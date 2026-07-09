defmodule Worldpay.Express do
  @moduledoc """
  Worldpay **Express Interface** (Integrated Payments Express) — lighter POS
  integration path covering all in-store payment types.

  Supported payment types:
  - Credit card
  - Debit card (PIN and signature)
  - Check / ACH
  - Healthcare (FSA / HSA)
  - Electronic Benefits Transfer (EBT — SNAP and Cash)
  - Gift Card

  Supported transaction types:
  - Sale
  - Authorization
  - Authorization Completion (capture)
  - Void
  - Reversal
  - Credit / Refund
  - Balance Inquiry
  - Card Activation (Gift)
  - Recurring Transactions
  - Level 3 / Enhanced Data (line item detail)
  - Lodging Data
  - Duplicate Checking

  ## Configuration

      config :worldpay,
        express_url: "https://api.expresshost.net/payments/v2",
        express_account_id: "your-account-id",
        express_account_token: "your-account-token",
        express_application_id: "your-app-id",
        express_application_name: "MyApp",
        express_application_version: "1.0.0"
  """

  alias Worldpay.{Config, Error}
  require Logger

  @doc """
  Submit a Sale transaction.

  ## Options

  - `:pan` — card number
  - `:expiry` — MMYY
  - `:amount` — integer (cents)
  - `:track1` / `:track2` — raw track data (card-present)
  - `:emv_data` — EMV TLV data (chip)
  - `:pin_block` — encrypted PIN (debit)
  - `:cvc` — card security code (CNP)
  - `:payment_type` — `"Credit"` | `"Debit"` | `"EBTFoodStamp"` | `"EBTCashBenefit"` | `"GiftCard"` | `"Healthcare"`
  - `:duplicate_check_disable` — boolean (default false)
  - `:terminal_id` — terminal/lane identifier
  - `:clerk_number` — clerk/cashier identifier
  - `:reference_number` — merchant reference
  - `:ticket_number` — ticket / receipt number
  """
  @spec sale(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def sale(opts, %Config{} = config) do
    submit("CreditCardSale", build_transaction(opts), config)
  end

  @doc "Submit an Authorization (pre-auth)."
  @spec authorize(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def authorize(opts, %Config{} = config) do
    submit("CreditCardAuthorization", build_transaction(opts), config)
  end

  @doc "Submit an Authorization Completion (capture a pre-auth)."
  @spec capture(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def capture(opts, %Config{} = config) do
    transaction = build_transaction(opts)

    body =
      transaction
      |> Map.put("TransactionID", Keyword.fetch!(opts, :transaction_id))
      |> Map.put("ApprovalNumber", Keyword.get(opts, :approval_number))

    submit("CreditCardAuthorizationCompletion", body, config)
  end

  @doc "Void a previous transaction."
  @spec void(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def void(opts, %Config{} = config) do
    body = %{
      "Transaction" => %{
        "TransactionID" => Keyword.fetch!(opts, :transaction_id),
        "ReferenceNumber" => Keyword.get(opts, :reference_number),
        "TerminalID" => Keyword.get(opts, :terminal_id)
      }
    }

    submit("CreditCardVoid", body, config)
  end

  @doc "Submit a Reversal."
  @spec reverse(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def reverse(opts, %Config{} = config) do
    transaction = build_transaction(opts)

    body =
      transaction
      |> Map.put("TransactionID", Keyword.fetch!(opts, :transaction_id))

    submit("CreditCardReversal", body, config)
  end

  @doc "Submit a Credit (refund)."
  @spec credit(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def credit(opts, %Config{} = config) do
    submit("CreditCardCredit", build_transaction(opts), config)
  end

  @doc "Balance Inquiry (Debit, EBT, Gift Card)."
  @spec balance_inquiry(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def balance_inquiry(opts, %Config{} = config) do
    submit("CreditCardBalanceInquiry", build_transaction(opts), config)
  end

  @doc "Gift Card Activation."
  @spec gift_activate(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def gift_activate(opts, %Config{} = config) do
    submit("GiftCardActivation", build_transaction(opts), config)
  end

  @doc "Check / ACH sale."
  @spec check_sale(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def check_sale(opts, %Config{} = config) do
    transaction = build_transaction(opts)

    body =
      transaction
      |> Map.put("Check", %{
        "AccountNumber" => Keyword.fetch!(opts, :account_number),
        "RoutingNumber" => Keyword.fetch!(opts, :routing_number),
        "CheckNumber" => Keyword.get(opts, :check_number),
        "AccountType" => Keyword.get(opts, :account_type, "Checking")
      })

    submit("CheckSale", body, config)
  end

  @doc "Healthcare / FSA / HSA sale."
  @spec healthcare_sale(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def healthcare_sale(opts, %Config{} = config) do
    healthcare = %{
      "HealthcareAmounts" => %{
        "TotalHealthcareAmount" => Keyword.fetch!(opts, :healthcare_amount),
        "ClinicalAmount" => Keyword.get(opts, :clinical_amount, 0),
        "DentalAmount" => Keyword.get(opts, :dental_amount, 0),
        "VisionAmount" => Keyword.get(opts, :vision_amount, 0),
        "PrescriptionAmount" => Keyword.get(opts, :prescription_amount, 0)
      }
    }

    body =
      opts
      |> Keyword.put(:payment_type, "Healthcare")
      |> build_transaction()
      |> Map.merge(healthcare)

    submit("HealthcareSale", body, config)
  end

  @doc "Recurring transaction (stored credential MIT)."
  @spec recurring(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def recurring(opts, %Config{} = config) do
    transaction = build_transaction(opts)

    body =
      transaction
      |> Map.put("StoredCredential", %{
        "StoredCredentialType" => Keyword.get(opts, :stored_credential_type, "Recurring"),
        "InitialTransactionID" => Keyword.get(opts, :initial_transaction_id),
        "SchemeTransactionID" => Keyword.get(opts, :scheme_transaction_id)
      })

    submit("CreditCardSale", body, config)
  end

  # ── response helpers ───────────────────────────────────────────────────────

  @doc "True if Express response is approved."
  @spec approved?(%{String.t() => term()}) :: boolean()
  def approved?(%{"ExpressResponseCode" => code}), do: code in ["0", "00", "000"]
  @spec approved?(%{String.t() => term()}) :: boolean()
  def approved?(_), do: false

  @doc "Extract approval number from Express response."
  @spec approval_number(map()) :: String.t() | nil
  def approval_number(%{"Transaction" => %{"ApprovalNumber" => num}}), do: num
  def approval_number(_), do: nil

  @doc "Extract transaction ID from Express response."
  @spec transaction_id(map()) :: String.t() | nil
  def transaction_id(%{"Transaction" => %{"TransactionID" => id}}), do: id
  def transaction_id(_), do: nil

  @doc "Extract balance from Express response (debit/EBT/Gift)."
  @spec balance(map()) :: map() | nil
  def balance(%{"Card" => %{"AvailableBalance" => bal}}), do: %{"available" => bal}
  def balance(_), do: nil

  # ── private ───────────────────────────────────────────────────────────────

  defp build_transaction(opts) do
    payment_type = Keyword.get(opts, :payment_type, "Credit")

    card =
      %{
        "CardNumber" => Keyword.get(opts, :pan),
        "ExpirationMonth" => expiry_month(Keyword.get(opts, :expiry)),
        "ExpirationYear" => expiry_year(Keyword.get(opts, :expiry)),
        "CVV" => Keyword.get(opts, :cvc),
        "Track1Data" => Keyword.get(opts, :track1),
        "Track2Data" => Keyword.get(opts, :track2),
        "EMVData" => Keyword.get(opts, :emv_data),
        "PINBlock" => Keyword.get(opts, :pin_block)
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    transaction =
      %{
        "TransactionAmount" => Keyword.get(opts, :amount),
        "ReferenceNumber" => Keyword.get(opts, :reference_number, generate_ref()),
        "TicketNumber" => Keyword.get(opts, :ticket_number),
        "ClerkNumber" => Keyword.get(opts, :clerk_number),
        "TerminalID" => Keyword.get(opts, :terminal_id),
        "PaymentType" => payment_type,
        "DuplicateCheckDisableFlag" => Keyword.get(opts, :duplicate_check_disable, false),
        "DuplicateOverrideFlag" => Keyword.get(opts, :duplicate_override, false)
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)
      |> maybe_add_level3(opts)
      |> maybe_add_lodging(opts)

    %{"Card" => card, "Transaction" => transaction}
  end

  defp maybe_add_level3(txn, opts) do
    case Keyword.get(opts, :line_items) do
      nil ->
        txn

      items ->
        level3 =
          %{
            "DestinationZipCode" => Keyword.get(opts, :destination_zip),
            "DestinationCountryCode" => Keyword.get(opts, :destination_country),
            "ShipFromZipCode" => Keyword.get(opts, :ship_from_zip),
            "DiscountAmount" => Keyword.get(opts, :discount_amount),
            "TaxAmount" => Keyword.get(opts, :tax_amount),
            "ShippingAmount" => Keyword.get(opts, :shipping_amount),
            "DutyAmount" => Keyword.get(opts, :duty_amount),
            "PurchaseOrderNumber" => Keyword.get(opts, :po_number),
            "LineItems" => build_line_items(items)
          }
          |> Map.reject(fn {_, v} -> is_nil(v) end)

        Map.put(txn, "LevelIIIData", level3)
    end
  end

  defp maybe_add_lodging(txn, opts) do
    case Keyword.get(opts, :lodging) do
      nil ->
        txn

      lodging ->
        lodging_map =
          %{
            "CheckInDate" => lodging[:check_in],
            "CheckOutDate" => lodging[:check_out],
            "DurationOfStay" => lodging[:duration],
            "FolioNumber" => lodging[:folio_number],
            "RoomRate" => lodging[:room_rate],
            "ProgramCode" => lodging[:program_code],
            "ChargeType" => lodging[:charge_type],
            "FireSafetyIndicator" => lodging[:fire_safe]
          }
          |> Map.reject(fn {_, v} -> is_nil(v) end)

        Map.put(txn, "LodgingData", lodging_map)
    end
  end

  defp build_line_items(items) do
    Enum.map(items, fn item ->
      %{
        "ItemDescription" => item[:description],
        "ItemQuantity" => item[:quantity],
        "ItemUnitOfMeasure" => item[:unit_of_measure],
        "ItemUnitCostAmount" => item[:unit_cost],
        "ItemTotalAmount" => item[:total],
        "ItemDiscountAmount" => item[:discount],
        "ItemTaxAmount" => item[:tax],
        "ItemCommodityCode" => item[:commodity_code],
        "ItemProductCode" => item[:product_code]
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)
    end)
  end

  defp submit(transaction_type, body, %Config{} = config) do
    url = express_url()

    credentials = %{
      "AcceptorID" => Application.get_env(:worldpay, :express_account_id, ""),
      "AccountToken" => Application.get_env(:worldpay, :express_account_token, ""),
      "ApplicationID" => Application.get_env(:worldpay, :express_application_id, ""),
      "ApplicationName" => Application.get_env(:worldpay, :express_application_name, "Worldpay"),
      "ApplicationVersion" => Application.get_env(:worldpay, :express_application_version, "1.0")
    }

    payload = Map.merge(%{"Credentials" => credentials}, body)

    result =
      try do
        {:ok,
         Req.post!(url <> "/#{transaction_type}",
           json: payload,
           headers: [{"Content-Type", "application/json"}, {"Accept", "application/json"}],
           finch: Worldpay.Finch,
           receive_timeout: config.timeout
         )}
      rescue
        ex -> {:error, ex}
      end

    case result do
      {:ok, %{status: s, body: body}} when s in 200..299 ->
        {:ok, body}

      {:ok, %{status: s, body: body}} ->
        {:error, Error.from_response(s, body)}

      {:error, ex} ->
        {:error, Error.from_exception(ex)}
    end
  end

  defp express_url do
    case Application.get_env(:worldpay, :express_url) do
      nil ->
        case Application.get_env(:worldpay, :environment, :try) do
          :live -> "https://api.expresshost.net/payments/v2"
          _ -> "https://certtransaction.elementexpress.com/express.asmx/json"
        end

      url ->
        url
    end
  end

  defp expiry_month(nil), do: nil
  defp expiry_month(mmyy) when byte_size(mmyy) >= 2, do: String.slice(mmyy, 0, 2)

  defp expiry_year(nil), do: nil
  defp expiry_year(mmyy) when byte_size(mmyy) >= 4, do: "20" <> String.slice(mmyy, 2, 2)
  defp expiry_year(mmyy), do: mmyy

  defp generate_ref, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
