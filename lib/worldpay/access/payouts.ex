defmodule Worldpay.CardPayouts do
  @moduledoc """
  Worldpay **Card Payouts API** — push funds to Visa / Mastercard cards.

  Supports basic disbursements and Fast Access (≤30 min delivery).
  """

  alias Worldpay.{Client, Config, Error}

  @doc "Basic card disbursement."
  @spec disburse(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def disburse(body, %Config{} = config, opts \\ []) do
    Client.post(
      "/cardPayouts",
      body,
      [api: :card_payouts, operation: :disburse, idempotency_key: key(opts)],
      config
    )
  end

  @doc """
  Fast Access payout — funds arrive on eligible cards within 30 minutes.

  Pass `fallback_to_basic: true` to automatically fall back to basic
  disbursement when Fast Access is unavailable.
  """
  @spec fast_access(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def fast_access(body, %Config{} = config, opts \\ []) do
    body =
      case Keyword.get(opts, :fallback_to_basic, false) do
        true -> Map.put(body, "fallbackToBasic", true)
        false -> body
      end

    Client.post(
      "/cardPayouts/fastAccess",
      body,
      [api: :card_payouts, operation: :fast_access, idempotency_key: key(opts)],
      config
    )
  end

  @doc """
  Search card payouts. Maximum 31-day date range.

  ## Query options

  - `:start_date` — ISO 8601 date
  - `:end_date` — ISO 8601 date
  - `:transaction_reference`
  """
  @spec search(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def search(params \\ [], %Config{} = config) do
    query =
      []
      |> add_if_present(:startDate, Keyword.get(params, :start_date))
      |> add_if_present(:endDate, Keyword.get(params, :end_date))
      |> add_if_present(:transactionReference, Keyword.get(params, :transaction_reference))

    Client.get("/cardPayouts", [api: :card_payouts, operation: :search, query: query], config)
  end

  @spec key(keyword()) :: String.t()
  defp key(opts), do: Keyword.get(opts, :idempotency_key, generate_key())

  @spec generate_key() :: String.t()
  defp generate_key, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  @spec add_if_present([{atom(), term()}], :startDate | :endDate | :transactionReference, term()) ::
          [{atom(), term()}]
  defp add_if_present(list, _k, nil), do: list
  defp add_if_present(list, k, v), do: Keyword.put(list, k, v)
end

defmodule Worldpay.AccountPayouts do
  @moduledoc """
  Worldpay **Account Payouts API** — push funds to bank accounts.
  """

  alias Worldpay.{Client, Config, Error}

  @doc "Create an account payout."
  @spec pay(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def pay(body, %Config{} = config, opts \\ []) do
    Client.post(
      "/payouts/accounts",
      body,
      [api: :account_payouts, operation: :pay, idempotency_key: key(opts)],
      config
    )
  end

  @doc "Search account payouts."
  @spec search(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def search(params \\ [], %Config{} = config) do
    query =
      []
      |> add_if_present(:startDate, Keyword.get(params, :start_date))
      |> add_if_present(:endDate, Keyword.get(params, :end_date))
      |> add_if_present(:transactionReference, Keyword.get(params, :transaction_reference))

    Client.get(
      "/payouts/accounts",
      [api: :account_payouts, operation: :search, query: query],
      config
    )
  end

  @spec key(keyword()) :: String.t()
  defp key(opts), do: Keyword.get(opts, :idempotency_key, generate_key())

  @spec generate_key() :: String.t()
  defp generate_key, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  @spec add_if_present(keyword(), :startDate | :endDate | :transactionReference, term()) ::
          keyword()
  defp add_if_present(list, _k, nil), do: list
  defp add_if_present(list, k, v), do: Keyword.put(list, k, v)
end

defmodule Worldpay.MoneyTransfers do
  @moduledoc """
  Worldpay **Money Transfers API** — Original Credit Transactions (OCTs).

  Push funds to an eligible card in ≤30 minutes.
  Use cases: digital wallet unload, gaming payouts, goodwill disbursements.
  Requires Visa/MC OCT registration (contact Worldpay IM).
  """

  alias Worldpay.{Client, Config, Error}

  @vendor_type "application/vnd.worldpay.money-transfers-v1+json"

  @doc "Create an OCT money transfer."
  @spec transfer(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def transfer(body, %Config{} = config, opts \\ []) do
    Client.post(
      "/moneyTransfers",
      body,
      [
        api: :money_transfers,
        operation: :transfer,
        idempotency_key: Keyword.get(opts, :idempotency_key, generate_key()),
        headers: [{"Accept", @vendor_type}]
      ],
      config
    )
  end

  @spec generate_key() :: String.t()
  defp generate_key, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
end

defmodule Worldpay.FX do
  @moduledoc """
  Worldpay **FX API** — Multi-Currency Processing.

  Supports rate pairings, FX quotes, and forward rate locking.
  """

  alias Worldpay.{Client, Config, Error}

  @doc "Get an FX rate pairing."
  @spec get_rate(String.t(), String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_rate(source_currency, target_currency, %Config{} = config) do
    query = [sourceCurrency: source_currency, targetCurrency: target_currency]

    Client.get("/fx/rates", [api: :fx, operation: :get_rate, query: query], config)
  end

  @doc """
  Create an FX quote.

  Set `intent: "PAYOUT LIVE RATE"` for a real-time rate on live transactions.
  """
  @spec create_quote(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def create_quote(body, %Config{} = config) do
    Client.post("/fx/quotes", body, [api: :fx, operation: :create_quote], config)
  end

  @doc "Retrieve a previously created FX quote."
  @spec get_quote(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_quote(quote_id, %Config{} = config) do
    Client.get("/fx/quotes/#{quote_id}", [api: :fx, operation: :get_quote], config)
  end
end

defmodule Worldpay.AccountTransfers do
  @moduledoc "Internal fund transfers between virtual balance accounts."

  alias Worldpay.{Client, Config, Error}

  @doc "Transfer funds from one account to another."
  @spec transfer(map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def transfer(body, %Config{} = config) do
    Client.post("/transfers", body, [api: :account_transfers, operation: :transfer], config)
  end
end

defmodule Worldpay.Balances do
  @moduledoc "Query virtual account balances."

  alias Worldpay.{Client, Config, Error}

  @doc "Get the current balance for an account."
  @spec get(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(account_id, %Config{} = config) do
    Client.get("/balances/#{account_id}", [api: :balances, operation: :get], config)
  end
end

defmodule Worldpay.Statements do
  @moduledoc "Retrieve settlement statements (deposit summaries)."

  alias Worldpay.{Client, Config, Error}

  @doc "List statements, optionally filtered by date range or account."
  @spec list(keyword(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(params \\ [], %Config{} = config) do
    query =
      []
      |> add_if_present(:startDate, Keyword.get(params, :start_date))
      |> add_if_present(:endDate, Keyword.get(params, :end_date))
      |> add_if_present(:accountId, Keyword.get(params, :account_id))

    Client.get("/statements", [api: :statements, operation: :list, query: query], config)
  end

  @spec add_if_present(keyword(), :startDate | :endDate | :accountId, term()) :: keyword()
  defp add_if_present(list, _k, nil), do: list
  defp add_if_present(list, k, v), do: Keyword.put(list, k, v)
end
