defmodule Worldpay.WPG.Features do
  @moduledoc """
  Advanced WPG features: DCC, Guaranteed Payments, Prime Routing,
  Revenue Boost, Lodging, MAC, zero-value auth, stored credentials,
  submission fulfillment, and JSC device data snippet builder.

  All `Builder.*` functions return XML fragments to embed in a WPG order
  or modification. Wrap with `Worldpay.WPG.Builder.envelope/2` before
  submitting via `Worldpay.WPG.submit/2`.
  """

  # ── Dynamic Currency Conversion (DCC) ─────────────────────────────────────

  @doc """
  Build a DCC enquiry order (step 1 — get offered rate).

  Submit before the actual payment. Customer chooses their currency.
  Then submit the payment with `dcc_payment/1` including their choice.
  """
  @spec dcc_enquiry(keyword()) :: String.t()
  def dcc_enquiry(opts) do
    order_code = Keyword.fetch!(opts, :order_code)
    amount = Keyword.fetch!(opts, :amount)
    currency = Keyword.fetch!(opts, :currency)
    card_number = Keyword.fetch!(opts, :card_number)
    exp_month = Keyword.fetch!(opts, :exp_month)
    exp_year = Keyword.fetch!(opts, :exp_year)
    card_holder = Keyword.get(opts, :card_holder, "")

    """
    <submit>
      <order orderCode="#{order_code}-DCC">
        <description>DCC Enquiry</description>
        <amount currencyCode="#{currency}" exponent="2" value="#{amount}"/>
        <paymentDetails>
          <VISA-SSL>
            <cardNumber>#{card_number}</cardNumber>
            <expiryDate><date month="#{exp_month}" year="#{exp_year}"/></expiryDate>
            <cardHolderName>#{card_holder}</cardHolderName>
          </VISA-SSL>
          <session id="session-#{order_code}"/>
        </paymentDetails>
        <dynamicInteractionType type="ECOMMERCE"/>
      </order>
    </submit>
    """
  end

  @doc """
  Build a DCC payment after customer accepts or declines DCC offer.

  ## Options

  - `:dcc_accepted` — boolean (customer accepted DCC?)
  - `:dcc_currency` — offered currency code (if accepted)
  - `:dcc_amount` — amount in offered currency (if accepted)
  - `:dcc_rate` — exchange rate (if accepted)
  - `:dcc_rate_type` — rate type (if accepted)
  - `:dcc_margin` — margin percentage (if accepted)
  """
  @spec dcc_payment(keyword()) :: String.t()
  def dcc_payment(opts) do
    order_code = Keyword.fetch!(opts, :order_code)
    amount = Keyword.fetch!(opts, :amount)
    currency = Keyword.fetch!(opts, :currency)
    card_number = Keyword.fetch!(opts, :card_number)
    exp_month = Keyword.fetch!(opts, :exp_month)
    exp_year = Keyword.fetch!(opts, :exp_year)
    card_holder = Keyword.get(opts, :card_holder, "")
    dcc_xml = build_dcc_status_xml(opts)

    """
    <submit>
      <order orderCode="#{order_code}">
        <description>DCC Payment</description>
        <amount currencyCode="#{currency}" exponent="2" value="#{amount}"/>
        <paymentDetails>
          <VISA-SSL>
            <cardNumber>#{card_number}</cardNumber>
            <expiryDate><date month="#{exp_month}" year="#{exp_year}"/></expiryDate>
            <cardHolderName>#{card_holder}</cardHolderName>
          </VISA-SSL>
        </paymentDetails>
        #{dcc_xml}
        <dynamicInteractionType type="ECOMMERCE"/>
      </order>
    </submit>
    """
  end

  @spec build_dcc_status_xml(keyword()) :: String.t()
  defp build_dcc_status_xml(opts) do
    if Keyword.get(opts, :dcc_accepted, false) do
      dcc_currency = Keyword.fetch!(opts, :dcc_currency)
      dcc_amount = Keyword.fetch!(opts, :dcc_amount)
      dcc_rate = Keyword.fetch!(opts, :dcc_rate)
      rate_type = Keyword.get(opts, :dcc_rate_type, "BANKERS_BUYING")
      margin = Keyword.get(opts, :dcc_margin, "0")

      """
      <dynamicCurrencyConversion>
        <status>ACCEPTED</status>
        <offeredCurrency>#{dcc_currency}</offeredCurrency>
        <offeredAmount>#{dcc_amount}</offeredAmount>
        <rate>#{dcc_rate}</rate>
        <rateType>#{rate_type}</rateType>
        <margin>#{margin}</margin>
      </dynamicCurrencyConversion>
      """
    else
      ~s(<dynamicCurrencyConversion><status>DECLINED</status></dynamicCurrencyConversion>)
    end
  end

  @doc """
  Parse DCC status from a WPG XML response map.

  Returns one of: `"ACCEPTED"` | `"DECLINED"` | `"NOT_OFFERED"` | `"NOT_AVAILABLE"` | `nil`
  """
  @spec dcc_status(map()) :: String.t() | nil
  def dcc_status(parsed) do
    get_in(parsed, [
      "paymentService",
      "reply",
      "orderStatus",
      "payment",
      "DCC",
      "dccStatus"
    ])
  end

  @doc "Parse Revenue Boost NPT upgrade from WPG response."
  @spec revenue_boost_npt?(map()) :: boolean()
  def revenue_boost_npt?(parsed) do
    case get_in(parsed, [
           "paymentService",
           "reply",
           "orderStatus",
           "payment",
           "paymentInstrumentUpdated",
           "@type"
         ]) do
      "REVENUE_BOOST_NPT" -> true
      _ -> false
    end
  end

  @doc "Parse Mastercard Authorization Optimizer (MAC) code from WPG response."
  @spec mac_code(map()) :: String.t() | nil
  def mac_code(parsed) do
    get_in(parsed, ["paymentService", "reply", "orderStatus", "payment", "MAC"])
  end

  # ── Guaranteed Payments / Signifyd ────────────────────────────────────────

  @doc """
  Build a Guaranteed Payments (Signifyd) order with device session data.

  The `web_session_id` is collected by the Signifyd JSC snippet on the
  checkout page and identifies the device session for fraud assessment.

  ## Options

  - `:web_session_id` — Signifyd device session ID (required)
  - `:shopper_email` — customer email
  - `:shopper_ip` — customer IP address
  - `:subscription` — boolean (recurring payment?)
  """
  @spec guaranteed_payment_order(keyword()) :: String.t()
  def guaranteed_payment_order(opts) do
    order_code = Keyword.fetch!(opts, :order_code)
    amount = Keyword.fetch!(opts, :amount)
    currency = Keyword.fetch!(opts, :currency)
    card_number = Keyword.fetch!(opts, :card_number)
    exp_month = Keyword.fetch!(opts, :exp_month)
    exp_year = Keyword.fetch!(opts, :exp_year)
    card_holder = Keyword.get(opts, :card_holder, "")
    web_session_id = Keyword.fetch!(opts, :web_session_id)
    shopper_email = Keyword.get(opts, :shopper_email)
    shopper_ip = Keyword.get(opts, :shopper_ip)
    subscription = Keyword.get(opts, :subscription, false)

    """
    <submit>
      <order orderCode="#{order_code}">
        <description>Guaranteed Payment</description>
        <amount currencyCode="#{currency}" exponent="2" value="#{amount}"/>
        #{if shopper_email, do: "<shopper><emailAddress>#{shopper_email}</emailAddress></shopper>", else: ""}
        #{if shopper_ip, do: "<shopperIPAddress>#{shopper_ip}</shopperIPAddress>", else: ""}
        <paymentDetails>
          <VISA-SSL>
            <cardNumber>#{card_number}</cardNumber>
            <expiryDate><date month="#{exp_month}" year="#{exp_year}"/></expiryDate>
            <cardHolderName>#{card_holder}</cardHolderName>
          </VISA-SSL>
        </paymentDetails>
        <fraudsight>
          <message>#{web_session_id}</message>
          #{if subscription, do: "<subscription>true</subscription>", else: ""}
        </fraudsight>
      </order>
    </submit>
    """
  end

  # ── Prime Routing / Debit Optimization ────────────────────────────────────

  @doc """
  Build a Prime Routing debit sale order.

  Prime Routing routes eligible debit transactions to the lowest-cost network.
  Requires Sale (not Authorization-only) transaction type.
  """
  @spec prime_routing_sale(keyword()) :: String.t()
  def prime_routing_sale(opts) do
    order_code = Keyword.fetch!(opts, :order_code)
    amount = Keyword.fetch!(opts, :amount)
    currency = Keyword.fetch!(opts, :currency)
    card_number = Keyword.fetch!(opts, :card_number)
    exp_month = Keyword.fetch!(opts, :exp_month)
    exp_year = Keyword.fetch!(opts, :exp_year)
    card_holder = Keyword.get(opts, :card_holder, "")
    pin_block = Keyword.get(opts, :pin_block)

    """
    <submit>
      <order orderCode="#{order_code}" type="SALE">
        <description>Prime Routing Sale</description>
        <amount currencyCode="#{currency}" exponent="2" value="#{amount}"/>
        <paymentDetails>
          <VISA-DEBIT-SSL>
            <cardNumber>#{card_number}</cardNumber>
            <expiryDate><date month="#{exp_month}" year="#{exp_year}"/></expiryDate>
            <cardHolderName>#{card_holder}</cardHolderName>
            #{if pin_block, do: "<pinBlock>#{pin_block}</pinBlock>", else: ""}
          </VISA-DEBIT-SSL>
        </paymentDetails>
        <additional name="primeRouting" value="true"/>
      </order>
    </submit>
    """
  end

  # ── Lodging data ──────────────────────────────────────────────────────────

  @doc """
  Add lodging (hotel) data to a WPG order for lower interchange.

  ## Options

  - `:hotel_folio_number` — folio/invoice number
  - `:check_in_date` — YYYY-MM-DD
  - `:check_out_date` — YYYY-MM-DD
  - `:duration_of_stay` — integer (nights)
  - `:fire_safe_indicator` — boolean
  - `:program_code` — Mastercard lodging program code
  - `:charge_type` — "RESTAURANT" | "GIFTSHOP" | "MINIBAR" | "TELEPHONE" | "LAUNDRY" | "OTHER"
  """
  @spec lodging_xml(keyword()) :: String.t()
  def lodging_xml(opts) do
    """
    <branchSpecificExtension>
      <hotel>
        <hotelFolioNumber>#{Keyword.get(opts, :hotel_folio_number)}</hotelFolioNumber>
        <checkInDate>#{Keyword.get(opts, :check_in_date)}</checkInDate>
        <checkOutDate>#{Keyword.get(opts, :check_out_date)}</checkOutDate>
        <durationOfStay>#{Keyword.get(opts, :duration_of_stay)}</durationOfStay>
        #{if Keyword.get(opts, :fire_safe_indicator), do: "<fireSafeIndicator>Y</fireSafeIndicator>", else: ""}
        #{if code = Keyword.get(opts, :program_code), do: "<masterCardSpecificData><programCode>#{code}</programCode></masterCardSpecificData>", else: ""}
        #{if ct = Keyword.get(opts, :charge_type), do: "<chargeType>#{ct}</chargeType>", else: ""}
      </hotel>
    </branchSpecificExtension>
    """
  end

  # ── Zero-value authorization (card validity check) ────────────────────────

  @doc """
  Build a zero-value authorization order to check card validity (WPG).

  Use with CVC and AVS to validate a card without charging it.
  Response includes riskFactors for CVC/AVS match results.
  """
  @spec zero_value_auth(keyword()) :: String.t()
  def zero_value_auth(opts) do
    order_code = Keyword.fetch!(opts, :order_code)
    card_number = Keyword.fetch!(opts, :card_number)
    exp_month = Keyword.fetch!(opts, :exp_month)
    exp_year = Keyword.fetch!(opts, :exp_year)
    card_holder = Keyword.get(opts, :card_holder, "")
    cvc = Keyword.get(opts, :cvc)
    billing_address = Keyword.get(opts, :billing_address)

    """
    <submit>
      <order orderCode="#{order_code}">
        <description>Card validity check</description>
        <amount currencyCode="GBP" exponent="2" value="0"/>
        <paymentDetails>
          <VISA-SSL>
            <cardNumber>#{card_number}</cardNumber>
            <expiryDate><date month="#{exp_month}" year="#{exp_year}"/></expiryDate>
            <cardHolderName>#{card_holder}</cardHolderName>
            #{if cvc, do: "<cvc>#{cvc}</cvc>", else: ""}
          </VISA-SSL>
          #{if billing_address, do: billing_address_xml(billing_address), else: ""}
        </paymentDetails>
      </order>
    </submit>
    """
  end

  # ── Stored credentials (WPG) ──────────────────────────────────────────────

  @doc """
  Add stored credential data to a WPG order.

  ## `reason` values:
  `"UNSCHEDULED"` | `"SUBSCRIPTION"` | `"INSTALLMENT"` | `"RESUBMISSION"` |
  `"REAUTHORISATION"` | `"DELAYED_CHARGE"` | `"NO_SHOW"`

  ## `usage` values:
  `"FIRST"` | `"USED"`
  """
  @spec stored_credentials_xml(keyword()) :: String.t()
  def stored_credentials_xml(opts) do
    usage = Keyword.get(opts, :usage, "USED")
    reason = Keyword.get(opts, :reason, "UNSCHEDULED")
    scheme_ref = Keyword.get(opts, :scheme_reference)

    """
    <storedCredentials usage="#{usage}" merchantInitiatedReason="#{reason}">
      #{if scheme_ref, do: "<schemeTransactionIdentifier>#{scheme_ref}</schemeTransactionIdentifier>", else: ""}
    </storedCredentials>
    """
  end

  # ── Submission fulfillment (WPG) ──────────────────────────────────────────

  @doc """
  Build a WPG submission fulfillment modification.

  Used for deferred capture: pre-orders, delayed shipping, subscriptions.
  Marks an authorized order as ready for capture/settlement.

  ## Options

  - `:order_code` — original order code
  - `:fulfillment_data` — optional fulfillment metadata map
  """
  @spec submission_fulfillment(keyword()) :: String.t()
  def submission_fulfillment(opts) do
    order_code = Keyword.fetch!(opts, :order_code)
    fulfillment = Keyword.get(opts, :fulfillment_data, %{})

    extra =
      fulfillment
      |> Enum.map_join("\n", fn {k, v} ->
        ~s(<additional name="#{k}" value="#{v}"/>)
      end)

    """
    <modify>
      <orderModification orderCode="#{order_code}">
        <submissionFulfillment>
          #{extra}
        </submissionFulfillment>
      </orderModification>
    </modify>
    """
  end

  # ── JSC device data snippet ───────────────────────────────────────────────

  @doc """
  Returns the JavaScript snippet string for WPG Device and Behavioral JSC.

  Embed in checkout page HTML. The `session_id` is used as the
  `webSessionId` / `<message>` in FraudSight / Guaranteed Payments requests.

  ## Parameters

  - `session_id` — unique session identifier for the checkout session
  - `environment` — `:try` | `:live`
  """
  @spec jsc_snippet(String.t(), :try | :live) :: String.t()
  def jsc_snippet(session_id, environment \\ :try) do
    domain =
      case environment do
        :live -> "h.online-metrix.net"
        _ -> "h.online-metrix.net"
      end

    """
    <!-- Worldpay JSC Device Data Collection -->
    <script type="text/javascript">
      var org_id = "#{jsc_org_id(environment)}";
      var session_id = "#{session_id}";
    </script>
    <script type="text/javascript" src="https://#{domain}/fp/check.js?org_id=#{jsc_org_id(environment)}&amp;session_id=#{session_id}"></script>
    <noscript>
      <iframe
        style="width: 100px; height: 100px; border: 0; position: absolute; top: -5000px;"
        src="https://#{domain}/fp/tags?org_id=#{jsc_org_id(environment)}&amp;session_id=#{session_id}">
      </iframe>
    </noscript>
    """
  end

  # ── AVS / CVC parsing ─────────────────────────────────────────────────────

  @doc """
  Parse AVS and CVC risk factors from a WPG XML response.

  Returns `%{cvc: "MATCHED" | "NOT_MATCHED" | "NOT_SENT_TO_ACQUIRER" | nil,
             avs_address: "MATCHED" | ... | nil,
             avs_postcode: "MATCHED" | ... | nil}`
  """
  @spec risk_factors(%{String.t() => term()}) :: %{
          cvc: String.t() | nil,
          avs_address: String.t() | nil,
          avs_postcode: String.t() | nil
        }
  def risk_factors(parsed) do
    rf = get_in(parsed, ["paymentService", "reply", "orderStatus", "payment", "riskFactors"])

    %{
      cvc: extract_risk(rf, "CVC"),
      avs_address: extract_risk(rf, "AVS"),
      avs_postcode: extract_risk(rf, "AVS-POSTCODE")
    }
  end

  # ── Dynamic MCC (WPG) ────────────────────────────────────────────────────

  @doc """
  Build a dynamic MCC XML element for per-transaction MCC override.
  Embed inside a WPG order `<paymentDetails>` element.
  """
  @spec dynamic_mcc_xml(String.t()) :: String.t()
  def dynamic_mcc_xml(mcc) do
    "<additional name=\"dynamicMCC\" value=\"#{mcc}\"/>"
  end

  # ── Account Name Inquiry (WPG) ───────────────────────────────────────────

  @doc """
  Build a WPG Account Name Inquiry request.

  Used to verify account holder name before payouts.
  """
  @spec account_name_inquiry(String.t(), String.t(), String.t()) :: String.t()
  def account_name_inquiry(inquiry_code, sort_code, account_number) do
    """
    <inquiry>
      <accountNameInquiry>
        <inquiryCode>#{inquiry_code}</inquiryCode>
        <sortCode>#{sort_code}</sortCode>
        <accountNumber>#{account_number}</accountNumber>
      </accountNameInquiry>
    </inquiry>
    """
  end

  # ── Fast Access / Fast Refund (WPG) ──────────────────────────────────────

  @doc """
  Build a WPG Fast Refund modification (≤30 min credit).

  ## Options

  - `:order_code` — original order code
  - `:amount` — refund amount
  - `:currency` — currency code
  """
  @spec fast_refund(keyword()) :: String.t()
  def fast_refund(opts) do
    order_code = Keyword.fetch!(opts, :order_code)
    amount = Keyword.fetch!(opts, :amount)
    currency = Keyword.fetch!(opts, :currency)

    """
    <modify>
      <orderModification orderCode="#{order_code}">
        <fastRefund>
          <amount currencyCode="#{currency}" exponent="2" value="#{amount}"/>
        </fastRefund>
      </orderModification>
    </modify>
    """
  end

  # ── Convenience fees / Surcharges (WPG) ──────────────────────────────────

  @doc """
  Build an order XML with a convenience fee (WPG).

  Convenience fees apply to all payment methods.
  """
  @spec convenience_fee_xml(non_neg_integer(), String.t()) :: String.t()
  def convenience_fee_xml(fee_amount, currency) do
    "<additionalAmount type=\"convenienceFee\" currencyCode=\"#{currency}\" exponent=\"2\" value=\"#{fee_amount}\"/>"
  end

  @doc """
  Build an order XML with a surcharge element (WPG).

  Surcharges apply to credit cards only and cannot be combined with convenience fees.
  """
  @spec surcharge_xml(non_neg_integer(), String.t()) :: String.t()
  def surcharge_xml(surcharge_amount, currency) do
    "<additionalAmount type=\"surcharge\" currencyCode=\"#{currency}\" exponent=\"2\" value=\"#{surcharge_amount}\"/>"
  end

  # ── private ───────────────────────────────────────────────────────────────

  @spec billing_address_xml(map()) :: String.t()
  defp billing_address_xml(addr) do
    """
    <cardAddress>
      <address>
        <address1>#{addr[:address1]}</address1>
        <postalCode>#{addr[:postal_code]}</postalCode>
        <city>#{addr[:city]}</city>
        <countryCode>#{addr[:country_code]}</countryCode>
      </address>
    </cardAddress>
    """
  end

  @spec extract_risk(term(), String.t()) :: String.t() | nil
  defp extract_risk(nil, _type), do: nil

  defp extract_risk(risk_factors, type) when is_map(risk_factors) do
    risk_factors[type]
  end

  defp extract_risk(risk_factors, type) when is_list(risk_factors) do
    Enum.find_value(risk_factors, fn rf ->
      if is_map(rf) and rf["@code"] == type, do: rf["@description"]
    end)
  end

  defp extract_risk(_, _), do: nil

  @spec jsc_org_id(:try | :live) :: String.t()
  defp jsc_org_id(:live), do: "1snn5n9w"
  defp jsc_org_id(_), do: "1snn5n9w"
end
