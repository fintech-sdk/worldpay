defmodule Worldpay.CNP.Builder do
  @moduledoc """
  Builds cnpAPI XML request documents for US eCommerce processing.

  Supports: Authorization, Sale, Credit, Void, Capture, Reversal,
  EcheckSale, EcheckVoid, EcheckCredit, Token registration, Dynamic Payout.
  """

  @schema_version "12.0"
  @xmlns "http://www.vantiv.cnp.com/schema"

  @doc "Wrap inner XML in a cnpRequest envelope."
  @spec envelope(String.t(), keyword()) :: String.t()
  def envelope(inner, opts) do
    merchant_id = Keyword.fetch!(opts, :merchant_id)
    user = Keyword.fetch!(opts, :user)
    password = Keyword.fetch!(opts, :password)
    id = Keyword.get(opts, :id, generate_id())

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <cnpRequest version="#{@schema_version}" xmlns="#{@xmlns}"
        merchantId="#{merchant_id}" id="#{id}">
      <authentication>
        <user>#{user}</user>
        <password>#{password}</password>
      </authentication>
      #{inner}
    </cnpRequest>
    """
  end

  @doc "Build an authorization transaction."
  @spec authorization(keyword()) :: String.t()
  def authorization(opts) do
    id = Keyword.fetch!(opts, :id)
    order_id = Keyword.fetch!(opts, :order_id)
    amount = Keyword.fetch!(opts, :amount)
    report_group = Keyword.get(opts, :report_group, "Default")
    card = Keyword.get(opts, :card)
    token = Keyword.get(opts, :token)
    customer_info = Keyword.get(opts, :customer_info)
    billing_address = Keyword.get(opts, :billing_address)
    fraud_filter = Keyword.get(opts, :fraud_filter_override)
    stored_credential = Keyword.get(opts, :stored_credential)
    order_source = Keyword.get(opts, :order_source, "ecommerce")

    """
    <authorization id="#{id}" reportGroup="#{report_group}">
      <orderId>#{order_id}</orderId>
      <amount>#{amount}</amount>
      <orderSource>#{order_source}</orderSource>
      #{maybe_billing(billing_address)}
      #{maybe_card(card)}
      #{maybe_cnp_token(token)}
      #{maybe_customer_info(customer_info)}
      #{maybe_fraud_filter(fraud_filter)}
      #{maybe_stored_credential(stored_credential)}
    </authorization>
    """
  end

  @doc "Build a sale transaction (auth + auto-capture)."
  @spec sale(keyword()) :: String.t()
  def sale(opts) do
    id = Keyword.fetch!(opts, :id)
    order_id = Keyword.fetch!(opts, :order_id)
    amount = Keyword.fetch!(opts, :amount)
    report_group = Keyword.get(opts, :report_group, "Default")
    card = Keyword.get(opts, :card)
    token = Keyword.get(opts, :token)
    billing_address = Keyword.get(opts, :billing_address)
    enhanced_data = Keyword.get(opts, :enhanced_data)
    lodging_info = Keyword.get(opts, :lodging_info)
    order_source = Keyword.get(opts, :order_source, "ecommerce")
    fraud_filter = Keyword.get(opts, :fraud_filter_override)
    stored_credential = Keyword.get(opts, :stored_credential)
    web_session_id = Keyword.get(opts, :web_session_id)

    """
    <sale id="#{id}" reportGroup="#{report_group}">
      <orderId>#{order_id}</orderId>
      <amount>#{amount}</amount>
      <orderSource>#{order_source}</orderSource>
      #{maybe_billing(billing_address)}
      #{maybe_card(card)}
      #{maybe_cnp_token(token)}
      #{maybe_enhanced_data(enhanced_data)}
      #{maybe_lodging(lodging_info)}
      #{maybe_fraud_filter(fraud_filter)}
      #{maybe_web_session(web_session_id)}
      #{maybe_stored_credential(stored_credential)}
    </sale>
    """
  end

  @doc "Build a credit (refund) transaction."
  @spec credit(keyword()) :: String.t()
  def credit(opts) do
    id = Keyword.fetch!(opts, :id)
    order_id = Keyword.fetch!(opts, :order_id)
    amount = Keyword.fetch!(opts, :amount)
    report_group = Keyword.get(opts, :report_group, "Default")
    cnp_txn_id = Keyword.get(opts, :cnp_txn_id)
    card = Keyword.get(opts, :card)
    billing_address = Keyword.get(opts, :billing_address)

    """
    <credit id="#{id}" reportGroup="#{report_group}">
      <orderId>#{order_id}</orderId>
      #{maybe_tag("cnpTxnId", cnp_txn_id)}
      <amount>#{amount}</amount>
      #{maybe_billing(billing_address)}
      #{maybe_card(card)}
    </credit>
    """
  end

  @doc "Build a void transaction."
  @spec void(keyword()) :: String.t()
  def void(opts) do
    id = Keyword.fetch!(opts, :id)
    cnp_txn_id = Keyword.fetch!(opts, :cnp_txn_id)
    report_group = Keyword.get(opts, :report_group, "Default")

    """
    <void id="#{id}" reportGroup="#{report_group}">
      <cnpTxnId>#{cnp_txn_id}</cnpTxnId>
    </void>
    """
  end

  @doc "Build a capture (settlement) transaction."
  @spec capture(keyword()) :: String.t()
  def capture(opts) do
    id = Keyword.fetch!(opts, :id)
    cnp_txn_id = Keyword.fetch!(opts, :cnp_txn_id)
    amount = Keyword.fetch!(opts, :amount)
    report_group = Keyword.get(opts, :report_group, "Default")
    partial = Keyword.get(opts, :partial, false)

    """
    <capture id="#{id}" reportGroup="#{report_group}" partial="#{partial}">
      <cnpTxnId>#{cnp_txn_id}</cnpTxnId>
      <amount>#{amount}</amount>
    </capture>
    """
  end

  @doc "Build a reversal transaction."
  @spec reversal(keyword()) :: String.t()
  def reversal(opts) do
    id = Keyword.fetch!(opts, :id)
    cnp_txn_id = Keyword.fetch!(opts, :cnp_txn_id)
    amount = Keyword.get(opts, :amount)
    report_group = Keyword.get(opts, :report_group, "Default")

    """
    <authReversal id="#{id}" reportGroup="#{report_group}">
      <cnpTxnId>#{cnp_txn_id}</cnpTxnId>
      #{maybe_tag("amount", amount)}
    </authReversal>
    """
  end

  @doc "Build an eCheck sale."
  @spec echeck_sale(keyword()) :: String.t()
  def echeck_sale(opts) do
    id = Keyword.fetch!(opts, :id)
    order_id = Keyword.fetch!(opts, :order_id)
    amount = Keyword.fetch!(opts, :amount)
    report_group = Keyword.get(opts, :report_group, "Default")
    account_number = Keyword.fetch!(opts, :account_number)
    routing_number = Keyword.fetch!(opts, :routing_number)
    account_type = Keyword.get(opts, :account_type, "Checking")
    billing_address = Keyword.get(opts, :billing_address)

    """
    <echeckSale id="#{id}" reportGroup="#{report_group}">
      <orderId>#{order_id}</orderId>
      <amount>#{amount}</amount>
      <orderSource>ecommerce</orderSource>
      #{maybe_billing(billing_address)}
      <echeck>
        <accType>#{account_type}</accType>
        <accNum>#{account_number}</accNum>
        <routingNum>#{routing_number}</routingNum>
      </echeck>
    </echeckSale>
    """
  end

  @doc "Build an eCheck void."
  @spec echeck_void(keyword()) :: String.t()
  def echeck_void(opts) do
    id = Keyword.fetch!(opts, :id)
    cnp_txn_id = Keyword.fetch!(opts, :cnp_txn_id)
    report_group = Keyword.get(opts, :report_group, "Default")

    """
    <echeckVoid id="#{id}" reportGroup="#{report_group}">
      <cnpTxnId>#{cnp_txn_id}</cnpTxnId>
    </echeckVoid>
    """
  end

  @doc "Build an eCheck credit (refund)."
  @spec echeck_credit(keyword()) :: String.t()
  def echeck_credit(opts) do
    id = Keyword.fetch!(opts, :id)
    order_id = Keyword.fetch!(opts, :order_id)
    amount = Keyword.fetch!(opts, :amount)
    cnp_txn_id = Keyword.get(opts, :cnp_txn_id)
    report_group = Keyword.get(opts, :report_group, "Default")
    account_number = Keyword.fetch!(opts, :account_number)
    routing_number = Keyword.fetch!(opts, :routing_number)
    account_type = Keyword.get(opts, :account_type, "Checking")

    """
    <echeckCredit id="#{id}" reportGroup="#{report_group}">
      <orderId>#{order_id}</orderId>
      #{maybe_tag("cnpTxnId", cnp_txn_id)}
      <amount>#{amount}</amount>
      <echeck>
        <accType>#{account_type}</accType>
        <accNum>#{account_number}</accNum>
        <routingNum>#{routing_number}</routingNum>
      </echeck>
    </echeckCredit>
    """
  end

  @doc "Build a token registration request."
  @spec register_token(keyword()) :: String.t()
  def register_token(opts) do
    id = Keyword.fetch!(opts, :id)
    order_id = Keyword.fetch!(opts, :order_id)
    report_group = Keyword.get(opts, :report_group, "Default")
    account_number = Keyword.fetch!(opts, :account_number)

    """
    <registerTokenRequest id="#{id}" reportGroup="#{report_group}">
      <orderId>#{order_id}</orderId>
      <accountNumber>#{account_number}</accountNumber>
    </registerTokenRequest>
    """
  end

  @doc "Build a Dynamic Payout funding instruction."
  @spec funding_instruction(keyword()) :: String.t()
  def funding_instruction(opts) do
    id = Keyword.fetch!(opts, :id)
    report_group = Keyword.get(opts, :report_group, "Default")
    funding_customer = Keyword.fetch!(opts, :funding_customer)
    funding_list = Keyword.fetch!(opts, :funding_list)
    same_day = Keyword.get(opts, :same_day_funding, false)
    fund_type = if same_day, do: "SAME_DAY_FUNDING", else: "NEXT_DAY_FUNDING"

    """
    <fundingInstruction id="#{id}" reportGroup="#{report_group}">
      <fundingCustomer>
        <customerId>#{funding_customer[:customer_id]}</customerId>
        <customerName>#{funding_customer[:name]}</customerName>
        <fundingSubmerchantList>
          #{build_submerchants(funding_list)}
        </fundingSubmerchantList>
      </fundingCustomer>
      <fundsTransferType>#{fund_type}</fundsTransferType>
    </fundingInstruction>
    """
  end

  # ── private helpers ────────────────────────────────────────────────────────

  @spec maybe_card(
          %{number: String.t(), exp_month: term(), exp_year: term(), type: String.t()}
          | nil
        ) :: String.t()
  defp maybe_card(nil), do: ""

  defp maybe_card(%{number: num, exp_month: m, exp_year: y, type: t} = card) do
    padded_month = String.pad_leading(to_string(m), 2, "0")

    """
    <card>
      <type>#{t}</type>
      <number>#{num}</number>
      <expDate>#{padded_month}#{y}</expDate>
      #{maybe_tag("cardValidationNum", card[:cvc])}
    </card>
    """
  end

  @spec maybe_cnp_token(
          %{token: String.t(), exp_month: term(), exp_year: term(), type: String.t()}
          | nil
        ) :: String.t()
  defp maybe_cnp_token(nil), do: ""

  defp maybe_cnp_token(%{token: t, exp_month: m, exp_year: y, type: type}) do
    padded_month = String.pad_leading(to_string(m), 2, "0")

    """
    <token>
      <cnpToken>#{t}</cnpToken>
      <expDate>#{padded_month}#{y}</expDate>
      <type>#{type}</type>
    </token>
    """
  end

  @spec maybe_billing(%{atom() => String.t() | nil} | nil) :: String.t()
  defp maybe_billing(nil), do: ""

  defp maybe_billing(addr) do
    """
    <billToAddress>
      #{maybe_tag("name", addr[:name])}
      #{maybe_tag("addressLine1", addr[:address1])}
      #{maybe_tag("city", addr[:city])}
      #{maybe_tag("state", addr[:state])}
      #{maybe_tag("zip", addr[:zip])}
      #{maybe_tag("country", addr[:country])}
      #{maybe_tag("email", addr[:email])}
      #{maybe_tag("phone", addr[:phone])}
    </billToAddress>
    """
  end

  @spec maybe_customer_info(%{atom() => String.t() | nil} | nil) :: String.t()
  defp maybe_customer_info(nil), do: ""

  defp maybe_customer_info(info) do
    """
    <customerInfo>
      #{maybe_tag("ssn", info[:ssn])}
      #{maybe_tag("dob", info[:dob])}
      #{maybe_tag("customerRegistrationDate", info[:registration_date])}
    </customerInfo>
    """
  end

  @spec maybe_fraud_filter(term()) :: String.t()
  defp maybe_fraud_filter(nil), do: ""
  defp maybe_fraud_filter(value), do: "<fraudFilterOverride>#{value}</fraudFilterOverride>"

  @spec maybe_web_session(String.t() | nil) :: String.t()
  defp maybe_web_session(nil), do: ""

  defp maybe_web_session(id) do
    "<fraudCheck><authenticationValue>#{id}</authenticationValue></fraudCheck>"
  end

  @spec maybe_stored_credential(%{atom() => term()} | nil) :: String.t()
  defp maybe_stored_credential(nil), do: ""

  defp maybe_stored_credential(%{type: type, network_txn_id: ntid}) do
    """
    <processingType>#{type}</processingType>
    <originalNetworkTransactionId>#{ntid}</originalNetworkTransactionId>
    """
  end

  defp maybe_stored_credential(_), do: ""

  @spec maybe_enhanced_data(%{atom() => term()} | nil) :: String.t()
  defp maybe_enhanced_data(nil), do: ""

  defp maybe_enhanced_data(data) do
    """
    <enhancedData>
      #{maybe_tag("customerReference", data[:customer_reference])}
      #{maybe_tag("salesTax", data[:sales_tax])}
      #{maybe_tag("discountAmount", data[:discount_amount])}
      #{maybe_tag("shippingAmount", data[:shipping_amount])}
      #{maybe_tag("dutyAmount", data[:duty_amount])}
      #{build_line_items(data[:line_items] || [])}
    </enhancedData>
    """
  end

  @spec maybe_lodging(%{atom() => term()} | nil) :: String.t()
  defp maybe_lodging(nil), do: ""

  defp maybe_lodging(info) do
    """
    <lodgingInfo>
      #{maybe_tag("hotelFolioNumber", info[:folio_number])}
      #{maybe_tag("checkInDate", info[:check_in])}
      #{maybe_tag("checkOutDate", info[:check_out])}
      #{maybe_tag("numAdults", info[:num_adults])}
      #{maybe_tag("programCode", info[:program_code])}
    </lodgingInfo>
    """
  end

  @spec build_line_items([map()]) :: String.t()
  defp build_line_items([]), do: ""

  defp build_line_items(items) do
    Enum.map_join(items, "\n", fn item ->
      """
      <lineItemData>
        <itemDescription>#{item[:description]}</itemDescription>
        <itemQuantity>#{item[:quantity]}</itemQuantity>
        <itemUnitCode>#{item[:unit_code]}</itemUnitCode>
        <itemUnitCost>#{item[:unit_cost]}</itemUnitCost>
        <itemTotalAmount>#{item[:total]}</itemTotalAmount>
        #{maybe_tag("itemTaxAmount", item[:tax])}
      </lineItemData>
      """
    end)
  end

  @spec build_submerchants([map()]) :: String.t()
  defp build_submerchants(list) do
    Enum.map_join(list, "\n", fn sm ->
      """
      <fundingSubmerchant>
        <submerchantId>#{sm[:id]}</submerchantId>
        <submerchantName>#{sm[:name]}</submerchantName>
        <fundingAmount>#{sm[:amount]}</fundingAmount>
        <routingNumber>#{sm[:routing_number]}</routingNumber>
        <accountNumber>#{sm[:account_number]}</accountNumber>
        <fundingTransactionType>#{sm[:type] || "credit"}</fundingTransactionType>
      </fundingSubmerchant>
      """
    end)
  end

  @spec maybe_tag(String.t(), term()) :: String.t()
  defp maybe_tag(_name, nil), do: ""
  defp maybe_tag(name, val), do: "<#{name}>#{val}</#{name}>"

  @spec generate_id() :: String.t()
  defp generate_id, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end

defmodule Worldpay.CNP.Parser do
  @moduledoc "Parses cnpAPI XML responses."

  @doc "Parse a cnpAPI XML response string."
  @spec parse(String.t()) ::
          {:ok, %{String.t() => term()}} | {:error, {:xml_parse_error, Exception.t()}}
  def parse(xml) when is_binary(xml) do
    # :xmerl is included via :erlang/OTP; ensure :xmerl is in extra_applications.
    # :xmerl_scan.string/2 always returns a 2-tuple on success (it raises on
    # malformed XML, handled by the rescue clause below).
    {doc, _rest} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
    {:ok, extract(doc)}
  rescue
    ex -> {:error, {:xml_parse_error, ex}}
  end

  @doc "True if the response indicates approval (response code `\"000\"`)."
  @spec approved?(%{String.t() => term()}) :: boolean()
  def approved?(parsed), do: response_code(parsed) == "000"

  @doc "Extract response code from parsed cnp response."
  @spec response_code(%{String.t() => term()}) :: String.t() | nil
  def response_code(%{"cnpResponse" => body}) when is_map(body) do
    body
    |> Map.values()
    |> Enum.find_value(fn
      %{"response" => code} when is_binary(code) -> code
      _ -> nil
    end)
  end

  def response_code(_), do: nil

  @doc "Extract the `cnpTxnId` from any transaction response."
  @spec txn_id(%{String.t() => term()}) :: String.t() | nil
  def txn_id(%{"cnpResponse" => body}) when is_map(body) do
    body
    |> Map.values()
    |> Enum.find_value(fn
      %{"cnpTxnId" => id} when is_binary(id) -> id
      _ -> nil
    end)
  end

  def txn_id(_), do: nil

  @doc "Extract FraudSight `advancedFraudResults` from the response."
  @spec fraud_results(%{String.t() => term()}) :: %{String.t() => term()} | nil
  def fraud_results(%{"cnpResponse" => body}) when is_map(body) do
    body
    |> Map.values()
    |> Enum.find_value(fn
      %{"fraudResult" => %{"advancedFraudResults" => afr}} -> afr
      _ -> nil
    end)
  end

  def fraud_results(_), do: nil

  # ── private ────────────────────────────────────────────────────────────────

  @spec extract(tuple()) :: %{String.t() => term()}
  defp extract({:xmlElement, name, _, _, _, _, _, attrs, children, _, _, _}) do
    tag = to_string(name)
    attr_map = cnp_attrs_to_map(attrs)
    child_map = cnp_children_to_map(children)
    text = cnp_element_text(children)

    %{tag => cnp_content(attr_map, child_map, text)}
  end

  defp extract(_), do: %{}

  @spec cnp_attrs_to_map(list()) :: %{String.t() => term()}
  defp cnp_attrs_to_map(attrs) do
    Map.new(attrs, fn {:xmlAttribute, k, _, _, _, _, _, _, v, _} ->
      {to_string(k), to_string(v)}
    end)
  end

  @spec cnp_children_to_map(list()) :: %{String.t() => term()}
  defp cnp_children_to_map(children) do
    children
    |> Enum.filter(&match?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, &1))
    |> Enum.map(&extract/1)
    |> Enum.reduce(%{}, &merge_cnp_child/2)
  end

  @spec merge_cnp_child(%{String.t() => term()}, %{String.t() => term()}) ::
          %{String.t() => term()}
  defp merge_cnp_child(child, acc) do
    [{k, v}] = Map.to_list(child)

    case Map.get(acc, k) do
      nil -> Map.put(acc, k, v)
      existing when is_list(existing) -> Map.put(acc, k, [v | existing])
      existing -> Map.put(acc, k, [existing, v])
    end
  end

  @spec cnp_element_text(list()) :: String.t()
  defp cnp_element_text(children) do
    children
    |> Enum.filter(&match?({:xmlText, _, _, _, _, _}, &1))
    |> Enum.map_join("", fn {:xmlText, _, _, _, v, _} -> to_string(v) end)
    |> String.trim()
  end

  @spec cnp_content(%{String.t() => term()}, %{String.t() => term()}, String.t()) ::
          %{String.t() => term()} | String.t()
  defp cnp_content(attr_map, child_map, text) do
    cond do
      map_size(child_map) > 0 -> Map.merge(attr_map, child_map)
      map_size(attr_map) > 0 and text != "" -> Map.put(attr_map, "#text", text)
      map_size(attr_map) > 0 -> attr_map
      text != "" -> text
      true -> %{}
    end
  end
end

defmodule Worldpay.CNP do
  @moduledoc """
  Worldpay **cnpAPI** — US eCommerce XML processing (Vantiv platform).

  Submits requests to the cnpAPI online endpoint.

  ## Configuration

      config :worldpay,
        cnp_merchant_id: "your-merchant-id",
        cnp_user: "your-user",
        cnp_password: "your-password"
  """

  alias Worldpay.{CNP, Config, Error}

  @doc "Submit a sale transaction."
  @spec sale(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def sale(opts, %Config{} = config), do: submit(CNP.Builder.sale(opts), config)

  @doc "Submit an authorization."
  @spec authorization(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def authorization(opts, %Config{} = config), do: submit(CNP.Builder.authorization(opts), config)

  @doc "Submit a capture."
  @spec capture(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def capture(opts, %Config{} = config), do: submit(CNP.Builder.capture(opts), config)

  @doc "Submit a credit (refund)."
  @spec credit(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def credit(opts, %Config{} = config), do: submit(CNP.Builder.credit(opts), config)

  @doc "Submit a void."
  @spec void(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def void(opts, %Config{} = config), do: submit(CNP.Builder.void(opts), config)

  @doc "Submit a reversal."
  @spec reversal(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def reversal(opts, %Config{} = config), do: submit(CNP.Builder.reversal(opts), config)

  @doc "Submit an eCheck sale."
  @spec echeck_sale(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def echeck_sale(opts, %Config{} = config), do: submit(CNP.Builder.echeck_sale(opts), config)

  @doc "Submit an eCheck void."
  @spec echeck_void(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def echeck_void(opts, %Config{} = config), do: submit(CNP.Builder.echeck_void(opts), config)

  @doc "Submit an eCheck credit."
  @spec echeck_credit(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def echeck_credit(opts, %Config{} = config), do: submit(CNP.Builder.echeck_credit(opts), config)

  @doc "Register a token."
  @spec register_token(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def register_token(opts, %Config{} = config),
    do: submit(CNP.Builder.register_token(opts), config)

  @doc "Submit a Dynamic Payout funding instruction."
  @spec funding_instruction(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def funding_instruction(opts, %Config{} = config),
    do: submit(CNP.Builder.funding_instruction(opts), config)

  # ── private ────────────────────────────────────────────────────────────────

  @spec submit(String.t(), Config.t()) :: {:ok, %{String.t() => term()}} | {:error, Error.t()}
  defp submit(inner_xml, %Config{} = config) do
    {url, wrapped_xml} = build_cnp_request(inner_xml, config)
    post_cnp_xml(url, wrapped_xml, config)
  end

  @spec build_cnp_request(String.t(), Config.t()) :: {String.t(), String.t()}
  defp build_cnp_request(inner_xml, %Config{} = config) do
    merchant_id = Application.get_env(:worldpay, :cnp_merchant_id, "")
    user = Application.get_env(:worldpay, :cnp_user, "")
    password = Application.get_env(:worldpay, :cnp_password, "")
    url = Application.get_env(:worldpay, :cnp_url, cnp_url(config))

    wrapped =
      CNP.Builder.envelope(inner_xml,
        merchant_id: merchant_id,
        user: user,
        password: password
      )

    {url, wrapped}
  end

  @cnp_headers [{"Content-Type", "text/xml; charset=utf-8"}, {"Accept", "text/xml"}]

  @spec post_cnp_xml(String.t(), String.t(), Config.t()) ::
          {:ok, %{String.t() => term()}} | {:error, Error.t()}
  defp post_cnp_xml(url, xml, %Config{} = config) do
    result =
      try do
        {:ok,
         Req.post!(url,
           body: xml,
           headers: @cnp_headers,
           finch: Worldpay.Finch,
           receive_timeout: config.timeout
         )}
      rescue
        ex -> {:error, ex}
      end

    handle_cnp_response(result)
  end

  @spec handle_cnp_response({:ok, Req.Response.t()} | {:error, term()}) ::
          {:ok, %{String.t() => term()}} | {:error, Error.t()}
  defp handle_cnp_response({:ok, %{status: s, body: body}}) when s in 200..299 do
    case CNP.Parser.parse(body) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, reason} ->
        {:error, %Error{type: :decode_error, reason: :xml_parse_error, raw: inspect(reason)}}
    end
  end

  defp handle_cnp_response({:ok, %{status: s, body: body}}) do
    {:error, Error.from_response(s, body)}
  end

  defp handle_cnp_response({:error, ex}) do
    {:error, Error.from_exception(ex)}
  end

  @spec cnp_url(Config.t()) :: String.t()
  defp cnp_url(%Config{environment: :live}),
    do: "https://payments.worldpay.com/vap/communicator/online"

  defp cnp_url(%Config{}),
    do: "https://payments.vantivprelive.com/vap/communicator/online"
end
