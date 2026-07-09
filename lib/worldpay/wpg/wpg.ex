defmodule Worldpay.WPG.Builder do
  @moduledoc """
  Builds WPG XML request documents.

  All functions return XML strings that can be submitted via `Worldpay.WPG.submit/2`.
  """

  @doc "Wrap inner XML in a WPG `paymentService` envelope."
  @spec envelope(String.t(), keyword()) :: String.t()
  def envelope(inner, opts \\ []) do
    merchant_code = Keyword.fetch!(opts, :merchant_code)
    version = Keyword.get(opts, :version, "1.4")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE paymentService PUBLIC "-//WorldPay//DTD WorldPay PaymentService v1//EN"
      "http://dtd.worldpay.com/paymentService_v1.dtd">
    <paymentService version="#{version}" merchantCode="#{merchant_code}">
      #{inner}
    </paymentService>
    """
  end

  @doc "Build a card order submission (Direct integration)."
  @spec order(keyword()) :: String.t()
  def order(opts) do
    order_code = Keyword.fetch!(opts, :order_code)
    order_reference = Keyword.get(opts, :order_reference)
    amount = Keyword.fetch!(opts, :amount)
    currency = Keyword.fetch!(opts, :currency)
    exponent = Keyword.get(opts, :exponent, 2)
    description = Keyword.get(opts, :description, "")
    extras = build_order_extras(opts)
    payment_details = build_card_details(opts)

    """
    <submit>
      <order orderCode="#{order_code}" #{maybe_attr("orderReference", order_reference)}>
        <description>#{description}</description>
        <amount currencyCode="#{currency}" exponent="#{exponent}" value="#{amount}"/>
        #{extras}
        <paymentDetails>
          #{payment_details}
        </paymentDetails>
        #{maybe_installments(Keyword.get(opts, :installment_data))}
        #{maybe_level3(Keyword.get(opts, :level3_data))}
      </order>
    </submit>
    """
  end

  @spec build_order_extras(keyword()) :: String.t()
  defp build_order_extras(opts) do
    [
      maybe_shopper_email(Keyword.get(opts, :shopper_email)),
      maybe_ip(Keyword.get(opts, :shopper_ip)),
      maybe_narrative(Keyword.get(opts, :statement_narrative))
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("
")
  end

  @spec build_card_details(keyword()) :: String.t()
  defp build_card_details(opts) do
    card_payment_details(
      Keyword.fetch!(opts, :card_number),
      Keyword.fetch!(opts, :exp_month),
      Keyword.fetch!(opts, :exp_year),
      Keyword.get(opts, :card_holder, ""),
      Keyword.get(opts, :cvc)
    )
  end

  @doc "Build a token order submission."
  @spec token_order(keyword()) :: String.t()
  def token_order(opts) do
    order_code = Keyword.fetch!(opts, :order_code)
    amount = Keyword.fetch!(opts, :amount)
    currency = Keyword.fetch!(opts, :currency)
    exponent = Keyword.get(opts, :exponent, 2)
    token_id = Keyword.fetch!(opts, :token_id)
    cvc = Keyword.get(opts, :cvc)
    shopper_email = Keyword.get(opts, :shopper_email)

    """
    <submit>
      <order orderCode="#{order_code}">
        <description>Token payment</description>
        <amount currencyCode="#{currency}" exponent="#{exponent}" value="#{amount}"/>
        #{maybe_shopper_email(shopper_email)}
        <paymentDetails>
          <TOKEN-SSL tokenScope="shopper">
            <paymentTokenID>#{token_id}</paymentTokenID>
            #{if cvc, do: "<cvc>#{cvc}</cvc>"}
          </TOKEN-SSL>
        </paymentDetails>
      </order>
    </submit>
    """
  end

  @doc "Build a capture (settlement) modification."
  @spec capture(String.t(), non_neg_integer(), String.t(), non_neg_integer()) :: String.t()
  def capture(order_code, amount, currency, exponent \\ 2) do
    """
    <modify>
      <orderModification orderCode="#{order_code}">
        <capture>
          <amount currencyCode="#{currency}" exponent="#{exponent}" value="#{amount}"/>
        </capture>
      </orderModification>
    </modify>
    """
  end

  @doc "Build a cancel modification."
  @spec cancel(String.t()) :: String.t()
  def cancel(order_code) do
    """
    <modify>
      <orderModification orderCode="#{order_code}">
        <cancel/>
      </orderModification>
    </modify>
    """
  end

  @doc "Build a refund modification."
  @spec refund(String.t(), non_neg_integer(), String.t(), non_neg_integer()) :: String.t()
  def refund(order_code, amount, currency, exponent \\ 2) do
    """
    <modify>
      <orderModification orderCode="#{order_code}">
        <refund>
          <amount currencyCode="#{currency}" exponent="#{exponent}" value="#{amount}"/>
        </refund>
      </orderModification>
    </modify>
    """
  end

  @doc "Build an inquiry request."
  @spec inquiry(String.t()) :: String.t()
  def inquiry(order_code) do
    """
    <inquiry>
      <orderInquiry orderCode="#{order_code}"/>
    </inquiry>
    """
  end

  @doc "Build a HPP order (hosted payment page redirect)."
  @spec hpp_order(keyword()) :: String.t()
  def hpp_order(opts) do
    order_code = Keyword.fetch!(opts, :order_code)
    amount = Keyword.fetch!(opts, :amount)
    currency = Keyword.fetch!(opts, :currency)
    exponent = Keyword.get(opts, :exponent, 2)
    description = Keyword.get(opts, :description, "")
    success_url = Keyword.get(opts, :success_url, "")
    failure_url = Keyword.get(opts, :failure_url, "")
    cancel_url = Keyword.get(opts, :cancel_url, "")
    shopper_email = Keyword.get(opts, :shopper_email)

    """
    <submit>
      <order orderCode="#{order_code}">
        <description>#{description}</description>
        <amount currencyCode="#{currency}" exponent="#{exponent}" value="#{amount}"/>
        #{maybe_shopper_email(shopper_email)}
        <paymentMethodMask>
          <include code="ALL"/>
        </paymentMethodMask>
        <successURL>#{success_url}</successURL>
        <failureURL>#{failure_url}</failureURL>
        <cancelURL>#{cancel_url}</cancelURL>
      </order>
    </submit>
    """
  end

  @doc "Build a split funding capture modification."
  @spec split_funding(String.t(), [map()]) :: String.t()
  def split_funding(order_code, splits) do
    splits_xml = Enum.map_join(splits, "\n", &split_funding_item/1)

    """
    <modify>
      <orderModification orderCode="#{order_code}">
        <capture>
          #{splits_xml}
        </capture>
      </orderModification>
    </modify>
    """
  end

  # ── private ───────────────────────────────────────────────────────────────

  @spec split_funding_item(map()) :: String.t()
  defp split_funding_item(s) do
    """
    <splitFunding>
      <reference>#{s["reference"]}</reference>
      <amount currencyCode="#{s["currency"]}" exponent="2" value="#{s["amount"]}"/>
    </splitFunding>
    """
  end

  @spec card_payment_details(String.t(), term(), term(), String.t(), String.t() | nil) ::
          String.t()
  defp card_payment_details(number, month, year, holder, cvc) do
    """
    <VISA-SSL>
      <cardNumber>#{number}</cardNumber>
      <expiryDate><date month="#{month}" year="#{year}"/></expiryDate>
      <cardHolderName>#{holder}</cardHolderName>
      #{if cvc, do: "<cvc>#{cvc}</cvc>"}
    </VISA-SSL>
    """
  end

  @spec maybe_attr(String.t(), String.t() | nil) :: String.t()
  defp maybe_attr(_name, nil), do: ""
  defp maybe_attr(name, val), do: ~s(#{name}="#{val}")

  @spec maybe_shopper_email(String.t() | nil) :: String.t()
  defp maybe_shopper_email(nil), do: ""
  defp maybe_shopper_email(email), do: "<shopper><emailAddress>#{email}</emailAddress></shopper>"

  @spec maybe_ip(String.t() | nil) :: String.t()
  defp maybe_ip(nil), do: ""
  defp maybe_ip(ip), do: "<shopperIPAddress>#{ip}</shopperIPAddress>"

  @spec maybe_narrative(String.t() | nil) :: String.t()
  defp maybe_narrative(nil), do: ""

  defp maybe_narrative(text) do
    "<statementNarrative><![CDATA[#{text}]]></statementNarrative>"
  end

  @spec maybe_installments(%{count: term(), currency: String.t(), amount: term()} | nil) ::
          String.t()
  defp maybe_installments(nil), do: ""

  defp maybe_installments(%{count: count, currency: curr, amount: amt}) do
    """
    <installments>
      <numberOfInstallments>#{count}</numberOfInstallments>
      <installmentAmount currencyCode="#{curr}" exponent="2" value="#{amt}"/>
    </installments>
    """
  end

  @spec maybe_level3(%{String.t() => term()} | nil) :: String.t()
  defp maybe_level3(nil), do: ""

  defp maybe_level3(data) do
    items_xml =
      (data["items"] || [])
      |> Enum.map_join("\n", &level3_item/1)

    """
    <branchSpecificExtension>
      <purchase>
        <customerReference>#{data["customerReference"]}</customerReference>
        <salesTax currencyCode="#{data["currency"]}" exponent="2" value="#{data["salesTax"]}"/>
        <discountAmount currencyCode="#{data["currency"]}" exponent="2" value="#{data["discount"] || 0}"/>
        #{items_xml}
      </purchase>
    </branchSpecificExtension>
    """
  end

  @spec level3_item(map()) :: String.t()
  defp level3_item(item) do
    """
    <item>
      <description>#{item["description"]}</description>
      <quantity>#{item["quantity"]}</quantity>
      <unitCost currencyCode="#{item["currency"]}" exponent="2" value="#{item["unitCost"]}"/>
      <unitTax currencyCode="#{item["currency"]}" exponent="2" value="#{item["unitTax"]}"/>
      <itemTotal currencyCode="#{item["currency"]}" exponent="2" value="#{item["total"]}"/>
    </item>
    """
  end
end

defmodule Worldpay.WPG.Parser do
  @moduledoc "Parses WPG XML responses into string-keyed maps."

  @doc "Parse a WPG XML response."
  @spec parse(String.t()) ::
          {:ok, %{String.t() => term()}} | {:error, {:xml_parse_error, Exception.t()}}
  def parse(xml) when is_binary(xml) do
    # :xmerl is included via :erlang/OTP; ensure :xmerl is in extra_applications.
    # :xmerl_scan.string/2 always returns a 2-tuple on success (it raises on
    # malformed XML, handled by the rescue clause below).
    {doc, _rest} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
    {:ok, element_to_map(doc)}
  rescue
    ex -> {:error, {:xml_parse_error, ex}}
  end

  @doc "Extract the last event from a parsed WPG response map."
  @spec last_event(%{String.t() => term()}) :: String.t() | nil
  def last_event(parsed) do
    get_in(parsed, ["paymentService", "reply", "orderStatus", "payment", "lastEvent"])
  end

  @doc "Extract the order code from a parsed WPG response map."
  @spec order_code(%{String.t() => term()}) :: String.t() | nil
  def order_code(parsed) do
    get_in(parsed, ["paymentService", "reply", "orderStatus", "@orderCode"])
  end

  @doc "Extract the FraudSight message from a WPG response map."
  @spec risk_score(%{String.t() => term()}) :: String.t() | nil
  def risk_score(parsed) do
    get_in(parsed, ["paymentService", "reply", "orderStatus", "payment", "FraudSight", "message"])
  end

  # ── private ───────────────────────────────────────────────────────────────

  @spec element_to_map(tuple()) :: %{String.t() => term()}
  defp element_to_map({:xmlElement, name, _, _, _, _, _, attrs, children, _, _, _}) do
    tag = to_string(name)
    attr_map = xml_attrs_to_map(attrs)
    child_map = xml_children_to_map(children)
    text = xml_element_text(children)

    %{tag => element_content(attr_map, child_map, text)}
  end

  defp element_to_map(_), do: %{}

  @spec xml_attrs_to_map(list()) :: %{String.t() => term()}
  defp xml_attrs_to_map(attrs) do
    Map.new(attrs, fn {:xmlAttribute, k, _, _, _, _, _, _, v, _} ->
      {"@#{k}", to_string(v)}
    end)
  end

  @spec xml_children_to_map(list()) :: %{String.t() => term()}
  defp xml_children_to_map(children) do
    children
    |> Enum.filter(&match?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, &1))
    |> Enum.map(&element_to_map/1)
    |> Enum.reduce(%{}, &merge_child_result/2)
  end

  @spec merge_child_result(%{String.t() => term()}, %{String.t() => term()}) ::
          %{String.t() => term()}
  defp merge_child_result(child, acc) do
    [{k, v}] = Map.to_list(child)

    case Map.get(acc, k) do
      nil -> Map.put(acc, k, v)
      existing when is_list(existing) -> Map.put(acc, k, [v | existing])
      existing -> Map.put(acc, k, [existing, v])
    end
  end

  @spec xml_element_text(list()) :: String.t()
  defp xml_element_text(children) do
    children
    |> Enum.filter(&match?({:xmlText, _, _, _, _, _}, &1))
    |> Enum.map_join("", fn {:xmlText, _, _, _, val, _} -> to_string(val) end)
    |> String.trim()
  end

  @spec element_content(%{String.t() => term()}, %{String.t() => term()}, String.t()) ::
          %{String.t() => term()} | String.t()
  defp element_content(attr_map, child_map, text) do
    cond do
      map_size(child_map) > 0 and map_size(attr_map) > 0 -> Map.merge(attr_map, child_map)
      map_size(child_map) > 0 -> child_map
      map_size(attr_map) > 0 and text != "" -> Map.put(attr_map, "#text", text)
      map_size(attr_map) > 0 -> attr_map
      text != "" -> text
      true -> %{}
    end
  end
end

defmodule Worldpay.WPG do
  @moduledoc """
  Worldpay **WPG (Worldpay Payment Gateway)** — XML-based gateway client.

  Supports: Direct, HPP, Direct Elements, tokenisation, 3DS, FraudSight,
  split funding, modifications (capture/cancel/refund), and inquiries.

  ## Example

      config = Worldpay.Config.new()

      xml =
        Worldpay.WPG.Builder.order(
          order_code: "order-001",
          amount: 1999,
          currency: "GBP",
          card_number: "4444333322221111",
          exp_month: "05",
          exp_year: "2035",
          card_holder: "Jane Doe",
          cvc: "123"
        )
        |> Worldpay.WPG.Builder.envelope(merchant_code: config.wpg_merchant_code)

      {:ok, response} = Worldpay.WPG.submit(xml, config)
      Worldpay.WPG.Parser.last_event(response)  # => "AUTHORISED"
  """

  alias Worldpay.{Client, Config, Error, WPG}

  @doc "Submit a WPG XML document and return a parsed map."
  @spec submit(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def submit(xml, %Config{} = config) do
    case Client.wpg_post(xml, config) do
      {:ok, body} ->
        case WPG.Parser.parse(body) do
          {:ok, parsed} ->
            {:ok, parsed}

          {:error, reason} ->
            {:error,
             %Error{
               type: :decode_error,
               reason: :xml_parse_error,
               message: "Failed to parse WPG XML response",
               raw: inspect(reason)
             }}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc "Submit and return the raw XML body without parsing."
  @spec submit_raw(String.t(), Config.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def submit_raw(xml, %Config{} = config) do
    Client.wpg_post(xml, config)
  end

  @doc "Authorize a card payment via WPG Direct."
  @spec authorize(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def authorize(opts, %Config{} = config) do
    opts
    |> WPG.Builder.order()
    |> WPG.Builder.envelope(merchant_code: config.wpg_merchant_code)
    |> submit(config)
  end

  @doc "Capture (settle) a WPG authorization."
  @spec capture(String.t(), non_neg_integer(), String.t(), Config.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def capture(order_code, amount, currency, %Config{} = config) do
    xml = WPG.Builder.capture(order_code, amount, currency)

    xml
    |> WPG.Builder.envelope(merchant_code: config.wpg_merchant_code)
    |> submit(config)
  end

  @doc "Cancel a WPG authorization."
  @spec cancel(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def cancel(order_code, %Config{} = config) do
    xml = WPG.Builder.cancel(order_code)

    xml
    |> WPG.Builder.envelope(merchant_code: config.wpg_merchant_code)
    |> submit(config)
  end

  @doc "Refund a WPG payment."
  @spec refund(String.t(), non_neg_integer(), String.t(), Config.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def refund(order_code, amount, currency, %Config{} = config) do
    xml = WPG.Builder.refund(order_code, amount, currency)

    xml
    |> WPG.Builder.envelope(merchant_code: config.wpg_merchant_code)
    |> submit(config)
  end

  @doc "Inquire on a WPG order."
  @spec inquiry(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def inquiry(order_code, %Config{} = config) do
    xml = WPG.Builder.inquiry(order_code)

    xml
    |> WPG.Builder.envelope(merchant_code: config.wpg_merchant_code)
    |> submit(config)
  end
end
