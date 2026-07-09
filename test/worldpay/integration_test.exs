defmodule Worldpay.WebhooksTest do
  use ExUnit.Case, async: true

  alias Worldpay.Webhooks

  describe "parse/1" do
    test "parses authorized JSON event" do
      body =
        Jason.encode!(%{
          "paymentId" => "pay-001",
          "lastEvent" => "AUTHORISED",
          "orderReference" => "order-001",
          "commandId" => "cmd-001",
          "value" => %{"amount" => 1999, "currency" => "GBP"},
          "paymentInstrument" => %{"type" => "card/plain"}
        })

      assert {:ok, event} = Webhooks.parse(body)
      assert event.type == :authorized
      assert event.payment_id == "pay-001"
      assert event.amount == %{"amount" => 1999, "currency" => "GBP"}
    end

    test "parses settled event" do
      body = Jason.encode!(%{"paymentId" => "pay-002", "lastEvent" => "SETTLED"})
      assert {:ok, event} = Webhooks.parse(body)
      assert event.type == :settled
    end

    test "parses refunded event" do
      body = Jason.encode!(%{"paymentId" => "pay-003", "lastEvent" => "REFUNDED"})
      assert {:ok, event} = Webhooks.parse(body)
      assert event.type == :refunded
    end

    test "parses charged_back event" do
      body = Jason.encode!(%{"paymentId" => "pay-004", "lastEvent" => "CHARGED_BACK"})
      assert {:ok, event} = Webhooks.parse(body)
      assert event.type == :charged_back
    end

    test "parses APM authorized event as apm_authorized" do
      body =
        Jason.encode!(%{
          "paymentId" => "pay-apm-001",
          "lastEvent" => "AUTHORISED",
          "paymentInstrument" => %{"type" => "ideal/redirect"}
        })

      assert {:ok, event} = Webhooks.parse(body)
      assert event.type == :apm_authorized
    end

    test "parses payout sent event" do
      body = Jason.encode!(%{"paymentId" => "pay-005", "lastEvent" => "PAYOUT_SENT"})
      assert {:ok, event} = Webhooks.parse(body)
      assert event.type == :payout_sent
    end

    test "parses pix confirmed event" do
      body = Jason.encode!(%{"paymentId" => "pay-pix-001", "lastEvent" => "PIX_CONFIRMED"})
      assert {:ok, event} = Webhooks.parse(body)
      assert event.type == :pix_confirmed
    end

    test "handles unknown event types gracefully" do
      body = Jason.encode!(%{"paymentId" => "pay-006", "lastEvent" => "SOME_FUTURE_EVENT"})
      assert {:ok, event} = Webhooks.parse(body)
      assert is_atom(event.type)
    end

    test "returns error on invalid JSON" do
      assert {:error, _} = Webhooks.parse("not valid json {{{")
    end

    test "parses map directly" do
      body = %{"paymentId" => "pay-007", "lastEvent" => "CANCELLED"}
      assert {:ok, event} = Webhooks.parse(body)
      assert event.type == :cancelled
    end
  end

  describe "handle/2" do
    defmodule TestHandler do
      @behaviour Worldpay.Webhooks.Handler

      @impl true
      @spec handle_event(map()) :: :ok | {:error, term()}
      def handle_event(%{type: :authorized}), do: :ok
      def handle_event(%{type: :settled}), do: {:error, :downstream_error}
      def handle_event(_event), do: :ok
    end

    test "dispatches to handler and returns :ok" do
      {:ok, event} = Webhooks.parse(%{"paymentId" => "p", "lastEvent" => "AUTHORISED"})
      assert :ok = Webhooks.handle(event, TestHandler)
    end

    test "returns handler error result" do
      {:ok, event} = Webhooks.parse(%{"paymentId" => "p", "lastEvent" => "SETTLED"})
      assert {:error, :downstream_error} = Webhooks.handle(event, TestHandler)
    end
  end
end

defmodule Worldpay.CardBINTest do
  use ExUnit.Case, async: true

  alias Worldpay.{CardBIN, Factory}

  setup do
    bypass = Bypass.open()
    config = Factory.config(base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, config: config}
  end

  describe "lookup/2" do
    test "GETs BIN info", %{bypass: bypass, config: config} do
      response = %{
        "type" => "card",
        "brand" => ["visa"],
        "bin" => "444433",
        "fundingType" => "credit",
        "issuerName" => "Test Bank",
        "countryCode" => "GB",
        "dccAllowed" => true
      }

      Bypass.expect_once(bypass, "GET", "/cardBin/444433", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response))
      end)

      assert {:ok, result} = CardBIN.lookup("444433", config)
      assert result["fundingType"] == "credit"
      assert result["dccAllowed"] == true
    end

    test "lookup_v2 uses v2 path", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/cardBin/v2/44443333", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"bin" => "44443333"}))
      end)

      assert {:ok, _} = CardBIN.lookup_v2("44443333", config)
    end
  end
end

defmodule Worldpay.WPGBuilderTest do
  use ExUnit.Case, async: true

  alias Worldpay.WPG.Builder

  describe "envelope/2" do
    test "wraps XML in paymentService envelope" do
      xml = Builder.envelope("<submit/>", merchant_code: "TESTMERCHANT")
      assert xml =~ "paymentService"
      assert xml =~ ~s(merchantCode="TESTMERCHANT")
    end

    test "includes xml declaration" do
      xml = Builder.envelope("<submit/>", merchant_code: "TESTMERCHANT")
      assert xml =~ ~s(<?xml version="1.0")
    end
  end

  describe "order/1" do
    test "builds a valid order XML" do
      xml =
        Builder.order(
          order_code: "order-001",
          amount: 1999,
          currency: "GBP",
          card_number: "4444333322221111",
          exp_month: "05",
          exp_year: "2035",
          card_holder: "Jane Doe",
          cvc: "123"
        )

      assert xml =~ ~s(orderCode="order-001")
      assert xml =~ "4444333322221111"
      assert xml =~ ~s(value="1999")
      assert xml =~ ~s(currencyCode="GBP")
      assert xml =~ "<cvc>123</cvc>"
    end
  end

  describe "capture/3" do
    test "builds capture modification XML" do
      xml = Builder.capture("order-001", 1999, "GBP")
      assert xml =~ "<capture>"
      assert xml =~ ~s(orderCode="order-001")
      assert xml =~ ~s(value="1999")
    end
  end

  describe "cancel/1" do
    test "builds cancel modification XML" do
      xml = Builder.cancel("order-001")
      assert xml =~ "<cancel/>"
      assert xml =~ ~s(orderCode="order-001")
    end
  end

  describe "refund/4" do
    test "builds refund modification XML" do
      xml = Builder.refund("order-001", 500, "GBP")
      assert xml =~ "<refund>"
      assert xml =~ ~s(value="500")
    end
  end

  describe "inquiry/1" do
    test "builds inquiry XML" do
      xml = Builder.inquiry("order-001")
      assert xml =~ "<inquiry>"
      assert xml =~ ~s(orderCode="order-001")
    end
  end

  describe "token_order/1" do
    test "builds token order XML" do
      xml =
        Builder.token_order(
          order_code: "tok-order-001",
          amount: 999,
          currency: "USD",
          token_id: "TOKEN-XYZ",
          cvc: "456"
        )

      assert xml =~ "TOKEN-XYZ"
      assert xml =~ "<cvc>456</cvc>"
      assert xml =~ ~s(value="999")
    end
  end

  describe "hpp_order/1" do
    test "builds HPP order with result URLs" do
      xml =
        Builder.hpp_order(
          order_code: "hpp-001",
          amount: 2500,
          currency: "EUR",
          success_url: "https://example.com/success",
          failure_url: "https://example.com/failure",
          cancel_url: "https://example.com/cancel"
        )

      assert xml =~ "https://example.com/success"
      assert xml =~ "<successURL>"
      assert xml =~ "<paymentMethodMask>"
    end
  end
end

defmodule Worldpay.WPGParserTest do
  use ExUnit.Case, async: true

  alias Worldpay.WPG.Parser

  @authorised_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <paymentService version="1.4" merchantCode="TESTMERCHANT">
    <reply>
      <orderStatus orderCode="order-001">
        <payment>
          <lastEvent>AUTHORISED</lastEvent>
          <balance accountType="IN_PROCESS_AUTHORISED">
            <amount value="1999" currencyCode="GBP" exponent="2" debitCreditIndicator="credit"/>
          </balance>
        </payment>
      </orderStatus>
    </reply>
  </paymentService>
  """

  @error_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <paymentService version="1.4" merchantCode="TESTMERCHANT">
    <reply>
      <error code="2">Internal error encountered</error>
    </reply>
  </paymentService>
  """

  describe "parse/1" do
    test "parses authorised response" do
      assert {:ok, parsed} = Parser.parse(@authorised_xml)
      assert Parser.last_event(parsed) == "AUTHORISED"
      assert Parser.order_code(parsed) == "order-001"
    end

    test "parses error response without crash" do
      assert {:ok, _parsed} = Parser.parse(@error_xml)
    end

    test "returns error on malformed XML" do
      assert {:error, _reason} = Parser.parse("not xml at all <{{>")
    end
  end
end

defmodule Worldpay.CNPBuilderTest do
  use ExUnit.Case, async: true

  alias Worldpay.CNP.Builder

  describe "sale/1" do
    test "builds sale XML" do
      xml =
        Builder.sale(
          id: "txn-001",
          order_id: "order-001",
          amount: 1999,
          card: %{
            number: "4444333322221111",
            exp_month: 5,
            exp_year: 2035,
            type: "VI",
            cvc: "123"
          }
        )

      assert xml =~ "<sale"
      assert xml =~ "<amount>1999</amount>"
      assert xml =~ "4444333322221111"
    end
  end

  describe "authorization/1" do
    test "builds authorization XML" do
      xml =
        Builder.authorization(
          id: "auth-001",
          order_id: "order-001",
          amount: 999,
          card: %{number: "4444333322221111", exp_month: 3, exp_year: 2030, type: "VI"}
        )

      assert xml =~ "<authorization"
      assert xml =~ "<amount>999</amount>"
    end
  end

  describe "void/1" do
    test "builds void XML" do
      xml = Builder.void(id: "void-001", cnp_txn_id: "12345678901234567")
      assert xml =~ "<void"
      assert xml =~ "12345678901234567"
    end
  end

  describe "capture/1" do
    test "builds capture XML" do
      xml = Builder.capture(id: "cap-001", cnp_txn_id: "12345678901234567", amount: 500)
      assert xml =~ "<capture"
      assert xml =~ "<amount>500</amount>"
    end
  end

  describe "credit/1" do
    test "builds credit (refund) XML" do
      xml =
        Builder.credit(
          id: "credit-001",
          order_id: "order-001",
          amount: 500,
          cnp_txn_id: "12345678901234567"
        )

      assert xml =~ "<credit"
      assert xml =~ "<amount>500</amount>"
    end
  end

  describe "echeck_sale/1" do
    test "builds eCheck sale XML" do
      xml =
        Builder.echeck_sale(
          id: "eck-001",
          order_id: "order-eck-001",
          amount: 7500,
          account_number: "1234567890",
          routing_number: "021000021"
        )

      assert xml =~ "<echeckSale"
      assert xml =~ "1234567890"
      assert xml =~ "021000021"
    end
  end

  describe "envelope/2" do
    test "wraps in cnpRequest" do
      inner =
        Builder.sale(
          id: "x",
          order_id: "o",
          amount: 100,
          card: %{number: "4111111111111111", exp_month: 1, exp_year: 2030, type: "VI"}
        )

      xml = Builder.envelope(inner, merchant_id: "MERCH-001", user: "user", password: "pass")
      assert xml =~ "<cnpRequest"
      assert xml =~ ~s(merchantId="MERCH-001")
      assert xml =~ "<user>user</user>"
    end
  end
end

defmodule Worldpay.CNPParserTest do
  use ExUnit.Case, async: true

  alias Worldpay.CNP.Parser

  @approved_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <cnpResponse version="12.0" xmlns="http://www.vantiv.cnp.com/schema"
      id="req-001" response="0" message="Valid Format" merchantId="MERCH-001">
    <saleResponse id="txn-001" reportGroup="Default">
      <cnpTxnId>82737588000000</cnpTxnId>
      <orderId>order-001</orderId>
      <response>000</response>
      <responseTime>2026-01-01T12:00:00</responseTime>
      <message>Approved</message>
      <authCode>12345A</authCode>
    </saleResponse>
  </cnpResponse>
  """

  @declined_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <cnpResponse version="12.0" xmlns="http://www.vantiv.cnp.com/schema"
      id="req-002" response="0" message="Valid Format" merchantId="MERCH-001">
    <authorizationResponse id="auth-002" reportGroup="Default">
      <cnpTxnId>82737588000001</cnpTxnId>
      <orderId>order-002</orderId>
      <response>110</response>
      <message>Insufficient Funds</message>
    </authorizationResponse>
  </cnpResponse>
  """

  describe "parse/1" do
    test "parses approved sale response" do
      assert {:ok, parsed} = Parser.parse(@approved_xml)
      assert Parser.approved?(parsed) == true
      assert Parser.response_code(parsed) == "000"
      assert Parser.txn_id(parsed) == "82737588000000"
    end

    test "parses declined authorization response" do
      assert {:ok, parsed} = Parser.parse(@declined_xml)
      assert Parser.approved?(parsed) == false
      assert Parser.response_code(parsed) == "110"
    end

    test "returns error on invalid XML" do
      assert {:error, _} = Parser.parse("<<invalid>>")
    end
  end
end

defmodule Worldpay.PayoutsTest do
  use ExUnit.Case, async: true

  alias Worldpay.{AccountPayouts, CardPayouts, Factory, FX, MoneyTransfers}

  setup do
    bypass = Bypass.open()
    config = Factory.config(base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, config: config}
  end

  describe "CardPayouts.disburse/3" do
    test "POSTs to /cardPayouts", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/cardPayouts", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"payoutId" => "pout-001"}))
      end)

      assert {:ok, result} = CardPayouts.disburse(%{}, config)
      assert result["payoutId"] == "pout-001"
    end
  end

  describe "CardPayouts.fast_access/3" do
    test "POSTs to /cardPayouts/fastAccess", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/cardPayouts/fastAccess", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"payoutId" => "pout-fast-001"}))
      end)

      assert {:ok, result} = CardPayouts.fast_access(%{}, config)
      assert result["payoutId"] == "pout-fast-001"
    end

    test "adds fallbackToBasic when option set", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/cardPayouts/fastAccess", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["fallbackToBasic"] == true

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{}))
      end)

      CardPayouts.fast_access(%{}, config, fallback_to_basic: true)
    end
  end

  describe "AccountPayouts.pay/3" do
    test "POSTs to /payouts/accounts", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/payouts/accounts", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"payoutId" => "acct-pout-001"}))
      end)

      assert {:ok, _result} = AccountPayouts.pay(%{}, config)
    end
  end

  describe "FX.get_rate/3" do
    test "GETs FX rate", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/fx/rates", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"rate" => 1.25}))
      end)

      assert {:ok, result} = FX.get_rate("GBP", "USD", config)
      assert result["rate"] == 1.25
    end
  end

  describe "FX.create_quote/2" do
    test "POSTs to /fx/quotes", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/fx/quotes", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"quoteId" => "quote-001", "rate" => 1.2567}))
      end)

      assert {:ok, result} = FX.create_quote(%{"sourceCurrency" => "GBP"}, config)
      assert result["quoteId"] == "quote-001"
    end
  end
end

defmodule Worldpay.MarketplacesTest do
  use ExUnit.Case, async: true

  alias Worldpay.Factory
  alias Worldpay.Marketplaces.{Parties, SplitPayments}

  setup do
    bypass = Bypass.open()
    config = Factory.config(base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, config: config}
  end

  describe "Parties.create/2" do
    test "POSTs to /parties", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/parties", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"partyId" => "party-001"}))
      end)

      assert {:ok, result} = Parties.create(%{}, config)
      assert result["partyId"] == "party-001"
    end
  end

  describe "Parties.add_beneficial_owner/3" do
    test "POSTs to correct path", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/parties/party-001/beneficialOwners", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"ownerId" => "owner-001"}))
      end)

      assert {:ok, result} =
               Parties.add_beneficial_owner("party-001", %{name: "Jane Doe"}, config)

      assert result["ownerId"] == "owner-001"
    end
  end

  describe "Parties.delete_beneficial_owner/3" do
    test "DELETEs from correct path", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/parties/party-001/beneficialOwners/owner-001",
        fn conn ->
          Plug.Conn.send_resp(conn, 204, "")
        end
      )

      assert {:ok, nil} = Parties.delete_beneficial_owner("party-001", "owner-001", config)
    end
  end

  describe "SplitPayments.split/3" do
    test "POSTs to /splitPayments with version header", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/splitPayments", fn conn ->
        version = Plug.Conn.get_req_header(conn, "wp-api-version")
        assert version == ["2025-06-25"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"splitPaymentId" => "split-001"}))
      end)

      assert {:ok, result} = SplitPayments.split(%{}, config)
      assert result["splitPaymentId"] == "split-001"
    end
  end
end
