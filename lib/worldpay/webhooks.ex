defmodule Worldpay.Webhooks do
  @moduledoc """
  Worldpay webhook event parsing and dispatch.

  Worldpay pushes payment lifecycle events to your HTTPS endpoint as JSON.

  ## Setup

  Register your endpoint URL with your Worldpay Implementation Manager.
  Your endpoint must use HTTPS with a SHA-256+ certificate chain.

  ### Phoenix example

      # router.ex
      post "/worldpay/webhook", WorldpayWebhookController, :handle

      # controller
      def handle(conn, _params) do
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        case Worldpay.Webhooks.parse(body) do
          {:ok, event} ->
            MyApp.PaymentHandler.handle_event(event)
            send_resp(conn, 200, "ok")

          {:error, reason} ->
            Logger.error("Worldpay webhook parse error: \#{inspect(reason)}")
            send_resp(conn, 400, "bad request")
        end
      end

  ## Event types

  Card: `:authorized` · `:sent_for_settlement` · `:settled` · `:settlement_failed` ·
  `:charged_back` · `:chargeback_reversed` · `:dispute_expired` · `:refunded` ·
  `:partially_refunded` · `:cancelled` · `:refused` · `:sent_for_authorization` · `:updated`

  APM: `:apm_authorized` · `:apm_pending_merchant` · `:apm_failed` · `:apm_request_expired` · `:pix_confirmed`

  Payout: `:payout_sent` · `:payout_failed` · `:payout_reversed`

  Token: `:token_created` · `:network_token_created` · `:network_token_updated` · `:network_token_deleted`
  """

  require Logger

  @card_instrument_types ~w[
    card/plain
    card/checkout
    card/token
    card/networkToken
    card/networkToken+applepay
    card/networkToken+googlepay
  ]

  @type event :: %{
          type: atom(),
          payment_id: String.t() | nil,
          order_reference: String.t() | nil,
          command_id: String.t() | nil,
          downstream_reference: String.t() | nil,
          last_event: String.t() | nil,
          amount: %{String.t() => term()} | nil,
          currency: String.t() | nil,
          payment_instrument: %{String.t() => term()} | nil,
          risk_factors: [term()] | nil,
          raw: %{String.t() => term()}
        }

  @doc """
  Parse a raw Worldpay webhook JSON body into a structured event.

  Accepts a JSON binary or a pre-decoded string-keyed map.
  Returns `{:ok, event()}` or `{:error, {:json_decode_error, Jason.DecodeError.t()} | :invalid_body}`.
  """
  @spec parse(String.t() | %{String.t() => term()}) ::
          {:ok, event()} | {:error, {:json_decode_error, Jason.DecodeError.t()} | :invalid_body}
  def parse(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse(decoded)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  def parse(body) when is_map(body) do
    event = %{
      type: detect_type(body),
      payment_id: body["paymentId"],
      order_reference: body["orderReference"],
      command_id: body["commandId"],
      downstream_reference: body["downStreamReference"],
      last_event: body["lastEvent"],
      amount: body["value"],
      currency: get_in(body, ["value", "currency"]),
      payment_instrument: body["paymentInstrument"],
      risk_factors: body["riskFactors"],
      raw: body
    }

    {:ok, event}
  end

  def parse(_body), do: {:error, :invalid_body}

  @doc "Extract the event type atom from a raw webhook body map."
  @spec event_type(%{String.t() => term()}) :: atom()
  def event_type(body), do: detect_type(body)

  @doc "Dispatch a parsed event to a handler module implementing `Handler`."
  @spec handle(event(), module()) :: :ok | {:error, term()}
  def handle(event, handler_module) do
    handler_module.handle_event(event)
  rescue
    ex ->
      Logger.error("[Worldpay.Webhooks] Handler error: #{Exception.message(ex)}")
      {:error, ex}
  end

  # ── Handler behaviour ─────────────────────────────────────────────────────

  defmodule Handler do
    @moduledoc """
    Behaviour for Worldpay webhook event handlers.

    ## Example

        defmodule MyApp.PaymentHandler do
          @behaviour Worldpay.Webhooks.Handler

          @impl true
          def handle_event(%{type: :authorized, payment_id: id}) do
            Orders.mark_authorized(id)
            :ok
          end

          def handle_event(_event), do: :ok
        end
    """

    @callback handle_event(Worldpay.Webhooks.event()) :: :ok | {:error, term()}
  end

  # ── private ───────────────────────────────────────────────────────────────

  @spec detect_type(%{String.t() => term()}) :: atom()
  defp detect_type(%{"lastEvent" => last_event} = body) when is_binary(last_event) do
    last_event
    |> normalize_event_name()
    |> maybe_qualify_as_apm(body)
  end

  defp detect_type(%{"type" => type}) when is_binary(type), do: sanitize_atom(type)
  defp detect_type(%{"eventType" => type}) when is_binary(type), do: sanitize_atom(type)
  defp detect_type(_body), do: :unknown

  @spec normalize_event_name(String.t()) :: atom()
  defp normalize_event_name(~s(AUTHORISED)), do: :authorized
  defp normalize_event_name(~s(SENT_FOR_SETTLEMENT)), do: :sent_for_settlement
  defp normalize_event_name(~s(SETTLED)), do: :settled
  defp normalize_event_name(~s(SETTLEMENT_FAILED)), do: :settlement_failed
  defp normalize_event_name(~s(CHARGED_BACK)), do: :charged_back
  defp normalize_event_name(~s(CHARGEBACK_REVERSED)), do: :chargeback_reversed
  defp normalize_event_name(~s(DISPUTE_EXPIRED)), do: :dispute_expired
  defp normalize_event_name(~s(REFUNDED)), do: :refunded
  defp normalize_event_name(~s(PARTIALLY_REFUNDED)), do: :partially_refunded
  defp normalize_event_name(~s(CANCELLED)), do: :cancelled
  defp normalize_event_name(~s(CANCEL_REQUESTED)), do: :cancel_requested
  defp normalize_event_name(~s(CANCEL_FAILED)), do: :cancel_failed
  defp normalize_event_name(~s(REFUSED)), do: :refused
  defp normalize_event_name(~s(SENT_FOR_AUTHORISATION)), do: :sent_for_authorization
  defp normalize_event_name(~s(UPDATED)), do: :updated
  defp normalize_event_name(~s(PENDING_MERCHANT)), do: :apm_pending_merchant
  defp normalize_event_name(~s(FAILED)), do: :apm_failed
  defp normalize_event_name(~s(REQUEST_EXPIRED)), do: :apm_request_expired
  defp normalize_event_name(~s(PIX_CONFIRMED)), do: :pix_confirmed
  defp normalize_event_name(~s(PAYOUT_SENT)), do: :payout_sent
  defp normalize_event_name(~s(PAYOUT_FAILED)), do: :payout_failed
  defp normalize_event_name(~s(PAYOUT_REVERSED)), do: :payout_reversed
  defp normalize_event_name(~s(TOKEN_CREATED)), do: :token_created
  defp normalize_event_name(~s(NETWORK_TOKEN_CREATED)), do: :network_token_created
  defp normalize_event_name(~s(NETWORK_TOKEN_UPDATED)), do: :network_token_updated
  defp normalize_event_name(~s(NETWORK_TOKEN_DELETED)), do: :network_token_deleted
  defp normalize_event_name(other), do: sanitize_atom(other)

  @spec maybe_qualify_as_apm(atom(), %{String.t() => term()}) :: atom()
  defp maybe_qualify_as_apm(:authorized, %{"paymentInstrument" => %{"type" => t}})
       when is_binary(t) and t not in @card_instrument_types,
       do: :apm_authorized

  defp maybe_qualify_as_apm(type, _body), do: type

  # Sanitize to [a-z0-9_] before interning. The character set is bounded and
  # derives from Worldpay API constants, so atom table exhaustion is not a risk.
  @spec sanitize_atom(String.t()) :: atom()
  defp sanitize_atom(str) do
    sanitized =
      str
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_]/, "_")

    intern_atom(sanitized)
  end

  @spec intern_atom(String.t()) :: atom()
  defp intern_atom(s) do
    try do
      String.to_existing_atom(s)
    rescue
      ArgumentError -> :erlang.binary_to_existing_atom(s, :utf8)
    end
  end
end
