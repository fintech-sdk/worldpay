defmodule Worldpay.Payments do
  @moduledoc """
  Worldpay **Payments API** — orchestrated single-call flow.

  Combines FraudSight, 3DS authentication, token creation, and card
  authorization in a single POST. Supports all payment instrument types:
  plain card, Checkout SDK session, stored token, network token, Apple Pay,
  Google Pay, and AI agent delegate tokens (ACP).

  ## Example

      {:ok, auth} =
        Worldpay.Payments.authorize(
          %{
            "transactionReference" => "order-001",
            "merchant" => %{"entity" => "default"},
            "instruction" => %{
              "narrative" => %{"line1" => "My Store"},
              "value" => %{"amount" => 1999, "currency" => "GBP"},
              "paymentInstrument" => %{
                "type" => "card/plain",
                "cardHolderName" => "Jane Doe",
                "cardNumber" => "4444333322221111",
                "cardExpiryDate" => %{"month" => 5, "year" => 2035},
                "cvc" => "123"
              }
            }
          },
          config
        )
  """

  alias Worldpay.{Client, Config, Error}

  @path "/payments"

  @doc """
  Authorize a payment.

  The `instruction` map is submitted as the request body.

  ## Options

  - `:idempotency_key` — string; auto-generated if not supplied
  """
  @spec authorize(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def authorize(instruction, %Config{} = config, opts \\ []) do
    Client.post(
      @path,
      %{"instruction" => instruction},
      [api: :payments, operation: :authorize, idempotency_key: idempotency_key(opts)],
      config
    )
  end

  @doc "Full settlement of an authorized payment."
  @spec settle(String.t(), map(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def settle(payment_id_or_href, body \\ %{}, %Config{} = config, opts \\ []) do
    path = resolve_action_path(payment_id_or_href, "/settlements")

    Client.post(
      path,
      body,
      [api: :payments, operation: :settle, idempotency_key: idempotency_key(opts)],
      config
    )
  end

  @doc "Partial settlement."
  @spec partial_settle(String.t(), non_neg_integer(), String.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def partial_settle(payment_id, amount, currency, %Config{} = config, opts \\ []) do
    body = %{"instruction" => %{"value" => %{"amount" => amount, "currency" => currency}}}

    Client.post(
      "/payments/#{payment_id}/settlements",
      body,
      [api: :payments, operation: :partial_settle, idempotency_key: idempotency_key(opts)],
      config
    )
  end

  @doc "Cancel / reverse an authorized payment."
  @spec cancel(String.t(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def cancel(payment_id_or_href, %Config{} = config, opts \\ []) do
    path = resolve_action_path(payment_id_or_href, "/reversals")

    Client.post(
      path,
      %{},
      [api: :payments, operation: :cancel, idempotency_key: idempotency_key(opts)],
      config
    )
  end

  @doc "Full refund."
  @spec refund(String.t(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def refund(payment_id, %Config{} = config, opts \\ []) do
    Client.post(
      "/payments/#{payment_id}/refunds",
      %{},
      [api: :payments, operation: :refund, idempotency_key: idempotency_key(opts)],
      config
    )
  end

  @doc "Partial refund."
  @spec partial_refund(String.t(), non_neg_integer(), String.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def partial_refund(payment_id, amount, currency, %Config{} = config, opts \\ []) do
    body = %{"value" => %{"amount" => amount, "currency" => currency}}

    Client.post(
      "/payments/#{payment_id}/refunds",
      body,
      [api: :payments, operation: :partial_refund, idempotency_key: idempotency_key(opts)],
      config
    )
  end

  @doc "Retrieve a payment by ID."
  @spec get(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(payment_id, %Config{} = config) do
    Client.get("/payments/#{payment_id}", [api: :payments, operation: :get], config)
  end

  # ── private ───────────────────────────────────────────────────────────────

  @spec resolve_action_path(String.t(), String.t()) :: String.t()
  defp resolve_action_path("https://" <> _ = href, _suffix) do
    uri = URI.parse(href)
    uri.path || href
  end

  defp resolve_action_path(id, suffix), do: "/payments/#{id}#{suffix}"

  @spec idempotency_key(keyword()) :: String.t()
  defp idempotency_key(opts) do
    Keyword.get(opts, :idempotency_key, generate_key())
  end

  @spec generate_key() :: String.t()
  defp generate_key do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
end
