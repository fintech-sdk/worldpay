defmodule Worldpay.Exemptions do
  @moduledoc """
  Worldpay **Exemptions API** — standalone SCA exemption requests.

  Exemption types:

  - `"TRA"` — Transaction Risk Assessment
  - `"lowValue"` — Low-value payment (under applicable threshold)
  - `"trustedBeneficiary"` — Trusted beneficiary
  - `"authenticationOutage"` — Issuer authentication outage

  For SCA exemptions embedded inside a FraudSight assessment, use
  `Worldpay.FraudSight.assess/2` with the `"exemption"` field.

  ## Example

      {:ok, result} = Worldpay.Exemptions.request(%{
        "transactionReference" => "order-123",
        "merchant" => %{"entity" => "default"},
        "instruction" => %{
          "value" => %{"amount" => 500, "currency" => "EUR"},
          "paymentInstrument" => %{"type" => "card/plain", ...}
        },
        "exemption" => %{"type" => "TRA"}
      }, config)
  """

  alias Worldpay.{Client, Config, Error}

  @doc "Request an SCA exemption."
  @spec request(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def request(body, %Config{} = config) do
    Client.post(
      "/exemptions",
      body,
      [api: :exemptions, operation: :request],
      config
    )
  end
end
