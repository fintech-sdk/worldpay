defmodule Worldpay.NetworkPaymentTokens do
  @moduledoc """
  Worldpay **Network Payment Token (NPT) API** — manages network payment tokens
  that can be used across Worldpay and other acquirers.

  Network tokens are format-preserving 16-digit tokens issued by Visa or
  Mastercard. Unlike Worldpay tokens (which are Worldpay-specific), NPTs
  can be used with any acquirer that supports network tokenization.

  This module covers:
  - NPT provisioning, inquiry, update, deletion
  - Cryptogram provisioning per CIT
  - paymentAccountReference (PAR) support
  - Multi-acquirer portability
  """

  alias Worldpay.{Client, Config, Error}

  @base_path "/tokens/networkTokens"

  @doc "Provision a new network token (Visa or Mastercard)."
  @spec provision(map(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def provision(body, %Config{} = config) do
    Client.post(@base_path, body, [api: :npt, operation: :provision], config)
  end

  @doc "Retrieve a network token."
  @spec get(String.t(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def get(npt_id, %Config{} = config) do
    Client.get("#{@base_path}/#{npt_id}", [api: :npt, operation: :get], config)
  end

  @doc "Update a network token (e.g. update status)."
  @spec update(String.t(), map(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def update(npt_id, body, %Config{} = config) do
    Client.put("#{@base_path}/#{npt_id}", body, [api: :npt, operation: :update], config)
  end

  @doc "Delete a network token."
  @spec delete(String.t(), Config.t()) :: {:ok, nil} | {:error, Worldpay.Error.t()}
  def delete(npt_id, %Config{} = config) do
    Client.delete("#{@base_path}/#{npt_id}", [api: :npt, operation: :delete], config)
  end

  @doc """
  Provision a cryptogram for a CIT using a network token.

  Each CIT requires a fresh cryptogram. The cryptogram is single-use
  and expires within minutes.
  """
  @spec provision_cryptogram(String.t(), Config.t()) ::
          {:ok, map()} | {:error, Worldpay.Error.t()}
  def provision_cryptogram(npt_id, %Config{} = config) do
    Client.post(
      "#{@base_path}/#{npt_id}/cryptograms",
      %{},
      [api: :npt, operation: :provision_cryptogram],
      config
    )
  end
end

defmodule Worldpay.CustomerEventService do
  @moduledoc """
  Worldpay **Customer Event Service API** — lifecycle events for provisioned NPTs.

  This API delivers webhook events when network tokens change state:
  - Token created
  - Token updated (e.g. card reissued, new expiry)
  - Token deleted / expired

  These events are separate from payment lifecycle events (see `Worldpay.Webhooks`).

  ## Setup

  Register your Customer Event Service endpoint URL with your Worldpay
  Implementation Manager. Events are delivered as JSON webhooks.

  ## Event types

  | Type | Description |
  |---|---|
  | `token_created` | New NPT provisioned |
  | `token_updated` | NPT details changed (account updater) |
  | `token_suspended` | NPT temporarily suspended |
  | `token_resumed` | NPT re-activated |
  | `token_deleted` | NPT permanently deleted |
  | `token_expired` | NPT expiry reached |
  """

  @type ces_event :: %{
          type: atom(),
          network_token_id: String.t() | nil,
          payment_account_reference: String.t() | nil,
          card_last4: String.t() | nil,
          card_expiry: map() | nil,
          scheme: String.t() | nil,
          raw: map()
        }

  @doc "Parse an incoming Customer Event Service webhook body."
  @spec parse(String.t() | %{String.t() => term()}) :: {:ok, ces_event()}
  def parse(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> parse(map)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  def parse(body) when is_map(body) do
    event = %{
      type: classify_event(body["eventType"] || body["type"]),
      network_token_id: body["networkTokenId"],
      payment_account_reference: body["paymentAccountReference"],
      card_last4: get_in(body, ["paymentInstrument", "last4"]),
      card_expiry: get_in(body, ["paymentInstrument", "cardExpiryDate"]),
      scheme: body["scheme"],
      raw: body
    }

    {:ok, event}
  end

  defp classify_event("TOKEN_CREATED"), do: :token_created
  defp classify_event("TOKEN_UPDATED"), do: :token_updated
  defp classify_event("TOKEN_SUSPENDED"), do: :token_suspended
  defp classify_event("TOKEN_RESUMED"), do: :token_resumed
  defp classify_event("TOKEN_DELETED"), do: :token_deleted
  defp classify_event("TOKEN_EXPIRED"), do: :token_expired

  defp classify_event(other) when is_binary(other) do
    sanitized = other |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "_")
    # Bounded input: only Worldpay API constant strings arrive here.
    try do
      String.to_existing_atom(sanitized)
    rescue
      ArgumentError -> :erlang.binary_to_existing_atom(sanitized, :utf8)
    end
  end
end

defmodule Worldpay.SecurityTokenService do
  @moduledoc """
  Worldpay **Security Token Service (STS) API** — provision, exchange,
  and detokenize raw card/account numbers.

  The STS is used for PCI-scope-reducing tokenization:
  - Convert raw PANs to tokens (provision)
  - Swap tokens between token vaults (exchange)
  - Retrieve raw PANs from tokens (detokenize — PCI-accredited only)

  **Warning:** Detokenization retrieves raw card numbers and significantly
  increases PCI audit scope. Only use when absolutely necessary.
  """

  alias Worldpay.{Client, Config, Error}

  @sts_path "/security/tokens"

  @doc "Provision a token from a raw card number."
  @spec provision(map(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def provision(body, %Config{} = config) do
    Client.post(
      "#{@sts_path}/provision",
      body,
      [api: :sts, operation: :provision],
      config
    )
  end

  @doc "Exchange a token between vaults (inter-token exchange)."
  @spec exchange(map(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def exchange(body, %Config{} = config) do
    Client.post(
      "#{@sts_path}/exchange",
      body,
      [api: :sts, operation: :exchange],
      config
    )
  end

  @doc """
  Detokenize — retrieve the raw card number from a token.

  **PCI-accredited merchants only.** Using this endpoint subjects your
  environment to PCI DSS Level 1 audit requirements.
  """
  @spec detokenize(String.t(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def detokenize(token_reference, %Config{} = config) do
    Client.post(
      "#{@sts_path}/detokenize",
      %{"tokenReference" => token_reference},
      [api: :sts, operation: :detokenize],
      config
    )
  end
end

defmodule Worldpay.ForwardAPI do
  @moduledoc """
  Worldpay **Forward API** — PCI-scope-reducing proxy/tokenizer.

  The Forward API acts as a transparent proxy between your systems and
  third-party APIs. It tokenizes sensitive card data in-flight so that
  raw PANs never touch your servers.

  ## How it works

  1. You POST to the Forward API with card data + target endpoint
  2. Worldpay tokenizes the card data
  3. The request is forwarded to the target with tokens in place of PANs
  4. The response is returned to you

  Keeps merchants out of PCI scope for integrations with third-party
  processors, analytics platforms, or legacy systems.
  """

  alias Worldpay.{Client, Config, Error}

  @doc """
  Forward a request with card data to a target endpoint.

  Worldpay intercepts, tokenizes card fields, and forwards.

  ## body fields

  - `targetUrl` — the third-party endpoint to forward to
  - `method` — HTTP method (`"POST"` | `"GET"` | `"PUT"`)
  - `headers` — headers to pass through to target
  - `body` — request body (card fields will be tokenized)
  - `tokenizeFields` — list of field paths to tokenize before forwarding
  """
  @spec forward(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def forward(body, %Config{} = config) do
    Client.post(
      "/forward",
      body,
      [api: :forward_api, operation: :forward],
      config
    )
  end

  @doc "Detokenize in a forwarded response — retrieve raw values from tokens in a response."
  @spec detokenize_response(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def detokenize_response(body, %Config{} = config) do
    Client.post(
      "/forward/detokenize",
      body,
      [api: :forward_api, operation: :detokenize_response],
      config
    )
  end
end

defmodule Worldpay.TokenImport do
  @moduledoc """
  Worldpay **Token Import** — migrate tokens from a previous provider.

  Allows merchants switching to Worldpay to import existing card tokens,
  avoiding the need to re-collect card details from customers.

  Token import is handled via a secure SFTP file transfer process with
  Worldpay's implementation team. This module provides helpers for
  building the import manifest.

  ## Process

  1. Contact Worldpay IM to initiate token import
  2. Build an import manifest using `build_manifest/2`
  3. Encrypt the manifest (Worldpay provides PGP public key)
  4. Transfer to Worldpay SFTP
  5. Worldpay processes and returns a completion file

  ## Supported source vaults

  - Stripe tokens
  - Braintree tokens
  - Adyen tokens
  - Chase Paymentech tokens
  - Other PCI-compliant token vaults
  """

  @doc "Build a token import manifest entry."
  @spec build_entry(keyword()) :: %{String.t() => term()}
  def build_entry(opts) do
    %{
      "sourceTokenReference" => Keyword.fetch!(opts, :source_token),
      "sourceVault" => Keyword.fetch!(opts, :source_vault),
      "cardHolderName" => Keyword.get(opts, :card_holder_name),
      "cardNumberLastFour" => Keyword.get(opts, :last4),
      "expiryMonth" => Keyword.get(opts, :expiry_month),
      "expiryYear" => Keyword.get(opts, :expiry_year),
      "cardScheme" => Keyword.get(opts, :scheme),
      "merchantReference" => Keyword.get(opts, :merchant_reference)
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  @doc "Build a complete token import manifest (JSON)."
  @spec build_manifest([map()], keyword()) :: String.t()
  def build_manifest(entries, opts \\ []) do
    manifest = %{
      "merchantId" => Keyword.fetch!(opts, :merchant_id),
      "importDate" => Date.utc_today() |> Date.to_iso8601(),
      "totalRecords" => length(entries),
      "tokens" => entries
    }

    Jason.encode!(manifest, pretty: true)
  end

  @doc "Parse a token import completion file."
  @spec parse_completion(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_completion(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"results" => results} = body} ->
        summary = %{
          total: body["totalRecords"] || length(results),
          imported: Enum.count(results, &(&1["status"] == "imported")),
          failed: Enum.count(results, &(&1["status"] == "failed")),
          results: results
        }

        {:ok, summary}

      {:ok, body} ->
        {:ok, body}

      {:error, reason} ->
        {:error, {:json_decode_error, reason}}
    end
  end
end
