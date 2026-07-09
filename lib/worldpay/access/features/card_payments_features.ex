defmodule Worldpay.CardPayments.Features do
  @moduledoc """
  Builder helpers for advanced Card Payments API features.

  All functions return maps that can be merged into a Card Payments
  `instruction` map before calling `Worldpay.CardPayments.authorize/3`
  or `Worldpay.CardPayments.mit/3`.

  ## Usage

      instruction =
        %{
          "transactionReference" => "txn-001",
          "merchant" => Worldpay.CardPayments.Features.merchant("entity-ref"),
          "instruction" => %{
            "narrative" => %{"line1" => "My Store"},
            "value" => %{"amount" => 5000, "currency" => "USD"},
            "paymentInstrument" => %{"type" => "card/token", "href" => token_href}
          }
        }
        |> Worldpay.CardPayments.Features.with_partial_auth()
        |> Worldpay.CardPayments.Features.with_moto()
        |> Worldpay.CardPayments.Features.with_level3(line_items: [...])

      {:ok, auth} = Worldpay.CardPayments.authorize(instruction, config)
  """

  # ── Merchant helpers ──────────────────────────────────────────────────────

  @doc """
  Build a merchant map with optional PayFac sub-merchant data.

  ## Options

  - `:mcc` — merchant category code (overrides account-level MCC)
  - `:payfac` — PayFac map (schemeId, independentSalesOrganizationId, subMerchant)
  """
  @spec merchant(String.t(), keyword()) :: %{String.t() => term()}
  def merchant(entity, opts \\ []) do
    %{"entity" => entity}
    |> maybe_put("mcc", Keyword.get(opts, :mcc))
    |> maybe_put("paymentFacilitator", build_payfac(Keyword.get(opts, :payfac)))
  end

  @doc "Build a PayFac (Payment Facilitator) object."
  @spec build_payfac(keyword() | nil) :: %{String.t() => term()} | nil
  def build_payfac(nil), do: nil

  def build_payfac(opts) when is_list(opts) do
    sub = Keyword.get(opts, :sub_merchant)

    %{}
    |> maybe_put("schemeId", Keyword.get(opts, :scheme_id))
    |> maybe_put("independentSalesOrganizationId", Keyword.get(opts, :iso_id))
    |> maybe_put(
      "subMerchant",
      if sub do
        %{}
        |> maybe_put("name", sub[:name])
        |> maybe_put("merchantId", sub[:merchant_id])
        |> maybe_put("address", sub[:address])
        |> maybe_put("mcc", sub[:mcc])
        |> maybe_put("countryCode", sub[:country_code])
        |> maybe_put("url", sub[:url])
        |> maybe_put("phone", sub[:phone])
      end
    )
  end

  # ── Partial authorization ─────────────────────────────────────────────────

  @doc """
  Enable partial authorization on a CIT.

  When the issuer approves less than the requested amount,
  `amounts.authorized` in the response will differ from `amounts.requested`.

  Test with `instruction.value.amount` magic values in Try environment.
  """
  @spec with_partial_auth(%{String.t() => term()}) :: %{String.t() => term()}
  def with_partial_auth(body) do
    put_in_instruction(body, "acceptPartialAuthorization", %{"enabled" => true})
  end

  # ── Incremental authorization ─────────────────────────────────────────────

  @doc """
  Build an incremental authorization body (extend a pre-authorization amount).

  Pass the original `payment_id` and the additional amount to authorize.
  """
  @spec incremental_auth(String.t(), non_neg_integer(), String.t()) :: %{String.t() => term()}
  def incremental_auth(payment_id, additional_amount, currency) do
    %{
      "paymentId" => payment_id,
      "instruction" => %{
        "value" => %{"amount" => additional_amount, "currency" => currency}
      }
    }
  end

  # ── MOTO ─────────────────────────────────────────────────────────────────

  @doc "Flag a payment as Mail Order / Telephone Order (MOTO)."
  @spec with_moto(%{String.t() => term()}) :: %{String.t() => term()}
  def with_moto(body) do
    put_in_instruction(body, "orderSource", "MOTO")
  end

  # ── Debt repayment ────────────────────────────────────────────────────────

  @doc "Flag a payment as a debt repayment (MCC 6012/6051 Mastercard requirement)."
  @spec with_debt_repayment(%{String.t() => term()}) :: %{String.t() => term()}
  def with_debt_repayment(body) do
    put_in_instruction(body, "debtRepayment", true)
  end

  # ── Surcharge & convenience fees ──────────────────────────────────────────

  @doc """
  Add a surcharge to a card payment.

  `surcharge_amount` is in minor currency units. Credit cards only.
  Cannot be combined with convenience fees.
  """
  @spec with_surcharge(%{String.t() => term()}, non_neg_integer(), String.t()) :: %{
          String.t() => term()
        }
  def with_surcharge(body, surcharge_amount, currency) do
    put_in_instruction(body, "surcharge", %{
      "value" => %{"amount" => surcharge_amount, "currency" => currency}
    })
  end

  @doc """
  Add a convenience fee to a card payment.

  Applies to all payment methods (unlike surcharge).
  """
  @spec with_convenience_fee(%{String.t() => term()}, non_neg_integer(), String.t()) :: %{
          String.t() => term()
        }
  def with_convenience_fee(body, fee_amount, currency) do
    put_in_instruction(body, "convenienceFee", %{
      "value" => %{"amount" => fee_amount, "currency" => currency}
    })
  end

  # ── Split funding reference ───────────────────────────────────────────────

  @doc """
  Add a split funding reference to route settlement to a secondary bank account.

  Used for simple two-party splits at settlement time (no Marketplace required).
  """
  @spec with_split_funding_reference(%{String.t() => term()}, String.t()) :: %{
          String.t() => term()
        }
  def with_split_funding_reference(body, reference) do
    put_in_instruction(body, "splitFundingReference", reference)
  end

  @doc "Add an orderReference to group payments together."
  @spec with_order_reference(%{String.t() => term()}, String.t()) :: %{String.t() => term()}
  def with_order_reference(body, order_ref) do
    Map.put(body, "orderReference", order_ref)
  end

  # ── MCC 6012 / 6051 (Financial services) ─────────────────────────────────

  @doc """
  Add MCC 6012 (UK financial services) mandatory data.

  Required by Visa Europe for UK financial services merchants.

  ## Options

  - `:surname` — cardholder surname (required)
  - `:account_first6` — first 6 digits of cardholder's primary account (required)
  - `:account_last4` — last 4 digits (required)
  - `:date_of_birth` — cardholder DOB in YYYY-MM-DD (required)
  - `:postcode` — cardholder postcode (required for Visa)
  """
  @spec with_mcc6012(%{String.t() => term()}, keyword()) :: %{String.t() => term()}
  def with_mcc6012(body, opts) do
    financial_services =
      %{
        "surname" => Keyword.fetch!(opts, :surname),
        "accountNumber" => %{
          "first6Digits" => Keyword.fetch!(opts, :account_first6),
          "last4Digits" => Keyword.fetch!(opts, :account_last4)
        },
        "dateOfBirth" => Keyword.fetch!(opts, :date_of_birth),
        "postcode" => Keyword.get(opts, :postcode)
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    put_in_instruction(body, "financialServices", financial_services)
  end

  # ── Airline data ──────────────────────────────────────────────────────────

  @doc """
  Add airline itinerary data for lower interchange rates.

  ## Options

  - `:passenger_name` — name on ticket
  - `:departure_date` — ISO 8601 date
  - `:origin` — IATA airport code
  - `:destination` — IATA airport code
  - `:ticket_number` — airline ticket number
  - `:restricted_ticket` — boolean
  - `:legs` — list of `%{origin:, destination:, carrier_code:, flight_number:, fare_basis_code:, stopover:}`
  - `:passengers` — list of `%{first_name:, last_name:, date_of_birth:}`
  """
  @spec with_airline_data(%{String.t() => term()}, keyword()) :: %{String.t() => term()}
  def with_airline_data(body, opts) do
    airline =
      %{
        "passengerName" => Keyword.get(opts, :passenger_name),
        "departureDate" => Keyword.get(opts, :departure_date),
        "origin" => Keyword.get(opts, :origin),
        "destination" => Keyword.get(opts, :destination),
        "ticketNumber" => Keyword.get(opts, :ticket_number),
        "restrictedTicket" => Keyword.get(opts, :restricted_ticket),
        "legs" => build_legs(Keyword.get(opts, :legs, [])),
        "passengers" => build_passengers(Keyword.get(opts, :passengers, []))
      }
      |> Map.reject(fn {_, v} -> is_nil(v) or v == [] end)

    put_in_instruction(body, "airline", airline)
  end

  # ── Level 2 / Level 3 (Corporate purchasing) ─────────────────────────────

  @doc """
  Add Level 2 purchasing card data (reduces interchange).

  ## Options

  - `:purchase_order_number` — PO number
  - `:customer_reference` — buyer-supplied reference
  - `:sales_tax` — tax amount in minor units
  - `:destination_postal_code` — ship-to postcode
  """
  @spec with_level2(%{String.t() => term()}, keyword()) :: %{String.t() => term()}
  def with_level2(body, opts) do
    level2 =
      %{
        "purchaseOrderNumber" => Keyword.get(opts, :purchase_order_number),
        "customerReference" => Keyword.get(opts, :customer_reference),
        "salesTax" => amount_map(Keyword.get(opts, :sales_tax), Keyword.get(opts, :currency)),
        "destinationPostalCode" => Keyword.get(opts, :destination_postal_code)
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    put_in_instruction(body, "level2", level2)
  end

  @doc """
  Add Level 3 purchasing card data with line items (lowest interchange tier).

  ## Options (all from Level 2, plus)

  - `:line_items` — list of item maps with keys:
    - `:description`, `:quantity`, `:unit_code`, `:unit_cost`, `:tax_amount`, `:total_amount`
  - `:discount_amount` — discount in minor units
  - `:shipping_amount` — shipping in minor units
  - `:duty_amount` — customs duty in minor units
  """
  @spec with_level3(%{String.t() => term()}, keyword()) :: %{String.t() => term()}
  def with_level3(body, opts) do
    currency = Keyword.get(opts, :currency)

    level3 =
      %{
        "purchaseOrderNumber" => Keyword.get(opts, :purchase_order_number),
        "customerReference" => Keyword.get(opts, :customer_reference),
        "salesTax" => amount_map(Keyword.get(opts, :sales_tax), currency),
        "discountAmount" => amount_map(Keyword.get(opts, :discount_amount), currency),
        "shippingAmount" => amount_map(Keyword.get(opts, :shipping_amount), currency),
        "dutyAmount" => amount_map(Keyword.get(opts, :duty_amount), currency),
        "destinationPostalCode" => Keyword.get(opts, :destination_postal_code),
        "lineItems" => build_line_items(Keyword.get(opts, :line_items, []), currency)
      }
      |> Map.reject(fn {_, v} -> is_nil(v) or v == [] end)

    put_in_instruction(body, "level3", level3)
  end

  # ── Latin America installments ────────────────────────────────────────────

  @doc """
  Add LatAm installment data.

  ## Options

  - `:number_of_installments` — integer (required)
  - `:installment_type` — "equalInstallments" | "unequalInstallments" (default: equalInstallments)
  - `:customer_document_reference` — CPF/RUT (required for some markets)
  - `:document_type` — "CPF" | "RUT" | ...
  """
  @spec with_latam_installments(%{String.t() => term()}, keyword()) :: %{String.t() => term()}
  def with_latam_installments(body, opts) do
    installments = %{
      "numberOfInstallments" => Keyword.fetch!(opts, :number_of_installments),
      "installmentType" => Keyword.get(opts, :installment_type, "equalInstallments")
    }

    body =
      if ref = Keyword.get(opts, :customer_document_reference) do
        type = Keyword.get(opts, :document_type, "CPF")

        put_in_instruction(body, "customerIdentityDocuments", [
          %{"type" => type, "reference" => ref}
        ])
      else
        body
      end

    put_in_instruction(body, "installments", installments)
  end

  # ── South Korea / Toss Pay domestic ──────────────────────────────────────

  @doc """
  Add customerData for South Korea domestic card payments (Toss Pay).

  ## Options

  - `:card_company_id` — Korean card company identifier
  - `:installment_months` — number of installment months (0 = lump sum)
  """
  @spec with_korea_domestic(%{String.t() => term()}, keyword()) :: %{String.t() => term()}
  def with_korea_domestic(body, opts) do
    customer_data =
      %{
        "cardCompanyId" => Keyword.get(opts, :card_company_id),
        "installmentMonths" => Keyword.get(opts, :installment_months, 0)
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    put_in_instruction(body, "customerData", customer_data)
  end

  # ── Crypto ramp ───────────────────────────────────────────────────────────

  @doc """
  Add crypto ramp provider identifiers.

  Required for crypto purchase transactions (MCC 6051).

  ## Options

  - `:transaction_identifier` — crypto exchange transaction ID
  - `:affiliate_details` — `%{name:, id:}`
  """
  @spec with_crypto_ramp(%{String.t() => term()}, keyword()) :: %{String.t() => term()}
  def with_crypto_ramp(body, opts) do
    crypto =
      %{
        "transactionIdentifier" => Keyword.get(opts, :transaction_identifier),
        "affiliateDetails" => build_affiliate(Keyword.get(opts, :affiliate_details))
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    put_in_instruction(body, "cryptoRamp", crypto)
  end

  # ── Co-badged card routing ────────────────────────────────────────────────

  @doc """
  Set preferred card brand for co-badged cards.

  Valid values: `"visa"`, `"mastercard"`, `"cartesBancaires"`,
  `"unionPay"`, `"eftpos"`, `"maestro"`, `"elo"`.
  """
  @spec with_preferred_card_brand(%{String.t() => term()}, String.t()) :: %{String.t() => term()}
  def with_preferred_card_brand(body, brand) do
    put_in_instruction(body, "preferredCardBrand", brand)
  end

  # ── AFT (Account Funding Transactions) ───────────────────────────────────

  @doc """
  Full AFT funds transfer builder.

  ## `type` values
  `"purchase"` | `"withdrawal"` | `"prepaidLoad"` | `"quasiCash"` | `"businessToBusiness"`

  ## `purpose` values (full enum)
  `"businessToBusiness"` | `"creditCardRepayment"` | `"crypto"` | `"crowdLending"` |
  `"debitCard"` | `"education"` | `"emergency"` | `"familySupport"` | `"gift"` |
  `"giftCard"` | `"goodwill"` | `"loanRepayment"` | `"medicalTreatment"` | `"others"` |
  `"pension"` | `"salary"` | `"taxRefund"` | `"travelAndExpense"` | `"utilities"` |
  `"walletTopUp"` | `"walletWithdrawal"` | `"gamblingPayout"`

  ## Sender fields (keyword list)
  - `:first_name`, `:middle_name`, `:last_name`
  - `:date_of_birth` — YYYY-MM-DD (required for some cross-border)
  - `:document_reference` — Tax ID / national ID (LatAm)
  - `:address` — map

  ## Recipient account types
  - `%{type: "card", href: token_href}`
  - `%{type: "bank", account_number: "...", routing_number: "..."}`
  - `%{type: "wallet", wallet_reference: "...", wallet_provider: "..."}`
  """
  @spec build_aft(String.t(), String.t(), keyword(), keyword()) :: %{String.t() => term()}
  def build_aft(type, purpose, sender_opts, recipient_opts) do
    %{
      "fundsTransfer" => %{
        "type" => type,
        "purpose" => purpose,
        "sender" => build_aft_sender(sender_opts),
        "recipient" => build_aft_recipient(recipient_opts)
      }
    }
  end

  # ── 3DS bypass controls (Jun 2026) ───────────────────────────────────────

  @doc """
  Add 3DS bypass controls (Jun 2026).

  ## Options

  - `:bypass_on` — list of conditions: `["frictionless", "lowValue"]`
  - `:continue_on` — list of error conditions to ignore: `["authenticationOutage"]`
  """
  @spec with_three_ds_bypass(%{String.t() => term()}, keyword()) :: %{String.t() => term()}
  def with_three_ds_bypass(body, opts) do
    three_ds =
      %{}
      |> maybe_put("bypassOn", Keyword.get(opts, :bypass_on))
      |> maybe_put("continueOn", Keyword.get(opts, :continue_on))

    put_in_instruction(
      body,
      "threeDS",
      Map.merge(get_in(body, ["instruction", "threeDS"]) || %{}, three_ds)
    )
  end

  # ── ACP (Agentic Commerce Protocol) ──────────────────────────────────────

  @doc """
  Add ACP (Agentic Commerce Protocol) delegate token for AI agent payments (Feb 2026).

  The `delegate_token` is issued by Worldpay to a trusted AI agent.
  """
  @spec with_acp_delegate(%{String.t() => term()}, String.t()) :: %{String.t() => term()}
  def with_acp_delegate(body, delegate_token) do
    put_in_instruction(body, "agenticCommerce", %{"delegateToken" => delegate_token})
  end

  # ── Request auto settlement ───────────────────────────────────────────────

  @doc "Enable auto-settlement on authorization (Payments API)."
  @spec with_auto_settlement(%{String.t() => term()}, keyword()) :: %{String.t() => term()}
  def with_auto_settlement(body, opts \\ []) do
    auto =
      %{"enabled" => true}
      |> maybe_put("targetDate", Keyword.get(opts, :target_date))

    put_in_instruction(body, "requestAutoSettlement", auto)
  end

  # ── Token creation on payment ─────────────────────────────────────────────

  @doc """
  Request token creation as part of a Payments API call.

  ## `type` options: `"worldpay"` | `"networkToken"`
  """
  @spec with_token_creation(%{String.t() => term()}, String.t(), keyword()) :: %{
          String.t() => term()
        }
  def with_token_creation(body, type \\ "worldpay", opts \\ []) do
    token_creation =
      %{"type" => type}
      |> maybe_put("namespace", Keyword.get(opts, :namespace))

    put_in_instruction(body, "tokenCreation", token_creation)
  end

  # ── External MPI ─────────────────────────────────────────────────────────

  @doc """
  Add external 3DS (own MPI) authentication result to a card payment.

  ## Required opts

  - `:eci` — Electronic Commerce Indicator
  - `:authentication_value` — CAVV / UCAF
  - `:transaction_id` — DS transaction ID
  - `:version` — 3DS version string
  """
  @spec with_external_mpi(%{String.t() => term()}, keyword()) :: %{String.t() => term()}
  def with_external_mpi(body, opts) do
    three_ds =
      %{
        "type" => "external",
        "eci" => Keyword.fetch!(opts, :eci),
        "authenticationValue" => Keyword.fetch!(opts, :authentication_value),
        "transactionId" => Keyword.get(opts, :transaction_id),
        "version" => Keyword.get(opts, :version)
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)

    put_in_instruction(body, "threeDS", three_ds)
  end

  # ── SCA exemptions in Payments API ───────────────────────────────────────

  @doc """
  Request an SCA exemption inside a Payments API call.

  Types: `"TRA"` | `"lowValue"` | `"trustedBeneficiary"` | `"authenticationOutage"`
  """
  @spec with_exemption(%{String.t() => term()}, String.t()) :: %{String.t() => term()}
  def with_exemption(body, exemption_type) do
    put_in_instruction(body, "exemption", %{"type" => exemption_type})
  end

  # ── Dynamic MCC ───────────────────────────────────────────────────────────

  @doc "Override MCC on a per-transaction basis."
  @spec with_dynamic_mcc(%{String.t() => term()}, String.t()) :: %{String.t() => term()}
  def with_dynamic_mcc(body, mcc) do
    update_in(body, ["merchant"], &Map.put(&1 || %{}, "mcc", mcc))
  end

  # ── Customer agreement ────────────────────────────────────────────────────

  @doc """
  Build a customerAgreement object for stored credential payments.

  ## `type` values: `"cardOnFile"` | `"subscription"` | `"installment"` | `"unscheduled"`
  ## `usage` values: `"first"` | `"subsequent"`
  """
  @spec customer_agreement(String.t(), String.t(), String.t() | nil) :: %{
          String.t() => String.t()
        }
  def customer_agreement(type, usage, scheme_reference \\ nil) do
    %{"type" => type, "storedCardUsage" => usage}
    |> maybe_put("schemeReference", scheme_reference)
  end

  # ── Narrative / statement descriptor ──────────────────────────────────────

  @doc "Build a narrative (statement descriptor)."
  @spec narrative(String.t(), String.t() | nil) :: %{String.t() => String.t()}
  def narrative(line1, line2 \\ nil) do
    %{"line1" => line1}
    |> maybe_put("line2", line2)
  end

  # ── private ───────────────────────────────────────────────────────────────

  @spec put_in_instruction(%{String.t() => term()}, String.t(), term()) :: %{String.t() => term()}
  defp put_in_instruction(body, key, value) do
    instruction = Map.get(body, "instruction", %{})
    Map.put(body, "instruction", Map.put(instruction, key, value))
  end

  @spec maybe_put(
          %{String.t() => term()},
          String.t(),
          String.t() | [term()] | %{String.t() => term()} | nil
        ) :: %{String.t() => term()}
  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v) when is_binary(k), do: Map.put(map, k, v)

  @spec amount_map(non_neg_integer() | nil, String.t() | nil) ::
          %{String.t() => non_neg_integer() | String.t()} | nil
  defp amount_map(nil, _currency), do: nil
  defp amount_map(amount, currency), do: %{"amount" => amount, "currency" => currency}

  @spec build_legs(list()) :: list()
  defp build_legs([]), do: []

  defp build_legs(legs) do
    Enum.map(legs, fn leg ->
      %{
        "originAirportCode" => leg[:origin],
        "destinationAirportCode" => leg[:destination],
        "carrierCode" => leg[:carrier_code],
        "flightNumber" => leg[:flight_number],
        "fareBasisCode" => leg[:fare_basis_code],
        "stopoverCode" => if(leg[:stopover], do: "permitted", else: "notPermitted")
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)
    end)
  end

  @spec build_passengers(list()) :: list()
  defp build_passengers([]), do: []

  defp build_passengers(passengers) do
    Enum.map(passengers, fn p ->
      %{
        "firstName" => p[:first_name],
        "lastName" => p[:last_name],
        "dateOfBirth" => p[:date_of_birth]
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)
    end)
  end

  @spec build_line_items(list(), String.t() | nil) :: list()
  defp build_line_items([], _currency), do: []

  defp build_line_items(items, currency) do
    Enum.map(items, fn item ->
      %{
        "description" => item[:description],
        "quantity" => item[:quantity],
        "unitCode" => item[:unit_code],
        "unitCost" => amount_map(item[:unit_cost], currency),
        "taxAmount" => amount_map(item[:tax_amount], currency),
        "totalAmount" => amount_map(item[:total_amount], currency),
        "discountAmount" => amount_map(item[:discount_amount], currency),
        "commodityCode" => item[:commodity_code]
      }
      |> Map.reject(fn {_, v} -> is_nil(v) end)
    end)
  end

  @spec build_affiliate(keyword() | nil) :: %{String.t() => String.t()} | nil
  defp build_affiliate(nil), do: nil

  defp build_affiliate(aff) do
    %{}
    |> maybe_put("name", aff[:name])
    |> maybe_put("id", aff[:id])
  end

  @spec build_aft_sender(keyword()) :: %{String.t() => term()}
  defp build_aft_sender(opts) do
    %{
      "firstName" => Keyword.get(opts, :first_name),
      "middleName" => Keyword.get(opts, :middle_name),
      "lastName" => Keyword.get(opts, :last_name),
      "dateOfBirth" => Keyword.get(opts, :date_of_birth),
      "documentReference" => Keyword.get(opts, :document_reference),
      "address" => Keyword.get(opts, :address)
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  @spec build_aft_recipient(keyword()) :: %{String.t() => term()}
  defp build_aft_recipient(opts) do
    account_type = Keyword.get(opts, :type, "card")

    base = %{"account" => %{"type" => account_type}}

    case account_type do
      "card" ->
        put_in(base, ["account", "href"], Keyword.get(opts, :href))

      "bank" ->
        base
        |> put_in(["account", "accountNumber"], Keyword.get(opts, :account_number))
        |> put_in(["account", "routingNumber"], Keyword.get(opts, :routing_number))
        |> put_in(["account", "identifierType"], Keyword.get(opts, :identifier_type))

      "wallet" ->
        base
        |> put_in(["account", "walletReference"], Keyword.get(opts, :wallet_reference))
        |> put_in(["account", "walletProvider"], Keyword.get(opts, :wallet_provider))

      _ ->
        base
    end
  end
end
