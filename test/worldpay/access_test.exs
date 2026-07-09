defmodule Worldpay.CardPaymentsTest do
  use ExUnit.Case, async: true

  alias Worldpay.{CardPayments, Factory}

  setup do
    bypass = Bypass.open()
    config = Factory.config(base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, config: config}
  end

  describe "authorize/3" do
    test "returns ok on 201", %{bypass: bypass, config: config} do
      response = Factory.authorized_response()

      Bypass.expect_once(bypass, "POST", "/payments/authorizations", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(response))
      end)

      body = Factory.card_payment_instruction()
      assert {:ok, result} = CardPayments.authorize(body, config)
      assert result["lastEvent"] == "AUTHORISED"
      assert is_binary(result["paymentId"])
    end

    test "returns error on 400", %{bypass: bypass, config: config} do
      error_body = %{"customCode" => "CARD_INVALID", "message" => "Card number invalid"}

      Bypass.expect_once(bypass, "POST", "/payments/authorizations", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(error_body))
      end)

      assert {:error, error} = CardPayments.authorize(%{}, config)
      assert error.status == 400
      assert error.type == :api_error
    end

    test "sends WP-Api-Version header", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/payments/authorizations", fn conn ->
        version = Plug.Conn.get_req_header(conn, "wp-api-version")
        assert version != []

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(Factory.authorized_response()))
      end)

      CardPayments.authorize(Factory.card_payment_instruction(), config)
    end

    test "sends Authorization header", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/payments/authorizations", fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        assert ["Basic " <> _] = auth

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(Factory.authorized_response()))
      end)

      CardPayments.authorize(Factory.card_payment_instruction(), config)
    end
  end

  describe "settle/3" do
    test "POSTs to correct settlement path", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/payments/settlements/full/pay-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"lastEvent" => "SENT_FOR_SETTLEMENT"}))
      end)

      assert {:ok, _result} = CardPayments.settle("pay-123", config)
    end
  end

  describe "cancel/3" do
    test "POSTs to cancellation path", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/payments/authorizations/cancellations/pay-123",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(%{"lastEvent" => "CANCELLED"}))
        end
      )

      assert {:ok, _result} = CardPayments.cancel("pay-123", config)
    end
  end

  describe "refund/3" do
    test "POSTs to refund path", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/payments/authorizations/refunds/pay-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"lastEvent" => "REFUNDED"}))
      end)

      assert {:ok, _result} = CardPayments.refund("pay-123", config)
    end
  end

  describe "partial_refund/5" do
    test "sends amount and currency in body", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/payments/authorizations/refunds/pay-123", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["value"]["amount"] == 500
        assert decoded["value"]["currency"] == "GBP"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"lastEvent" => "PARTIALLY_REFUNDED"}))
      end)

      assert {:ok, _result} = CardPayments.partial_refund("pay-123", 500, "GBP", config)
    end
  end

  describe "events/2" do
    test "GETs payment events", %{bypass: bypass, config: config} do
      events = %{"events" => [%{"type" => "authorized"}, %{"type" => "settled"}]}

      Bypass.expect_once(bypass, "GET", "/payments/events/pay-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(events))
      end)

      assert {:ok, result} = CardPayments.events("pay-123", config)
      assert length(result["events"]) == 2
    end
  end

  describe "mit/3" do
    test "POSTs to MIT endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/payments/authorizations/merch-initiated", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(Factory.authorized_response()))
      end)

      body =
        CardPayments.build_mit(
          transaction_reference: "mit-001",
          narrative: "Monthly Sub",
          amount: 999,
          currency: "USD",
          payment_instrument: %{
            "type" => "card/token",
            "href" => "https://try.access.worldpay.com/tokens/abc"
          },
          scheme_reference: "SCHEME-REF-001"
        )

      assert {:ok, _result} = CardPayments.mit(body, config)
    end
  end

  describe "build_cit/1" do
    test "builds a valid CIT instruction" do
      instruction =
        CardPayments.build_cit(
          transaction_reference: "txn-001",
          narrative: "My Store",
          amount: 1500,
          currency: "USD",
          payment_instrument: %{"type" => "card/plain"}
        )

      assert instruction["transactionReference"] == "txn-001"
      assert get_in(instruction, ["instruction", "value", "amount"]) == 1500
      assert get_in(instruction, ["instruction", "narrative", "line1"]) == "My Store"
    end
  end
end

defmodule Worldpay.APMsTest do
  use ExUnit.Case, async: true

  alias Worldpay.{APMs, Factory}

  setup do
    bypass = Bypass.open()
    config = Factory.config(base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, config: config}
  end

  describe "pay/3" do
    test "submits an APM payment", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/payments/alternative/direct", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          201,
          Jason.encode!(%{"paymentId" => "apm-pay-001", "lastEvent" => "AUTHORISED"})
        )
      end)

      body = %{
        "transactionReference" => "order-apm-001",
        "merchant" => %{"entity" => "default"},
        "instruction" => %{
          "value" => %{"amount" => 1500, "currency" => "EUR"},
          "paymentInstrument" => APMs.ideal()
        }
      }

      assert {:ok, result} = APMs.pay(body, config)
      assert result["paymentId"] == "apm-pay-001"
    end
  end

  describe "instrument builders" do
    test "ideal/1 builds correct type" do
      pi = APMs.ideal()
      assert pi["type"] == "ideal/redirect"
    end

    test "ideal/1 with token_href" do
      pi = APMs.ideal(token_href: "https://tokens/abc")
      assert pi["tokenHref"] == "https://tokens/abc"
    end

    test "klarna/2 builds correct types" do
      pi = APMs.klarna("payLater", locale: "en-GB", shopper_email: "test@example.com")
      assert pi["type"] == "klarna/payLater"
      assert pi["locale"] == "en-GB"
      assert pi["shopperEmail"] == "test@example.com"
    end

    test "klarna/2 raises on invalid type" do
      assert_raise ArgumentError, fn ->
        APMs.klarna("invalidType")
      end
    end

    test "ach/3 builds correct instrument" do
      pi = APMs.ach("12345678", "021000021", "savings")
      assert pi["type"] == "ach/direct"
      assert pi["accountType"] == "savings"
    end

    test "pix/2 includes CPF" do
      pi = APMs.pix("12345678901", expiry_in: 3600)
      assert pi["type"] == "pix/qrCode"
      assert hd(pi["identityDocuments"])["type"] == "CPF"
      assert pi["expiryIn"] == 3600
    end

    test "sepa/2 builds correct fields" do
      pi = APMs.sepa("DE89370400440532013000", "MANDATE-001")
      assert pi["type"] == "sepa/direct"
      assert pi["iban"] == "DE89370400440532013000"
    end

    test "swish/1 includes phone" do
      pi = APMs.swish("+46701234567")
      assert pi["type"] == "swish/redirect"
      assert pi["shopperPhone"] == "+46701234567"
    end

    test "blik/1 includes code" do
      pi = APMs.blik("123456")
      assert pi["type"] == "blik/direct"
      assert pi["blikCode"] == "123456"
    end

    test "open_banking/1 builds redirect" do
      pi = APMs.open_banking(bank_id: "MONZO", country_code: "GB")
      assert pi["type"] == "openBanking/redirect"
      assert pi["countryCode"] == "GB"
    end
  end
end

defmodule Worldpay.TokensTest do
  use ExUnit.Case, async: true

  alias Worldpay.{Factory, Tokens}

  setup do
    bypass = Bypass.open()
    config = Factory.config(base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, config: config}
  end

  describe "create/2" do
    test "creates a token", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/tokens", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          201,
          Jason.encode!(%{
            "tokenPaymentInstrument" => %{
              "href" => "https://try.access.worldpay.com/tokens/tok-abc123"
            }
          })
        )
      end)

      assert {:ok, result} =
               Tokens.create(%{"paymentInstrument" => %{"type" => "card/front"}}, config)

      assert get_in(result, ["tokenPaymentInstrument", "href"]) =~ "tok-abc123"
    end
  end

  describe "get/2" do
    test "retrieves a token", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/tokens/tok-abc123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"tokenId" => "tok-abc123"}))
      end)

      assert {:ok, result} = Tokens.get("tok-abc123", config)
      assert result["tokenId"] == "tok-abc123"
    end
  end

  describe "delete/2" do
    test "deletes a token successfully (204)", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "DELETE", "/tokens/tok-abc123", fn conn ->
        Plug.Conn.send_resp(conn, 204, "")
      end)

      assert {:ok, nil} = Tokens.delete("tok-abc123", config)
    end
  end

  describe "create_network_token/2" do
    test "creates an NPT", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/tokens/networkTokens", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"networkTokenId" => "npt-xyz"}))
      end)

      assert {:ok, result} = Tokens.create_network_token(%{}, config)
      assert result["networkTokenId"] == "npt-xyz"
    end
  end

  describe "provision_cryptogram/2" do
    test "provisions a cryptogram", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/tokens/networkTokens/npt-xyz/cryptograms", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"cryptogram" => "AAABBB==", "eci" => "07"}))
      end)

      assert {:ok, result} = Tokens.provision_cryptogram("npt-xyz", config)
      assert result["cryptogram"] == "AAABBB=="
    end
  end
end

defmodule Worldpay.FraudSightTest do
  use ExUnit.Case, async: true

  alias Worldpay.{Factory, FraudSight}

  setup do
    bypass = Bypass.open()
    config = Factory.config(base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, config: config}
  end

  describe "assess/2" do
    test "returns not high risk response", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/fraudsight/assessments", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(Factory.fraudsight_response("notHighRisk")))
      end)

      assert {:ok, result} = FraudSight.assess(%{}, config)
      assert result["outcome"] == "notHighRisk"
    end
  end

  describe "assess_and_extract_href/2" do
    test "returns href on notHighRisk", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/fraudsight/assessments", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(Factory.fraudsight_response("notHighRisk")))
      end)

      assert {:ok, href} = FraudSight.assess_and_extract_href(%{}, config)
      assert href =~ "fraudsight"
    end

    test "returns :high_risk error on highRisk", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/fraudsight/assessments", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(Factory.fraudsight_response("highRisk")))
      end)

      assert {:error, :high_risk} = FraudSight.assess_and_extract_href(%{}, config)
    end
  end
end

defmodule Worldpay.ThreeDSTest do
  use ExUnit.Case, async: true

  alias Worldpay.{Factory, ThreeDS}

  setup do
    bypass = Bypass.open()
    config = Factory.config(base_url: "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, config: config}
  end

  describe "authenticate/2" do
    test "returns authenticated response", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/verifications/customers/3ds/authentication", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(Factory.three_ds_auth_response("authenticated"))
        )
      end)

      assert {:ok, result} = ThreeDS.authenticate(%{}, config)
      assert result["outcome"] == "authenticated"
      assert result["eci"] == "05"
    end
  end

  describe "authenticate_and_extract/2" do
    test "extracts auth fields on success", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/verifications/customers/3ds/authentication", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(Factory.three_ds_auth_response("authenticated"))
        )
      end)

      assert {:ok, result} = ThreeDS.authenticate_and_extract(%{}, config)
      assert result.eci == "05"
      assert result.authentication_value == "AAABBBcccDDDeeeFFFgggHHH="
    end

    test "returns error on challenged outcome", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/verifications/customers/3ds/authentication", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(Factory.three_ds_auth_response("challenged")))
      end)

      assert {:error, error} = ThreeDS.authenticate_and_extract(%{}, config)
      assert error.reason == :challenge_required
    end
  end

  describe "build_auth_object/1" do
    test "builds threeDS map from response" do
      resp = Factory.three_ds_auth_response("authenticated")
      obj = ThreeDS.build_auth_object(resp)

      assert obj["type"] == "integrated"
      assert obj["eci"] == "05"
      assert obj["authenticationValue"] == "AAABBBcccDDDeeeFFFgggHHH="
    end
  end
end
