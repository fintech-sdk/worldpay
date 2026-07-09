defmodule Worldpay.ThreeDS do
  @moduledoc """
  Worldpay **3DS API** — Strong Customer Authentication.

  Handles the full 3DS authentication flow:

  1. Device data collection
  2. Authentication request (sends order + device data to card schemes)
  3. Challenge display (if outcome is `"challenged"`)
  4. Apply `eci` + `authenticationValue` to the card payment

  ## Web flow

      # Step 1 — device data collection
      {:ok, ddc} = Worldpay.ThreeDS.device_data(session_href, config)
      # → render ddc["_links"]["3ds:deviceDataCollection"]["href"] in an iFrame

      # Step 2 — authenticate
      {:ok, auth} = Worldpay.ThreeDS.authenticate(auth_body, config)

      # auth["outcome"] is "authenticated" | "challenged" | "unAuthenticated" | "authenticationOutage"

      # Step 3 (if challenged) — render iFrame from auth["_links"]["3ds:challenge"]["href"]
      # Customer completes challenge, then re-poll or receive webhook

      # Step 4 — attach result to payment
      three_ds = Worldpay.ThreeDS.build_auth_object(auth)

      {:ok, payment} =
        Worldpay.CardPayments.authorize(
          Map.put(instruction, "threeDS", three_ds),
          config
        )

  ## Outcomes

  | Outcome | Action |
  |---|---|
  | `"authenticated"` | Apply `eci` + `authenticationValue` to payment |
  | `"challenged"` | Render challenge iFrame; await completion |
  | `"unAuthenticated"` | Do not proceed; SCA failed |
  | `"authenticationOutage"` | Issuer outage; exemption may auto-apply |
  """

  alias Worldpay.{Client, Config, Error}

  @doc "Initiate device data collection (step 1 of web 3DS flow)."
  @spec device_data(String.t(), map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def device_data(session_href, device_info \\ %{}, %Config{} = config) do
    body = Map.merge(%{"sessionHref" => session_href}, device_info)

    Client.post(
      "/verifications/customers/3ds/deviceData",
      body,
      [api: :three_ds, operation: :device_data],
      config
    )
  end

  @doc """
  Authenticate the customer (step 2).

  ### Required body fields

  - `sessionHref` — from Checkout SDK
  - `deviceData` — from device data collection response
  - `merchant.entity`
  - `instruction.value`
  - `instruction.paymentInstrument`

  ### Optional fields

  - `challengePreference` — `"noChallengeRequested"` | `"challengeRequested"` | `"challengeMandated"` | `"noChallengeRequestedTRAPerformed"`
  - `customerData` — South Korea / Toss Pay domestic payments
  - `bypassOn` / `continueOn` — 3DS bypass controls (Jun 2026)
  """
  @spec authenticate(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def authenticate(body, %Config{} = config) do
    Client.post(
      "/verifications/customers/3ds/authentication",
      body,
      [api: :three_ds, operation: :authenticate],
      config
    )
  end

  @doc """
  Authenticate and extract the fields needed for a card payment.

  Returns `{:ok, %{eci: ..., authentication_value: ..., transaction_id: ..., version: ...}}`
  on success, `{:error, Error.t()}` on challenge required or failure.
  """
  @type auth_result :: %{
          eci: String.t() | nil,
          authentication_value: String.t() | nil,
          transaction_id: String.t() | nil,
          version: String.t() | nil
        }

  @spec authenticate_and_extract(%{String.t() => term()}, Config.t()) ::
          {:ok, auth_result()} | {:error, Error.t()}

  def authenticate_and_extract(body, %Config{} = config) do
    case authenticate(body, config) do
      {:ok, resp} -> handle_auth_outcome(resp)
      {:error, _} = err -> err
    end
  end

  @spec handle_auth_outcome(%{String.t() => term()}) ::
          {:ok, auth_result()} | {:error, Error.t()}
  defp handle_auth_outcome(%{"outcome" => "authenticated"} = resp) do
    {:ok,
     %{
       eci: resp["eci"],
       authentication_value: resp["authenticationValue"],
       transaction_id: resp["transactionId"],
       version: resp["version"]
     }}
  end

  defp handle_auth_outcome(%{"outcome" => "challenged"} = resp) do
    {:error,
     %Error{
       type: :api_error,
       reason: :challenge_required,
       message: "3DS challenge required",
       raw: resp
     }}
  end

  defp handle_auth_outcome(%{"outcome" => outcome} = resp) do
    {:error,
     %Error{
       type: :api_error,
       reason: safe_to_atom(outcome),
       message: "3DS outcome: #{outcome}",
       raw: resp
     }}
  end

  @doc """
  Build the `threeDS` object to embed in a Card Payments authorize request
  from a successful authentication response map.
  """
  @spec build_auth_object(%{String.t() => term()}) :: %{String.t() => String.t()}
  def build_auth_object(%{"eci" => _eci} = resp) do
    %{"type" => "integrated"}
    |> put_if_present("eci", resp["eci"])
    |> put_if_present("authenticationValue", resp["authenticationValue"])
    |> put_if_present("transactionId", resp["transactionId"])
    |> put_if_present("version", resp["version"])
  end

  @spec build_auth_object(map()) :: map()
  def build_auth_object(resp) when is_map(resp) do
    %{"type" => "integrated"}
    |> put_if_present("eci", resp["eci"])
    |> put_if_present("authenticationValue", resp["authenticationValue"])
    |> put_if_present("transactionId", resp["transactionId"])
    |> put_if_present("version", resp["version"])
  end

  @spec put_if_present(%{String.t() => String.t()}, String.t(), String.t() | nil) :: %{
          String.t() => String.t()
        }
  defp put_if_present(map, _k, nil), do: map
  defp put_if_present(map, k, v), do: Map.put(map, k, v)

  @spec safe_to_atom(String.t()) :: atom()
  defp safe_to_atom(str) do
    sanitized =
      str
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_]/, "_")

    # Bounded input from Worldpay API constants only.
    try do
      String.to_existing_atom(sanitized)
    rescue
      ArgumentError -> :erlang.binary_to_existing_atom(sanitized, :utf8)
    end
  end
end
