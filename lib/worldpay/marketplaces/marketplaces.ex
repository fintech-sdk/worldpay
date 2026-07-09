defmodule Worldpay.Marketplaces.Parties do
  @moduledoc """
  Worldpay **Parties API** — onboard and manage marketplace sellers.

  Supports both orchestrated (single-call) and modular (incremental) flows.

  ## Orchestrated onboarding

      {:ok, party} = Worldpay.Marketplaces.Parties.create(%{
        "merchant" => %{"entity" => "default"},
        "partyReference" => "seller-001",
        "type" => "person",
        "personalDetails" => %{
          "firstName" => "Jane",
          "lastName" => "Doe",
          "dateOfBirth" => "1985-06-15"
        },
        "email" => "jane@example.com",
        "payoutInstruments" => [%{
          "type" => "bankAccount",
          "accountHolderName" => "Jane Doe",
          "accountNumber" => "12345678",
          "sortCode" => "010203"
        }],
        "balanceAccounts" => [%{"currency" => "GBP"}]
      }, config)
  """

  alias Worldpay.{Client, Config, Error}

  @parties_path "/parties"

  @doc "Create a party (orchestrated or modular)."
  @spec create(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def create(body, %Config{} = config) do
    Client.post(@parties_path, body, [api: :parties, operation: :create], config)
  end

  @doc "Retrieve a party by ID."
  @spec get(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(party_id, %Config{} = config) do
    Client.get("#{@parties_path}/#{party_id}", [api: :parties, operation: :get], config)
  end

  @doc "Update a party."
  @spec update(String.t(), map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def update(party_id, body, %Config{} = config) do
    Client.put("#{@parties_path}/#{party_id}", body, [api: :parties, operation: :update], config)
  end

  @doc "Add a payout instrument (bank account or card) to a party."
  @spec add_payout_instrument(String.t(), map(), Config.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def add_payout_instrument(party_id, body, %Config{} = config) do
    Client.post(
      "#{@parties_path}/#{party_id}/payoutInstruments",
      body,
      [api: :parties, operation: :add_payout_instrument],
      config
    )
  end

  @doc "Create a balance account for a party."
  @spec add_balance_account(String.t(), map(), Config.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def add_balance_account(party_id, body, %Config{} = config) do
    Client.post(
      "#{@parties_path}/#{party_id}/balanceAccounts",
      body,
      [api: :parties, operation: :add_balance_account],
      config
    )
  end

  @doc "Add a beneficial owner to a party."
  @spec add_beneficial_owner(String.t(), map(), Config.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def add_beneficial_owner(party_id, body, %Config{} = config) do
    Client.post(
      "#{@parties_path}/#{party_id}/beneficialOwners",
      body,
      [api: :parties, operation: :add_beneficial_owner],
      config
    )
  end

  @doc "Retrieve a beneficial owner."
  @spec get_beneficial_owner(String.t(), String.t(), Config.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_beneficial_owner(party_id, owner_id, %Config{} = config) do
    Client.get(
      "#{@parties_path}/#{party_id}/beneficialOwners/#{owner_id}",
      [api: :parties, operation: :get_beneficial_owner],
      config
    )
  end

  @doc "Update a beneficial owner."
  @spec update_beneficial_owner(String.t(), String.t(), map(), Config.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def update_beneficial_owner(party_id, owner_id, body, %Config{} = config) do
    Client.put(
      "#{@parties_path}/#{party_id}/beneficialOwners/#{owner_id}",
      body,
      [api: :parties, operation: :update_beneficial_owner],
      config
    )
  end

  @doc "Delete a beneficial owner."
  @spec delete_beneficial_owner(String.t(), String.t(), Config.t()) ::
          {:ok, nil} | {:error, Error.t()}
  def delete_beneficial_owner(party_id, owner_id, %Config{} = config) do
    Client.delete(
      "#{@parties_path}/#{party_id}/beneficialOwners/#{owner_id}",
      [api: :parties, operation: :delete_beneficial_owner],
      config
    )
  end

  @doc "Trigger KYC identity verification for a party."
  @spec verify_identity(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def verify_identity(party_id, %Config{} = config) do
    Client.post(
      "#{@parties_path}/#{party_id}/identityVerifications",
      %{},
      [api: :parties, operation: :verify_identity],
      config
    )
  end
end

defmodule Worldpay.Marketplaces.SplitPayments do
  @moduledoc """
  Worldpay **Split Payments API** — allocate a payment across balance accounts.

  Requires a prior card payment authorization and settlement via
  `Worldpay.CardPayments`.

  ## Flow

  1. Authorize → `Worldpay.CardPayments.authorize/3`
  2. Settle → `Worldpay.CardPayments.settle/3`
  3. Split → `Worldpay.Marketplaces.SplitPayments.split/3`

  ## Example

      {:ok, _} = Worldpay.Marketplaces.SplitPayments.split(%{
        "merchant" => %{"entity" => "default"},
        "paymentId" => payment_id,
        "splits" => [
          %{"type" => "marketplace", "amount" => %{"value" => 8500, "currency" => "GBP"}, "partyId" => seller_id},
          %{"type" => "fee",         "amount" => %{"value" => 1500, "currency" => "GBP"}, "partyId" => platform_id}
        ]
      }, config)
  """

  alias Worldpay.{Client, Config, Error}

  @split_version "2025-06-25"

  @doc "Split a settled payment across balance accounts."
  @spec split(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def split(body, %Config{} = config, opts \\ []) do
    Client.post(
      "/splitPayments",
      body,
      [
        api: :split_payments,
        operation: :split,
        idempotency_key: key(opts),
        headers: [{"WP-Api-Version", @split_version}]
      ],
      config
    )
  end

  @doc "Split refund across balance accounts."
  @spec split_refund(String.t(), map(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def split_refund(split_payment_id, body, %Config{} = config, opts \\ []) do
    Client.post(
      "/splitPayments/#{split_payment_id}/refunds",
      body,
      [
        api: :split_payments,
        operation: :split_refund,
        idempotency_key: key(opts),
        headers: [{"WP-Api-Version", @split_version}]
      ],
      config
    )
  end

  @spec key(keyword()) :: String.t()
  defp key(opts), do: Keyword.get(opts, :idempotency_key, generate_key())

  @spec generate_key() :: String.t()
  defp generate_key, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
end
