defmodule Worldpay.Factory do
  @moduledoc "Test data factories."

  @spec config(keyword()) :: Worldpay.Config.t()
  def config(overrides \\ []) do
    Worldpay.Config.new(
      Keyword.merge(
        [
          username: "test-user",
          password: "test-password",
          environment: :try,
          wpg_merchant_code: "TESTMERCHANT",
          wpg_username: "wpg-user",
          wpg_password: "wpg-pass",
          circuit_breaker: false
        ],
        overrides
      )
    )
  end

  @spec card_payment_instruction(map()) :: map()
  def card_payment_instruction(overrides \\ %{}) do
    Map.merge(
      %{
        "transactionReference" => "test-#{System.unique_integer([:positive])}",
        "merchant" => %{"entity" => "default"},
        "instruction" => %{
          "narrative" => %{"line1" => "Test Store"},
          "value" => %{"amount" => 1999, "currency" => "GBP"},
          "paymentInstrument" => plain_card()
        }
      },
      overrides
    )
  end

  @spec plain_card() :: %{
          required(String.t()) => term()
        }
  def plain_card do
    %{
      "type" => "card/plain",
      "cardHolderName" => "Test User",
      "cardNumber" => "4444333322221111",
      "cardExpiryDate" => %{"month" => 5, "year" => 2035},
      "cvc" => "123"
    }
  end

  @spec authorized_response(map()) :: map()
  def authorized_response(overrides \\ %{}) do
    Map.merge(
      %{
        "paymentId" => "pay-#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}",
        "lastEvent" => "AUTHORISED",
        "instruction" => %{
          "value" => %{"amount" => 1999, "currency" => "GBP"},
          "paymentInstrument" => %{
            "type" => "card/plain",
            "href" => "https://try.access.worldpay.com/tokens/test-token"
          }
        },
        "_links" => %{
          "cardPayments:settle" => %{
            "href" => "https://try.access.worldpay.com/payments/settlements/full/test-id"
          },
          "cardPayments:cancel" => %{
            "href" =>
              "https://try.access.worldpay.com/payments/authorizations/cancellations/test-id"
          }
        }
      },
      overrides
    )
  end

  @spec fraudsight_response(String.t()) :: map()
  def fraudsight_response(outcome \\ "notHighRisk") do
    %{
      "outcome" => outcome,
      "_links" => %{
        "fraudsight:riskProfile" => %{
          "href" => "https://try.access.worldpay.com/fraudsight/assessments/test-id"
        }
      }
    }
  end

  @spec three_ds_auth_response(String.t()) :: map()
  def three_ds_auth_response(outcome \\ "authenticated") do
    %{
      "outcome" => outcome,
      "eci" => "05",
      "authenticationValue" => "AAABBBcccDDDeeeFFFgggHHH=",
      "transactionId" => "7c4dad86-5dbc-4e28-b060-4f3b0a5bd3c7",
      "version" => "2.1.0"
    }
  end
end
