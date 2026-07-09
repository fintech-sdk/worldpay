defmodule Worldpay.PaymentQueries do
  @moduledoc """
  Worldpay **Payment Queries API** — query payment history.

  This is an aggregation service with up to 60 seconds of latency.
  Not suitable for real-time status checks immediately after payment.

  ## Query modes

  - By date range (from 25 Jun 2024 onward; paginated)
  - By `transactionReference`
  - By `paymentId` (single payment, full detail)
  - Historical (pre-Jun 2024; minimal fields; requires `entityReference`)
  """

  alias Worldpay.{Client, Config, Error}

  @path "/query/payments"

  @doc "Query payments by date range."
  @spec by_date_range(String.t(), String.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def by_date_range(start_date, end_date, %Config{} = config, opts \\ []) do
    query =
      [startDate: start_date, endDate: end_date]
      |> add_if_present(:pageSize, Keyword.get(opts, :page_size))
      |> add_if_present(:pageNumber, Keyword.get(opts, :page_number))

    Client.get(@path, [api: :payment_queries, operation: :by_date_range, query: query], config)
  end

  @doc "Query payments by transaction reference."
  @spec by_transaction_reference(String.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def by_transaction_reference(ref, %Config{} = config, opts \\ []) do
    query =
      [transactionReference: ref]
      |> add_if_present(:entityReference, Keyword.get(opts, :entity_reference))

    Client.get(@path, [api: :payment_queries, operation: :by_reference, query: query], config)
  end

  @doc "Retrieve a single payment by `paymentId` (full detail)."
  @spec by_id(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def by_id(payment_id, %Config{} = config) do
    Client.get(
      "#{@path}/#{payment_id}",
      [api: :payment_queries, operation: :by_id],
      config
    )
  end

  @spec add_if_present(
          [{atom(), term()}, ...],
          :pageSize | :pageNumber | :entityReference,
          term()
        ) ::
          [{atom(), term()}, ...]
  defp add_if_present(list, _key, nil), do: list
  defp add_if_present(list, key, val), do: Keyword.put(list, key, val)
end

defmodule Worldpay.CardBIN do
  @moduledoc """
  Worldpay **Card BIN API** — issuer, scheme, and capability lookup.

  Accepts first 6 or 8 digits of a PAN.

  ## Response fields

  - `brand` — list of card brand strings (multi-brand for co-badged)
  - `fundingType` — `"credit"` | `"debit"` | `"prepaid"` | `"chargeCard"` | `"deferredDebit"`
  - `issuerName` — issuing bank name
  - `countryCode` — ISO 3166-1 Alpha-2
  - `dccAllowed` — boolean
  - `anonymousPrepaid` — boolean
  - `category` — `"consumer"` | `"commercial"`
  """

  alias Worldpay.{Client, Config, Error}

  @doc "BIN lookup v1."
  @spec lookup(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def lookup(bin, %Config{} = config) when byte_size(bin) in [6, 8] do
    Client.get("/cardBin/#{bin}", [api: :card_bin, operation: :lookup], config)
  end

  @doc "BIN lookup v2 (Apr 2026 — expanded response)."
  @spec lookup_v2(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def lookup_v2(bin, %Config{} = config) when byte_size(bin) in [6, 8] do
    Client.get("/cardBin/v2/#{bin}", [api: :card_bin, operation: :lookup_v2], config)
  end
end

defmodule Worldpay.Verifications do
  @moduledoc """
  Worldpay **Verifications API** — card and bank account verification.

  ## Card verification

      {:ok, result} = Worldpay.Verifications.verify_card(%{
        "transactionReference" => "verify-001",
        "merchant" => %{"entity" => "default"},
        "instruction" => %{
          "narrative" => %{"line1" => "Active Card Check"},
          "paymentInstrument" => %{"type" => "card/plain", ...}
        }
      }, config)

      result["outcome"]  # => "verified" | "notVerified" | "verificationFailed"

  ## Beneficiary Account Verification

      {:ok, result} = Worldpay.Verifications.verify_account(%{
        "merchant" => %{"entity" => "default"},
        "payoutInstrument" => %{
          "type" => "bankAccount",
          "accountNumber" => "12345678",
          "routingNumber" => "021000021"
        }
      }, config)
  """

  alias Worldpay.{Client, Config, Error}

  @doc "Intelligent card-on-file verification."
  @spec verify_card(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def verify_card(body, %Config{} = config) do
    Client.post(
      "/verifications/customers/cardOnFile",
      body,
      [api: :verifications, operation: :verify_card],
      config
    )
  end

  @doc "Dynamic card-on-file verification (with `storedCredentials.reason`)."
  @spec verify_card_dynamic(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def verify_card_dynamic(body, %Config{} = config) do
    Client.post(
      "/verifications/customers/dynamicCardOnFile",
      body,
      [api: :verifications, operation: :verify_card_dynamic],
      config
    )
  end

  @doc "Beneficiary Account Verification — verify bank account before payout."
  @spec verify_account(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def verify_account(body, %Config{} = config) do
    Client.post(
      "/beneficiary-account-verifications",
      body,
      [api: :verifications, operation: :verify_account],
      config
    )
  end
end

defmodule Worldpay.AccountUpdater do
  @moduledoc """
  Worldpay **Account Updater** — keep stored card credentials current.

  ## Real-time (Visa, Access APIs)

  Set `requestAccountUpdater: true` in the instruction on a subsequent CIT.
  Use `Worldpay.CardPayments.authorize_with_account_updater/3` for convenience.

  ## File-based batch (WPG / cnpAPI)

  Build batch XML with the helpers here and submit via SFTP.
  Completion file returned ~5 business days later.

  ### Batch limits

  - Max 20,000 changes per batch
  - Max 9,999 batches per session file
  - Max 1,000,000 changes per session file
  """

  @doc "Build an accountUpdate element for a card."
  @spec build_card_update(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def build_card_update(order_id, report_group, card_number, exp_date) do
    """
    <accountUpdate id="#{order_id}" reportGroup="#{report_group}">
      <orderId>#{order_id}</orderId>
      <card>
        <type>VI</type>
        <number>#{card_number}</number>
        <expDate>#{exp_date}</expDate>
      </card>
    </accountUpdate>
    """
  end

  @doc "Build an accountUpdate element for a token."
  @spec build_token_update(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def build_token_update(order_id, report_group, cnp_token, exp_date) do
    """
    <accountUpdate id="#{order_id}" reportGroup="#{report_group}">
      <orderId>#{order_id}</orderId>
      <token>
        <cnpToken>#{cnp_token}</cnpToken>
        <expDate>#{exp_date}</expDate>
      </token>
    </accountUpdate>
    """
  end

  @doc "Wrap account update elements in a batch session file."
  @spec build_batch(String.t(), String.t(), String.t(), [String.t()]) :: String.t()
  def build_batch(request_id, batch_id, merchant_id, updates)
      when length(updates) <= 20_000 do
    updates_xml = Enum.join(updates, "\n")
    cnp_user = System.get_env("WORLDPAY_CNP_USER", "")
    cnp_password = System.get_env("WORLDPAY_CNP_PASSWORD", "")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <cnpRequest version="12.0" xmlns="http://www.vantiv.cnp.com/schema"
        id="#{request_id}" numBatchRequests="1">
      <authentication>
        <user>#{cnp_user}</user>
        <password>#{cnp_password}</password>
      </authentication>
      <batchRequest id="#{batch_id}"
          numAccountUpdates="#{length(updates)}"
          merchantId="#{merchant_id}">
        #{updates_xml}
      </batchRequest>
    </cnpRequest>
    """
  end
end
