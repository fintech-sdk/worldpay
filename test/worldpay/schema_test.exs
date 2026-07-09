defmodule Worldpay.SchemaTest do
  use ExUnit.Case, async: true

  alias Worldpay.Schema.{
    Address,
    Amount,
    CustomerAgreement,
    Merchant,
    Narrative,
    PaymentInstrument,
    ThreeDS
  }

  describe "Amount" do
    test "to_map/1 serializes correctly" do
      amount = %Amount{value: 1999, currency: "GBP"}
      assert Amount.to_map(amount) == %{"value" => 1999, "currency" => "GBP"}
    end

    test "from_map/1 with string keys" do
      amount = Amount.from_map(%{"value" => 500, "currency" => "USD"})
      assert amount.value == 500
      assert amount.currency == "USD"
    end

    test "from_map/1 with atom keys" do
      amount = Amount.from_map(%{value: 100, currency: "EUR"})
      assert amount.value == 100
    end
  end

  describe "Address" do
    test "to_map/1 drops nil fields" do
      addr = %Address{
        address1: "123 Main St",
        city: "London",
        postal_code: "SW1A 1AA",
        country_code: "GB"
      }

      map = Address.to_map(addr)
      assert map["address1"] == "123 Main St"
      assert map["postalCode"] == "SW1A 1AA"
      assert map["countryCode"] == "GB"
      refute Map.has_key?(map, "address2")
      refute Map.has_key?(map, "state")
    end
  end

  describe "Narrative" do
    test "to_map/1 includes line2 when present" do
      n = %Narrative{line1: "My Store", line2: "Order #123"}
      map = Narrative.to_map(n)
      assert map["line1"] == "My Store"
      assert map["line2"] == "Order #123"
    end

    test "to_map/1 omits line2 when nil" do
      n = %Narrative{line1: "My Store"}
      map = Narrative.to_map(n)
      refute Map.has_key?(map, "line2")
    end
  end

  describe "CustomerAgreement" do
    test "encodes card_on_file type" do
      ca = %CustomerAgreement{type: :card_on_file, stored_card_usage: :first}
      map = CustomerAgreement.to_map(ca)
      assert map["type"] == "cardOnFile"
      assert map["storedCardUsage"] == "first"
    end

    test "encodes subscription with scheme reference" do
      ca = %CustomerAgreement{
        type: :subscription,
        stored_card_usage: :subsequent,
        scheme_reference: "SCHEME123"
      }

      map = CustomerAgreement.to_map(ca)
      assert map["type"] == "subscription"
      assert map["schemeReference"] == "SCHEME123"
    end
  end

  describe "ThreeDS" do
    test "to_map/1 builds auth object" do
      t = %ThreeDS{
        type: "integrated",
        eci: "05",
        authentication_value: "AAABBBccc=",
        transaction_id: "txn-123",
        version: "2.1.0"
      }

      map = ThreeDS.to_map(t)
      assert map["eci"] == "05"
      assert map["authenticationValue"] == "AAABBBccc="
      assert map["version"] == "2.1.0"
    end
  end

  describe "PaymentInstrument" do
    test "card/plain serializes all required fields" do
      pi = %PaymentInstrument{
        type: "card/plain",
        card_holder_name: "Jane Doe",
        card_number: "4444333322221111",
        expiry_month: 5,
        expiry_year: 2035,
        cvc: "123"
      }

      map = PaymentInstrument.to_map(pi)
      assert map["type"] == "card/plain"
      assert map["cardHolderName"] == "Jane Doe"
      assert map["cardNumber"] == "4444333322221111"
      assert map["cardExpiryDate"] == %{"month" => 5, "year" => 2035}
      assert map["cvc"] == "123"
    end

    test "card/token serializes href" do
      pi = %PaymentInstrument{
        type: "card/token",
        href: "https://try.access.worldpay.com/tokens/abc"
      }

      map = PaymentInstrument.to_map(pi)
      assert map["type"] == "card/token"
      assert map["href"] == "https://try.access.worldpay.com/tokens/abc"
    end

    test "card/checkout serializes session href" do
      pi = %PaymentInstrument{
        type: "card/checkout",
        session_href: "https://try.access.worldpay.com/sessions/xyz"
      }

      map = PaymentInstrument.to_map(pi)
      assert map["type"] == "card/checkout"
      assert map["href"] == "https://try.access.worldpay.com/sessions/xyz"
    end

    test "card/networkToken includes cryptogram" do
      pi = %PaymentInstrument{
        type: "card/networkToken",
        href: "https://try.access.worldpay.com/tokens/npt-abc",
        cryptogram: "AAABBB==",
        eci: "07"
      }

      map = PaymentInstrument.to_map(pi)
      assert map["cryptogram"] == "AAABBB=="
      assert map["eci"] == "07"
    end
  end
end
