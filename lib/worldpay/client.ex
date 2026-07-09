defmodule Worldpay.Client do
  @moduledoc """
  Low-level HTTP client for all Worldpay REST APIs.

  Wraps `Req` with:

  - Basic Auth injection
  - `WP-Api-Version` header management
  - `WP-CorrelationId` per-request tracing header
  - JSON encode/decode
  - Telemetry spans on every call
  - Auto-generated idempotency keys on mutations
  - Optional circuit breaker via `:fuse`
  - XML client for WPG (`wpg_post/2`)
  """

  alias Worldpay.{Config, Error, Telemetry}

  require Logger

  # :fuse options: {{strategy, max_melt, period_ms}, {reset_strategy, reset_ms}}
  # Standard: allow 5 failures in 10 seconds, then open for 30 seconds.
  @fuse_opts {{:standard, 5, 10_000}, {:reset, 30_000}}

  @type header :: {String.t(), String.t()}
  @type headers :: [header()]
  @type result :: {:ok, map() | nil} | {:error, Error.t()}
  @type xml_result :: {:ok, String.t()} | {:error, Error.t()}

  @typep request_spec :: %{
           method: atom(),
           url: String.t(),
           body: %{String.t() => term()} | nil,
           query: keyword(),
           extra_headers: headers(),
           idempotency_key: String.t() | nil
         }

  @typep telemetry_ctx :: %{
           api: atom(),
           operation: atom(),
           start: integer()
         }

  @doc "GET request against the Access API."
  @spec get(String.t(), keyword(), Config.t()) :: result()
  def get(path, opts \\ [], %Config{} = config) do
    request(:get, path, nil, opts, config)
  end

  @doc "POST request against the Access API."
  @spec post(String.t(), map(), keyword(), Config.t()) :: result()
  def post(path, body, opts \\ [], %Config{} = config) do
    request(:post, path, body, opts, config)
  end

  @doc "PUT request."
  @spec put(String.t(), map(), keyword(), Config.t()) :: result()
  def put(path, body, opts \\ [], %Config{} = config) do
    request(:put, path, body, opts, config)
  end

  @doc "PATCH request."
  @spec patch(String.t(), map(), keyword(), Config.t()) :: result()
  def patch(path, body, opts \\ [], %Config{} = config) do
    request(:patch, path, body, opts, config)
  end

  @doc "DELETE request."
  @spec delete(String.t(), keyword(), Config.t()) :: result()
  def delete(path, opts \\ [], %Config{} = config) do
    request(:delete, path, nil, opts, config)
  end

  @doc "POST XML to the WPG endpoint."
  @spec wpg_post(String.t(), Config.t()) :: xml_result()
  def wpg_post(xml_body, %Config{} = config) do
    url = config.wpg_base_url <> "/frontdoor/xml"
    api = :wpg
    op = :submit
    start = Telemetry.start(api, op)

    headers = [
      {"Authorization", "Basic #{Config.wpg_basic_auth(config)}"},
      {"Content-Type", "text/xml; charset=utf-8"},
      {"Accept", "text/xml"}
    ]

    result =
      [url: url, headers: headers, body: xml_body]
      |> Req.new()
      |> run_request()

    case result do
      {:ok, %{status: s, body: body}} when s in 200..299 ->
        Telemetry.stop(api, op, start, s, :ok)
        {:ok, body}

      {:ok, %{status: s, body: body}} ->
        Telemetry.stop(api, op, start, s, :error)
        {:error, Error.from_response(s, body)}

      {:error, ex} ->
        Telemetry.exception(api, op, start, :error, ex)
        {:error, Error.from_exception(ex)}
    end
  end

  # ── private ───────────────────────────────────────────────────────────────

  @spec request(atom(), String.t(), %{String.t() => term()} | nil, keyword(), Config.t()) ::
          result()
  defp request(method, path, body, opts, %Config{} = config) do
    api = Keyword.get(opts, :api, :access)
    operation = Keyword.get(opts, :operation, :request)
    query = Keyword.get(opts, :query, [])
    extra_headers = Keyword.get(opts, :headers, [])
    idempotency_key = Keyword.get(opts, :idempotency_key)
    url = config.base_url <> path
    start = Telemetry.start(api, operation, %{method: method, url: url})

    request_spec = %{
      method: method,
      url: url,
      body: body,
      query: query,
      extra_headers: extra_headers,
      idempotency_key: idempotency_key
    }

    telemetry_ctx = %{api: api, operation: operation, start: start}

    case maybe_check_fuse(config, api) do
      {:error, _} = err -> err
      :ok -> execute_request(request_spec, telemetry_ctx, config)
    end
  end

  @spec execute_request(request_spec(), telemetry_ctx(), Config.t()) :: result()
  defp execute_request(request_spec, telemetry_ctx, config) do
    headers = build_headers(config, request_spec.extra_headers, request_spec.idempotency_key)

    req_opts =
      [
        method: request_spec.method,
        url: request_spec.url,
        headers: headers,
        params: request_spec.query,
        finch: Worldpay.Finch,
        receive_timeout: config.timeout,
        retry: :never,
        decode_json: [keys: :strings]
      ]
      |> maybe_put_body(request_spec.body)

    req_opts
    |> Req.new()
    |> run_request()
    |> handle_response(telemetry_ctx.api, telemetry_ctx.operation, telemetry_ctx.start, config)
  end

  @spec handle_response(
          {:ok, Req.Response.t()} | {:error, struct()},
          atom(),
          atom(),
          integer(),
          Config.t()
        ) :: result()
  defp handle_response({:ok, %{status: 204}}, api, operation, start, _config) do
    Telemetry.stop(api, operation, start, 204, :ok)
    {:ok, nil}
  end

  defp handle_response({:ok, %{status: s, body: b}}, api, operation, start, config)
       when s in 200..299 do
    Telemetry.stop(api, operation, start, s, :ok)
    maybe_reset_fuse(config, api)
    {:ok, b}
  end

  defp handle_response({:ok, %{status: s, body: b}}, api, operation, start, config) do
    Telemetry.stop(api, operation, start, s, :error)
    maybe_melt_fuse(config, api)
    {:error, Error.from_response(s, b)}
  end

  defp handle_response({:error, ex}, api, operation, start, config) do
    Telemetry.exception(api, operation, start, :error, ex)
    maybe_melt_fuse(config, api)
    {:error, Error.from_exception(ex)}
  end

  @spec build_headers(Config.t(), headers(), String.t() | nil) :: headers()
  defp build_headers(%Config{} = config, extra, idempotency_key) do
    base = [
      {"Authorization", "Basic #{Config.basic_auth(config)}"},
      {"WP-Api-Version", config.api_version},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"WP-CorrelationId", generate_correlation_id()}
    ]

    base =
      case idempotency_key do
        nil -> base
        key -> [{"Idempotency-Key", key} | base]
      end

    base ++ extra
  end

  @spec maybe_put_body(keyword(), %{String.t() => term()} | nil) :: keyword()
  defp maybe_put_body(opts, nil), do: opts
  defp maybe_put_body(opts, body) when is_map(body), do: Keyword.put(opts, :json, body)

  @spec run_request(Req.Request.t()) :: {:ok, Req.Response.t()} | {:error, struct()}
  defp run_request(req) do
    {:ok, Req.request!(req)}
  rescue
    ex -> {:error, ex}
  end

  @spec generate_correlation_id() :: String.t()
  defp generate_correlation_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  # ── circuit breaker ───────────────────────────────────────────────────────

  @spec maybe_check_fuse(Config.t(), atom()) :: :ok | {:error, Error.t()}
  defp maybe_check_fuse(%Config{circuit_breaker: true}, api) do
    name = fuse_name(api)
    install_fuse_if_needed(name)

    case :fuse.ask(name, :sync) do
      :ok ->
        :ok

      :blown ->
        {:error,
         %Error{
           type: :circuit_open,
           reason: :circuit_open,
           message: "Circuit breaker open for #{api}"
         }}
    end
  end

  defp maybe_check_fuse(%Config{circuit_breaker: false}, _api), do: :ok
  defp maybe_check_fuse(%Config{}, _api), do: :ok

  @spec maybe_melt_fuse(Config.t(), atom()) :: :ok
  defp maybe_melt_fuse(%Config{circuit_breaker: true}, api), do: :fuse.melt(fuse_name(api))
  defp maybe_melt_fuse(%Config{}, _api), do: :ok

  @spec maybe_reset_fuse(Config.t(), atom()) :: :ok
  defp maybe_reset_fuse(%Config{circuit_breaker: true}, api), do: :fuse.reset(fuse_name(api))
  defp maybe_reset_fuse(%Config{}, _api), do: :ok

  # Fixed, closed set of `api` values used throughout this client (see the
  # `api:` option passed to `request/5` across all Worldpay.* modules).
  # Building this map at compile time means every fuse-name atom already
  # exists in the atom table, so `fuse_name/1` never creates atoms at
  # runtime — it only looks them up.
  @known_apis [
    :access,
    :wpg,
    :account_payouts,
    :account_transfers,
    :apms,
    :balances,
    :batch_transactions,
    :boarding,
    :card_bin,
    :card_payments,
    :card_payouts,
    :exemptions,
    :forward_api,
    :fraudsight,
    :fx,
    :hpp,
    :lead_submission,
    :money_transfers,
    :npt,
    :parties,
    :payment_queries,
    :payments,
    :split_payments,
    :statements,
    :sts,
    :three_ds,
    :tokens,
    :verifications
  ]

  @fuse_names Map.new(@known_apis, &{&1, :"worldpay_#{&1}"})

  @spec fuse_name(atom()) :: atom()
  defp fuse_name(api), do: Map.fetch!(@fuse_names, api)

  @spec install_fuse_if_needed(atom()) :: :ok
  defp install_fuse_if_needed(name) do
    case :fuse.ask(name, :sync) do
      {:error, :not_found} ->
        # :fuse.install/2 expects {strategy_tuple, reset_tuple} — not a list.
        :fuse.install(name, @fuse_opts)

      _ ->
        :ok
    end
  end
end
