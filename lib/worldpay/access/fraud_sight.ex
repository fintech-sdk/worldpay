defmodule Worldpay.FraudSight do
  @moduledoc """
  Worldpay **FraudSight API** — ML-based fraud risk assessment and SCA exemptions.

  Can be used standalone before a card payment, or embedded directly in
  Card Payments / Payments API orchestrated calls.

  ## Standalone usage

      {:ok, assessment} = Worldpay.FraudSight.assess(%{
        "transactionReference" => "order-123",
        "merchant" => %{"entity" => "default"},
        "instruction" => %{
          "value" => %{"amount" => 1999, "currency" => "GBP"},
          "paymentInstrument" => %{"type" => "card/plain", ...}
        },
        "customer" => %{
          "ipAddress" => "1.2.3.4",
          "email" => "user@example.com"
        }
      }, config)

      # assessment["outcome"] => "notHighRisk" | "highRisk"

  ## Attach to card payment

  Take the `riskProfile` href from the assessment response and include it
  in the Card Payments authorize instruction:

      risk_href = get_in(assessment, ["_links", "fraudsight:riskProfile", "href"])

      instruction = %{
        ...
        "instruction" => %{
          ...
          "riskProfile" => %{"href" => risk_href}
        }
      }

  ## SCA exemption (TRA)

  Include `"exemption" => %{"type" => "TRA"}` in the assessment body to
  request a Transaction Risk Assessment exemption at the same time.
  """

  alias Worldpay.{Client, Config, Error}

  @assessments_path "/fraudsight/assessments"

  @doc "Request a fraud risk assessment (and optionally an SCA exemption)."
  @spec assess(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def assess(body, %Config{} = config) do
    Client.post(
      @assessments_path,
      body,
      [api: :fraudsight, operation: :assess],
      config
    )
  end

  @doc """
  Update the fraud model with the actual payment outcome.

  Required when using a 3rd-party gateway alongside FraudSight.
  Worldpay uses this data to improve the ML model.

  ### Body fields

  - `"transactionAuthorized"` — boolean
  - `"fraudReported"` — boolean
  - `"fraudType"` — `"TC40"` | `"SAFE"` | `nil`
  """
  @spec update_outcome(String.t(), map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def update_outcome(assessment_id, body, %Config{} = config) do
    Client.post(
      "#{@assessments_path}/#{assessment_id}/outcomes",
      body,
      [api: :fraudsight, operation: :update_outcome],
      config
    )
  end

  @doc """
  Assess and return only the risk profile href for embedding in a payment.

  Returns `{:ok, href}` when outcome is `"notHighRisk"`,
  `{:error, :high_risk}` when outcome is `"highRisk"`.
  """
  @spec assess_and_extract_href(map(), Config.t()) ::
          {:ok, String.t()} | {:error, :high_risk | Error.t()}
  def assess_and_extract_href(body, %Config{} = config) do
    case assess(body, config) do
      {:ok, %{"outcome" => "notHighRisk"} = resp} ->
        href = get_in(resp, ["_links", "fraudsight:riskProfile", "href"])
        {:ok, href}

      {:ok, %{"outcome" => "highRisk"}} ->
        {:error, :high_risk}

      {:ok, _resp} ->
        {:error, :high_risk}

      {:error, _} = err ->
        err
    end
  end
end
