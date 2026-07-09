defmodule Worldpay.CardPayments do
  @moduledoc """
  Worldpay **Card Payments API** — modular card authorization.

  Supports CITs, MITs, partial auth, fast refunds, AFTs, account updater,
  PayFac, Level 2/3, airline data, MOTO, co-badged card routing, and more.

  Use `Worldpay.CardPayments.Features` to build advanced instruction maps.

  ## CIT example

      body = Worldpay.CardPayments.build_cit(
        transaction_reference: "txn-001",
        narrative: "My Store",
        amount: 1999,
        currency: "GBP",
        payment_instrument: %{"type" => "card/plain", ...}
      )
      {:ok, auth} = Worldpay.CardPayments.authorize(body, config)

  ## MIT (subscription) example

      body = Worldpay.CardPayments.build_mit(
        transaction_reference: "sub-002",
        narrative: "Monthly Plan",
        amount: 999,
        currency: "USD",
        payment_instrument: %{"type" => "card/token", "href" => token_href},
        scheme_reference: scheme_ref
      )
      {:ok, _} = Worldpay.CardPayments.mit(body, config)
  """

  alias Worldpay.{Client, Config, Error}

  @auth_path "/payments/authorizations"
  @mit_path "/payments/authorizations/merch-initiated"

  # ── Authorization ─────────────────────────────────────────────────────────

  @doc "Customer Initiated Transaction (CIT) authorization."
  @spec authorize(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def authorize(body, %Config{} = config, opts \\ []) do
    Client.post(
      @auth_path,
      body,
      [api: :card_payments, operation: :authorize, idempotency_key: key(opts)],
      config
    )
  end

  @doc "Merchant Initiated Transaction (MIT) — subscription / installment / unscheduled."
  @spec mit(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def mit(body, %Config{} = config, opts \\ []) do
    Client.post(
      @mit_path,
      body,
      [api: :card_payments, operation: :mit, idempotency_key: key(opts)],
      config
    )
  end

  # ── Settlement ────────────────────────────────────────────────────────────

  @doc "Full settlement of an authorized payment."
  @spec settle(String.t(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def settle(href_or_id, %Config{} = config, opts \\ []) do
    Client.post(
      full_settlement_path(href_or_id),
      %{},
      [api: :card_payments, operation: :settle, idempotency_key: key(opts)],
      config
    )
  end

  @doc "Partial settlement."
  @spec partial_settle(String.t(), non_neg_integer(), String.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def partial_settle(payment_id, amount, currency, %Config{} = config, opts \\ []) do
    body = %{"value" => %{"amount" => amount, "currency" => currency}}

    Client.post(
      "/payments/settlements/partials/#{payment_id}",
      body,
      [api: :card_payments, operation: :partial_settle, idempotency_key: key(opts)],
      config
    )
  end

  # ── Cancellation ──────────────────────────────────────────────────────────

  @doc "Cancel an authorization."
  @spec cancel(String.t(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def cancel(payment_id, %Config{} = config, opts \\ []) do
    Client.post(
      "/payments/authorizations/cancellations/#{payment_id}",
      %{},
      [api: :card_payments, operation: :cancel, idempotency_key: key(opts)],
      config
    )
  end

  # ── Refunds ───────────────────────────────────────────────────────────────

  @doc "Full refund."
  @spec refund(String.t(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def refund(payment_id, %Config{} = config, opts \\ []) do
    Client.post(
      "/payments/authorizations/refunds/#{payment_id}",
      %{},
      [api: :card_payments, operation: :refund, idempotency_key: key(opts)],
      config
    )
  end

  @doc "Partial refund."
  @spec partial_refund(String.t(), non_neg_integer(), String.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def partial_refund(payment_id, amount, currency, %Config{} = config, opts \\ []) do
    body = %{"value" => %{"amount" => amount, "currency" => currency}}

    Client.post(
      "/payments/authorizations/refunds/#{payment_id}",
      body,
      [api: :card_payments, operation: :partial_refund, idempotency_key: key(opts)],
      config
    )
  end

  @doc "Fast refund (≤30 min credit to eligible cards)."
  @spec fast_refund(String.t(), map(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def fast_refund(payment_id, body \\ %{}, %Config{} = config, opts \\ []) do
    Client.post(
      "/payments/authorizations/fastRefunds/#{payment_id}",
      body,
      [api: :card_payments, operation: :fast_refund, idempotency_key: key(opts)],
      config
    )
  end

  # ── Query ─────────────────────────────────────────────────────────────────

  @doc "Retrieve payment events."
  @spec events(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def events(payment_id, %Config{} = config) do
    Client.get(
      "/payments/events/#{payment_id}",
      [api: :card_payments, operation: :events],
      config
    )
  end

  @doc "Retrieve a single payment by ID."
  @spec get(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(payment_id, %Config{} = config) do
    Client.get(
      "/payments/authorizations/#{payment_id}",
      [api: :card_payments, operation: :get],
      config
    )
  end

  # ── Account Updater convenience ───────────────────────────────────────────

  @doc """
  Subsequent CIT with real-time Account Updater (Visa).

  Sets `requestAccountUpdater: true` in the instruction body.
  If the card was reissued, the response includes `updatedPaymentInstrument`.
  """
  @spec authorize_with_account_updater(map(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def authorize_with_account_updater(body, %Config{} = config, opts \\ []) do
    updated =
      update_in(body, ["instruction"], fn instr ->
        Map.put(instr || %{}, "requestAccountUpdater", true)
      end)

    authorize(updated, config, opts)
  end

  # ── Instruction builders ──────────────────────────────────────────────────

  @doc "Build a standard CIT instruction map."
  @spec build_cit(keyword()) :: %{String.t() => term()}
  def build_cit(fields) do
    %{
      "transactionReference" => Keyword.fetch!(fields, :transaction_reference),
      "merchant" => %{"entity" => Keyword.get(fields, :entity, "default")},
      "instruction" => %{
        "narrative" => %{"line1" => Keyword.fetch!(fields, :narrative)},
        "value" => %{
          "amount" => Keyword.fetch!(fields, :amount),
          "currency" => Keyword.fetch!(fields, :currency)
        },
        "paymentInstrument" => Keyword.fetch!(fields, :payment_instrument)
      }
    }
  end

  @doc "Build a standard MIT subscription instruction map."
  @spec build_mit(keyword()) :: %{String.t() => term()}
  def build_mit(fields) do
    %{
      "transactionReference" => Keyword.fetch!(fields, :transaction_reference),
      "merchant" => %{"entity" => Keyword.get(fields, :entity, "default")},
      "instruction" => %{
        "narrative" => %{"line1" => Keyword.fetch!(fields, :narrative)},
        "value" => %{
          "amount" => Keyword.fetch!(fields, :amount),
          "currency" => Keyword.fetch!(fields, :currency)
        },
        "paymentInstrument" => Keyword.fetch!(fields, :payment_instrument),
        "customerAgreement" => %{
          "type" => Keyword.get(fields, :agreement_type, "subscription"),
          "storedCardUsage" => "subsequent",
          "schemeReference" => Keyword.fetch!(fields, :scheme_reference)
        }
      }
    }
  end

  # ── private ───────────────────────────────────────────────────────────────

  @spec full_settlement_path(String.t()) :: String.t()
  defp full_settlement_path("https://" <> _ = href) do
    uri = URI.parse(href)
    uri.path || href
  end

  defp full_settlement_path(id), do: "/payments/settlements/full/#{id}"

  @spec key(keyword()) :: String.t()
  defp key(opts), do: Keyword.get(opts, :idempotency_key, generate_key())

  @spec generate_key() :: String.t()
  defp generate_key, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
end
