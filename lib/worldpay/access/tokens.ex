defmodule Worldpay.Tokens do
  @moduledoc """
  Worldpay **Tokens API** — Worldpay tokens and Network tokens (NPTs).

  ## Worldpay tokens

      # Create
      {:ok, token} = Worldpay.Tokens.create(%{
        "paymentInstrument" => %{"type" => "card/front", "cardNumber" => "4444333322221111", ...},
        "merchant" => %{"entity" => "default"}
      }, config)

      token_href = get_in(token, ["tokenPaymentInstrument", "href"])

  ## Network tokens (NPTs — Visa / Mastercard)

      {:ok, npt} = Worldpay.Tokens.create_network_token(%{...}, config)

      # Provision cryptogram per CIT
      {:ok, cg} = Worldpay.Tokens.provision_cryptogram(npt_id, config)
  """

  alias Worldpay.{Client, Config, Error}

  @tokens_path "/tokens"
  @npt_path "/tokens/networkTokens"

  # ── Worldpay tokens ───────────────────────────────────────────────────────

  @doc "Create a Worldpay token."
  @spec create(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def create(body, %Config{} = config) do
    Client.post(@tokens_path, body, [api: :tokens, operation: :create], config)
  end

  @doc "Retrieve a Worldpay token by ID."
  @spec get(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(token_id, %Config{} = config) do
    Client.get("#{@tokens_path}/#{token_id}", [api: :tokens, operation: :get], config)
  end

  @doc "Update a Worldpay token."
  @spec update(String.t(), map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def update(token_id, body, %Config{} = config) do
    Client.put("#{@tokens_path}/#{token_id}", body, [api: :tokens, operation: :update], config)
  end

  @doc "Delete a Worldpay token."
  @spec delete(String.t(), Config.t()) :: {:ok, nil} | {:error, Error.t()}
  def delete(token_id, %Config{} = config) do
    Client.delete("#{@tokens_path}/#{token_id}", [api: :tokens, operation: :delete], config)
  end

  @doc """
  Detokenize — retrieve the raw card number from a token.

  **Warning:** Only available to PCI-accredited merchants. Increases PCI scope.
  """
  @spec detokenize(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def detokenize(token_id, %Config{} = config) do
    Client.post(
      "#{@tokens_path}/detokenize",
      %{"tokenId" => token_id},
      [api: :tokens, operation: :detokenize],
      config
    )
  end

  # ── Network tokens (NPTs) ─────────────────────────────────────────────────

  @doc "Provision a Visa or Mastercard network token (NPT)."
  @spec create_network_token(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def create_network_token(body, %Config{} = config) do
    Client.post(@npt_path, body, [api: :tokens, operation: :create_network_token], config)
  end

  @doc "Query a network token by ID."
  @spec get_network_token(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_network_token(npt_id, %Config{} = config) do
    Client.get(
      "#{@npt_path}/#{npt_id}",
      [api: :tokens, operation: :get_network_token],
      config
    )
  end

  @doc "Delete a network token."
  @spec delete_network_token(String.t(), Config.t()) :: {:ok, nil} | {:error, Error.t()}
  def delete_network_token(npt_id, %Config{} = config) do
    Client.delete(
      "#{@npt_path}/#{npt_id}",
      [api: :tokens, operation: :delete_network_token],
      config
    )
  end

  @doc """
  Provision a cryptogram for a network token.

  Required for every Customer Initiated Transaction using a network token,
  unless Worldpay auto-provisions it (Payments API orchestrated flow only).
  """
  @spec provision_cryptogram(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def provision_cryptogram(npt_id, %Config{} = config) do
    Client.post(
      "#{@npt_path}/#{npt_id}/cryptograms",
      %{},
      [api: :tokens, operation: :provision_cryptogram],
      config
    )
  end
end
