defmodule Worldpay.Reporting.EMAF do
  @moduledoc """
  Worldpay **Enhanced Merchant Activity File (eMAF)** parser.

  eMAF is Worldpay's daily settlement reconciliation file (v1.43, Apr 2026).
  Delivered via SFTP. Covers Credit, Debit POS, EBT (SNAP/WIC), Gift Card,
  POS Check Services, and WIC.

  ## Record types (Credit)

  | Record | Description |
  |---|---|
  | 1 | Credit Reconciliation Detail Transaction |
  | 2 | Credit Reconciliation Detail Transaction (additional fields) |
  | 3 | DCC / MCP Information |
  | 4 | Risk Holds and Releases |
  | 5 | Reward Data (Summary Level) |
  | 7 | Customer Discretionary Data |

  ## Usage

      {:ok, records} = Worldpay.Reporting.EMAF.parse_file("/path/to/emaf.dat")
      {:ok, records} = Worldpay.Reporting.EMAF.parse_string(file_contents)

      # Group by record type
      by_type = Worldpay.Reporting.EMAF.group_by_type(records)

      # Extract credit detail records
      credit_records = Worldpay.Reporting.EMAF.credit_records(records)

      # Find transactions with PAR
      par_records = Worldpay.Reporting.EMAF.with_par(records)

      # Find digital wallet transactions
      wallet_records = Worldpay.Reporting.EMAF.wallet_transactions(records)

  ## Key fields added in recent releases

  - Transaction Integrity Classification (TIC) Indicator
  - Payment Account Reference (PAR)
  - Convenience Fee Amount
  - Digital Wallet fields (Auth Detail + Reconciliation Detail)
  - Pin Conversion Flag (Debit POS Record 2)
  - FraudSight records for WIC and EBT transactions
  """

  @record_delimiter "\n"
  @field_delimiter "|"

  @type record_type ::
          :credit_detail
          | :credit_detail_2
          | :dcc_mcp
          | :risk_hold
          | :reward_summary
          | :customer_discretionary
          | :debit_detail
          | :debit_detail_2
          | :ebt_detail
          | :gift_detail
          | :wic_detail
          | :check_detail
          | :header
          | :trailer
          | :unknown

  @type record :: %{
          record_type: record_type(),
          record_number: String.t(),
          fields: [String.t()],
          raw: String.t()
        }

  @doc "Parse an eMAF file from disk."
  @spec parse_file(String.t()) :: {:ok, [record()]} | {:error, term()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, contents} -> parse_string(contents)
      {:error, reason} -> {:error, {:file_read_error, reason}}
    end
  end

  @doc "Parse an eMAF file from a string."
  @spec parse_string(String.t()) :: {:ok, [record()]}
  def parse_string(contents) when is_binary(contents) do
    records =
      contents
      |> String.split(@record_delimiter, trim: true)
      |> Enum.map(&parse_record/1)

    {:ok, records}
  end

  @doc "Group records by type."
  @spec group_by_type([record()]) :: %{record_type() => [record()]}
  def group_by_type(records) do
    Enum.group_by(records, & &1.record_type)
  end

  @doc "Filter for credit detail records (Record 1)."
  @spec credit_records([record()]) :: [record()]
  def credit_records(records) do
    Enum.filter(records, &(&1.record_type == :credit_detail))
  end

  @doc "Filter for debit POS detail records."
  @spec debit_records([record()]) :: [record()]
  def debit_records(records) do
    Enum.filter(records, &(&1.record_type == :debit_detail))
  end

  @doc "Filter for EBT records."
  @spec ebt_records([record()]) :: [record()]
  def ebt_records(records) do
    Enum.filter(records, &(&1.record_type == :ebt_detail))
  end

  @doc "Filter for Gift Card records."
  @spec gift_records([record()]) :: [record()]
  def gift_records(records) do
    Enum.filter(records, &(&1.record_type == :gift_detail))
  end

  @doc "Filter for WIC records."
  @spec wic_records([record()]) :: [record()]
  def wic_records(records) do
    Enum.filter(records, &(&1.record_type == :wic_detail))
  end

  @doc "Filter for DCC/MCP information records (Record 3)."
  @spec dcc_mcp_records([record()]) :: [record()]
  def dcc_mcp_records(records) do
    Enum.filter(records, &(&1.record_type == :dcc_mcp))
  end

  @doc "Filter for Risk Hold and Release records (Record 4)."
  @spec risk_hold_records([record()]) :: [record()]
  def risk_hold_records(records) do
    Enum.filter(records, &(&1.record_type == :risk_hold))
  end

  @doc "Filter records that have a Payment Account Reference (PAR)."
  @spec with_par([record()]) :: [record()]
  def with_par(records) do
    Enum.filter(records, fn r ->
      par = get_field(r, :payment_account_reference)
      not is_nil(par) and par != ""
    end)
  end

  @doc "Filter digital wallet transactions."
  @spec wallet_transactions([record()]) :: [record()]
  def wallet_transactions(records) do
    Enum.filter(records, fn r ->
      wallet = get_field(r, :digital_wallet_indicator)
      not is_nil(wallet) and wallet != "" and wallet != "0"
    end)
  end

  @doc "Filter transactions with FraudSight data."
  @spec fraudsight_records([record()]) :: [record()]
  def fraudsight_records(records) do
    Enum.filter(records, fn r ->
      score = get_field(r, :fraudsight_score)
      not is_nil(score) and score != ""
    end)
  end

  @doc "Extract a named field from a parsed record."
  @spec get_field(record(), atom()) :: String.t() | nil
  def get_field(%{fields: fields, record_type: type}, field_name) do
    case field_index(type, field_name) do
      nil -> nil
      idx -> Enum.at(fields, idx)
    end
  end

  @doc "Sum transaction amounts for a list of records."
  @spec sum_amounts([record()]) :: integer()
  def sum_amounts(records) do
    Enum.reduce(records, 0, &add_amount/2)
  end

  @spec add_amount(record(), integer()) :: integer()
  defp add_amount(record, acc) do
    case get_field(record, :transaction_amount) do
      nil -> acc
      amount_str -> acc + parse_amount_or_zero(amount_str)
    end
  end

  @spec parse_amount_or_zero(String.t()) :: integer()
  defp parse_amount_or_zero(amount_str) do
    case Integer.parse(amount_str) do
      {amount, _} -> amount
      :error -> 0
    end
  end

  @doc "Generate a reconciliation summary from eMAF records."
  @spec reconciliation_summary([record()]) :: %{
          total_records: non_neg_integer(),
          credit_count: non_neg_integer(),
          debit_count: non_neg_integer(),
          ebt_count: non_neg_integer(),
          gift_count: non_neg_integer(),
          wic_count: non_neg_integer(),
          dcc_count: non_neg_integer(),
          risk_hold_count: non_neg_integer(),
          credit_total: integer(),
          debit_total: integer(),
          wallet_transactions: non_neg_integer(),
          par_transactions: non_neg_integer()
        }
  def reconciliation_summary(records) do
    by_type = group_by_type(records)

    %{
      total_records: length(records),
      credit_count: length(Map.get(by_type, :credit_detail, [])),
      debit_count: length(Map.get(by_type, :debit_detail, [])),
      ebt_count: length(Map.get(by_type, :ebt_detail, [])),
      gift_count: length(Map.get(by_type, :gift_detail, [])),
      wic_count: length(Map.get(by_type, :wic_detail, [])),
      dcc_count: length(Map.get(by_type, :dcc_mcp, [])),
      risk_hold_count: length(Map.get(by_type, :risk_hold, [])),
      credit_total: sum_amounts(Map.get(by_type, :credit_detail, [])),
      debit_total: sum_amounts(Map.get(by_type, :debit_detail, [])),
      wallet_transactions: length(wallet_transactions(records)),
      par_transactions: length(with_par(records))
    }
  end

  # ── private ───────────────────────────────────────────────────────────────

  defp parse_record(line) do
    fields = String.split(line, @field_delimiter)
    record_number = List.first(fields, "")
    record_type = classify_record(record_number)

    %{
      record_type: record_type,
      record_number: record_number,
      fields: fields,
      raw: line
    }
  end

  defp classify_record("01"), do: :credit_detail
  defp classify_record("02"), do: :credit_detail_2
  defp classify_record("03"), do: :dcc_mcp
  defp classify_record("04"), do: :risk_hold
  defp classify_record("05"), do: :reward_summary
  defp classify_record("07"), do: :customer_discretionary
  defp classify_record("10"), do: :debit_detail
  defp classify_record("11"), do: :debit_detail_2
  defp classify_record("20"), do: :ebt_detail
  defp classify_record("30"), do: :gift_detail
  defp classify_record("40"), do: :wic_detail
  defp classify_record("50"), do: :check_detail
  defp classify_record("H"), do: :header
  defp classify_record("T"), do: :trailer
  defp classify_record(_), do: :unknown

  # Field index maps for each record type
  # Indices are 0-based (including the record_number at index 0)
  defp field_index(:credit_detail, :transaction_amount), do: 5
  defp field_index(:credit_detail, :card_number_last4), do: 8
  defp field_index(:credit_detail, :card_type), do: 9
  defp field_index(:credit_detail, :transaction_date), do: 3
  defp field_index(:credit_detail, :authorization_code), do: 11
  defp field_index(:credit_detail, :merchant_id), do: 2
  defp field_index(:credit_detail, :transaction_type), do: 4
  defp field_index(:credit_detail, :payment_account_reference), do: 42
  defp field_index(:credit_detail, :digital_wallet_indicator), do: 43
  defp field_index(:credit_detail, :tic_indicator), do: 44
  defp field_index(:credit_detail, :convenience_fee_amount), do: 45
  defp field_index(:credit_detail, :fraudsight_score), do: nil

  defp field_index(:credit_detail_2, :payment_account_reference), do: 15
  defp field_index(:credit_detail_2, :digital_wallet_indicator), do: 16
  defp field_index(:credit_detail_2, :tic_indicator), do: 17
  defp field_index(:credit_detail_2, :transaction_amount), do: 3

  defp field_index(:debit_detail, :transaction_amount), do: 5
  defp field_index(:debit_detail, :card_number_last4), do: 8
  defp field_index(:debit_detail, :transaction_date), do: 3
  defp field_index(:debit_detail, :pin_conversion_flag), do: nil
  defp field_index(:debit_detail, :digital_wallet_indicator), do: 30
  defp field_index(:debit_detail, :payment_account_reference), do: 31

  defp field_index(:debit_detail_2, :pin_conversion_flag), do: 5
  defp field_index(:debit_detail_2, :transaction_amount), do: 3

  defp field_index(:ebt_detail, :transaction_amount), do: 5
  defp field_index(:ebt_detail, :card_number_last4), do: 8
  defp field_index(:ebt_detail, :ebt_type), do: 10
  defp field_index(:ebt_detail, :fraudsight_score), do: 25

  defp field_index(:gift_detail, :transaction_amount), do: 5
  defp field_index(:gift_detail, :card_number_last4), do: 8
  defp field_index(:gift_detail, :available_balance), do: 15

  defp field_index(:wic_detail, :transaction_amount), do: 5
  defp field_index(:wic_detail, :fraudsight_score), do: 20

  defp field_index(:dcc_mcp, :original_currency), do: 3
  defp field_index(:dcc_mcp, :original_amount), do: 4
  defp field_index(:dcc_mcp, :exchange_rate), do: 5
  defp field_index(:dcc_mcp, :dcc_status), do: 6

  defp field_index(:risk_hold, :hold_amount), do: 3
  defp field_index(:risk_hold, :hold_reason), do: 4
  defp field_index(:risk_hold, :release_date), do: 5

  defp field_index(_, _), do: nil
end

defmodule Worldpay.Reporting.BatchTransactions do
  @moduledoc """
  Worldpay **Batch Transaction API** (Access).

  Submit batch details and retrieve authorized batch summaries.
  Used alongside `Worldpay.Statements` for full settlement reconciliation.

  This is distinct from cnpAPI batch files (which use SFTP) — this API
  accepts batch metadata via REST and returns settlement summaries.
  """

  alias Worldpay.{Client, Config}

  @doc "Submit a batch for processing."
  @spec submit(map(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def submit(body, %Config{} = config) do
    Client.post(
      "/batches",
      body,
      [api: :batch_transactions, operation: :submit],
      config
    )
  end

  @doc "Retrieve batch details by batch ID."
  @spec get(String.t(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def get(batch_id, %Config{} = config) do
    Client.get(
      "/batches/#{batch_id}",
      [api: :batch_transactions, operation: :get],
      config
    )
  end

  @doc "List all batches, optionally filtered by date range."
  @spec list(keyword(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def list(params \\ [], %Config{} = config) do
    query =
      []
      |> maybe_add(:startDate, Keyword.get(params, :start_date))
      |> maybe_add(:endDate, Keyword.get(params, :end_date))
      |> maybe_add(:merchantId, Keyword.get(params, :merchant_id))

    Client.get(
      "/batches",
      [api: :batch_transactions, operation: :list, query: query],
      config
    )
  end

  defp maybe_add(list, _k, nil), do: list
  defp maybe_add(list, k, v), do: Keyword.put(list, k, v)
end

defmodule Worldpay.Reporting.CNPBatch do
  @moduledoc """
  Helpers for **cnpAPI batch file** processing.

  cnpAPI batch files are submitted via SFTP and contain XML transaction
  records. Results are returned as completion files (~5 business days
  for Account Updater; same-day for Dynamic Payout).

  ## File types

  - **Transaction batch** — auth, sale, credit, void, etc. in bulk
  - **Account Updater completion file** — results of card update requests
  - **Dynamic Payout funding report** — sub-merchant disbursement results

  ## Usage

      # Build a batch session file
      session_xml = Worldpay.Reporting.CNPBatch.build_session([
        Worldpay.CNP.Builder.sale(id: "txn-001", order_id: "order-001", amount: 1999, card: card),
        Worldpay.CNP.Builder.sale(id: "txn-002", order_id: "order-002", amount: 2999, card: card)
      ],
        merchant_id: "MERCH-001",
        user: "user",
        password: "pass",
        batch_id: "batch-001",
        num_batch_requests: 2
      )

      # Write to SFTP for transmission to Worldpay
      File.write!("/path/to/batch_#{Date.utc_today()}.xml", session_xml)
  """

  @schema_version "12.0"
  @xmlns "http://www.vantiv.cnp.com/schema"

  @doc """
  Build a complete cnpAPI session file from a list of transaction XML elements.

  ## Limits

  - Max 20,000 changes per batch
  - Max 9,999 batches per session file
  - Max 1,000,000 changes per session file

  ## Options

  - `:merchant_id` — merchant ID (required)
  - `:user` — cnpAPI username (required)
  - `:password` — cnpAPI password (required)
  - `:batch_id` — unique batch identifier (required)
  - `:report_group` — report group name
  - `:num_batch_requests` — number of transactions in this batch
  """
  @spec build_session([String.t()], keyword()) :: String.t()
  def build_session(transactions, opts) when length(transactions) <= 1_000_000 do
    merchant_id = Keyword.fetch!(opts, :merchant_id)
    user = Keyword.fetch!(opts, :user)
    password = Keyword.fetch!(opts, :password)
    batch_id = Keyword.fetch!(opts, :batch_id)
    report_group = Keyword.get(opts, :report_group, "Default")
    request_id = Keyword.get(opts, :request_id, generate_id())
    num_transactions = length(transactions)

    transactions_xml = Enum.join(transactions, "\n")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <cnpRequest version="#{@schema_version}" xmlns="#{@xmlns}"
        merchantId="#{merchant_id}" id="#{request_id}"
        numBatchRequests="1">
      <authentication>
        <user>#{user}</user>
        <password>#{password}</password>
      </authentication>
      <batchRequest id="#{batch_id}"
          numAuths="0"
          numSales="#{num_transactions}"
          numCredits="0"
          numVoids="0"
          numCaptures="0"
          numTokenRegistrations="0"
          numAccountUpdates="0"
          numPayFacCredits="0"
          numSubmerchantCredits="0"
          numPayFacDebits="0"
          numSubmerchantDebits="0"
          merchantId="#{merchant_id}"
          reportGroup="#{report_group}">
        #{transactions_xml}
      </batchRequest>
    </cnpRequest>
    """
  end

  @doc """
  Parse a cnpAPI Account Updater completion file.

  Returns a list of update result maps, each with:
  - `order_id` — original order ID
  - `cnp_txn_id` — transaction ID
  - `response` — response code ("000" = success)
  - `updated_card` / `updated_token` — new card/token details (if updated)
  - `reason_code` — network reason code
  """
  @spec parse_account_updater_response(String.t()) :: {:ok, [map()]} | {:error, term()}
  def parse_account_updater_response(xml) when is_binary(xml) do
    # :xmerl_scan.string/2 always returns a 2-tuple on success (it
    # raises on malformed XML, handled by the rescue clause below),
    # so there is no error tuple to match here.
    {doc, _rest} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
    results = extract_update_results(doc)
    {:ok, results}
  rescue
    ex -> {:error, {:xml_parse_error, ex}}
  end

  @doc """
  Parse a Dynamic Payout funding report.

  Returns a list of funding result maps, each with:
  - `sub_merchant_id` — sub-merchant identifier
  - `funding_amount` — amount disbursed
  - `status` — "approved" | "declined" | "pending"
  - `routing_number` — bank routing number
  - `account_number` — (masked) bank account number
  - `funding_transaction_type` — "credit" | "debit"
  - `estimated_settlement_date` — ISO 8601 date string
  """
  @spec parse_funding_report(String.t()) :: {:ok, [map()]} | {:error, term()}
  def parse_funding_report(xml) when is_binary(xml) do
    # :xmerl_scan.string/2 always returns a 2-tuple on success (it
    # raises on malformed XML, handled by the rescue clause below),
    # so there is no error tuple to match here.
    {doc, _rest} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
    results = extract_funding_results(doc)
    {:ok, results}
  rescue
    ex -> {:error, {:xml_parse_error, ex}}
  end

  @doc "Generate a SFTP-ready filename for a cnpAPI batch file."
  @spec batch_filename(String.t(), String.t()) :: String.t()
  def batch_filename(merchant_id, batch_id) do
    date = Date.utc_today() |> Date.to_string() |> String.replace("-", "")
    "#{merchant_id}_#{batch_id}_#{date}.xml"
  end

  # ── private ───────────────────────────────────────────────────────────────

  defp extract_update_results({:xmlElement, _, _, _, _, _, _, _, children, _, _, _}) do
    children
    |> Enum.filter(
      &match?({:xmlElement, :accountUpdateResponse, _, _, _, _, _, _, _, _, _, _}, &1)
    )
    |> Enum.map(&parse_update_response/1)
  end

  defp extract_update_results(_), do: []

  defp parse_update_response(
         {:xmlElement, :accountUpdateResponse, _, _, _, _, _, attrs, children, _, _, _}
       ) do
    attr_map =
      Map.new(attrs, fn {:xmlAttribute, k, _, _, _, _, _, _, v, _} ->
        {to_string(k), to_string(v)}
      end)

    child_map =
      children
      |> Enum.filter(&match?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, &1))
      |> Enum.reduce(%{}, fn {:xmlElement, name, _, _, _, _, _, _, ch, _, _, _}, acc ->
        text =
          Enum.map_join(ch, "", fn
            {:xmlText, _, _, _, v, _} -> to_string(v)
            _ -> ""
          end)

        Map.put(acc, to_string(name), text)
      end)

    merged = Map.merge(attr_map, child_map)

    merged
    |> Map.take([
      "orderId",
      "cnpTxnId",
      "response",
      "message",
      "originalCard",
      "updatedCard",
      "originalToken",
      "updatedToken"
    ])
  end

  defp parse_update_response(_), do: %{}

  defp extract_funding_results({:xmlElement, _, _, _, _, _, _, _, children, _, _, _}) do
    children
    |> Enum.filter(
      &match?({:xmlElement, :fundingSubmerchantResponse, _, _, _, _, _, _, _, _, _, _}, &1)
    )
    |> Enum.map(&parse_funding_response/1)
  end

  defp extract_funding_results(_), do: []

  defp parse_funding_response({:xmlElement, _, _, _, _, _, _, _, children, _, _, _}) do
    children
    |> Enum.filter(&match?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, &1))
    |> Enum.reduce(%{}, fn {:xmlElement, name, _, _, _, _, _, _, ch, _, _, _}, acc ->
      text =
        Enum.map_join(ch, "", fn
          {:xmlText, _, _, _, v, _} -> to_string(v)
          _ -> ""
        end)

      Map.put(acc, to_string(name), text)
    end)
  end

  defp parse_funding_response(_), do: %{}

  defp generate_id, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
