defmodule Worldpay.RAFT do
  @moduledoc """
  Worldpay **RAFT 610 Interface** — ISO 8583 card-present processing.

  Covers all payment types supported by the RAFT platform:
  Credit, Debit, EBT (SNAP/WIC), Gift Card, Fleet, Check/ACH, WIC.

  This module provides:

  1. `Worldpay.RAFT.Message` — ISO 8583 message builders
  2. `Worldpay.RAFT.Response` — response field extractors
  3. `Worldpay.RAFT` — submit messages over TCP/TLS to RAFT

  ## RAFT transaction types

  ### Credit card
  - Authorization (0100)
  - Sale (0200)
  - Capture (0220)
  - Reversal — full (0420), partial (0420 with partial flag)
  - Refund (0200 with reversal indicator)
  - Incremental authorization

  ### Debit card
  - Authorization (0100)
  - Pre-authorization / DUKPT key exchange
  - Reversal
  - Balance Inquiry (0100)

  ### EBT (Electronic Benefits Transfer)
  - SNAP purchase
  - SNAP return
  - Cash Benefits withdrawal
  - Balance Inquiry
  - Voice Authorization / Voucher Clear

  ### Gift Card
  - Activation (0200)
  - Balance Inquiry (0100)
  - Mini-Statement (0100)
  - Mass Transaction (0200)
  - Reload / Add Value (0200)

  ### Fleet Card
  - Authorization
  - Reversal

  ### Check / ACH
  - Enhanced Check Authorization (0200)
  - Reversal (0420)

  ### WIC (Women, Infants, Children)
  - Authorization
  - Reconciliation records

  ## Network management
  - System Health Check (0800)
  - Key Change Request (0800)
  - Lane Validation Request
  - FleetOne Batch Close
  - Reconciliation (0500/0510): Batch Inquiry, Batch Release, Batch Totals
  """

  alias Worldpay.{Config, Error}
  require Logger

  @typep auth_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           pan: term(),
           expiry: term(),
           amount: term(),
           cashback_amount: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           entry_mode: term(),
           cvv2: term(),
           avs_zip: term(),
           avs_address: term(),
           track2: term(),
           emv_data: term(),
           pin_block: term(),
           incremental: term(),
           original_amount: term(),
           processing_code: String.t(),
           response_r030: nil,
           response_r034: nil,
           response_r040: nil,
           response_r073: nil,
           response_r075: nil
         }

  @typep capture_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           original_stan: term(),
           original_auth_code: term(),
           amount: term(),
           partial: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term()
         }

  @typep reversal_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           original_stan: term(),
           original_auth_code: term(),
           amount: term(),
           partial_amount: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term()
         }

  @typep refund_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           pan: term(),
           expiry: term(),
           amount: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           entry_mode: term(),
           track2: term(),
           emv_data: term(),
           original_stan: term()
         }

  @typep balance_inquiry_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           pan: term(),
           expiry: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           pin_block: term(),
           entry_mode: term()
         }

  @typep ebt_snap_purchase_msg ::
           %{
             mti: String.t(),
             transaction_type: String.t(),
             pan: term(),
             expiry: term(),
             amount: term(),
             cashback_amount: term(),
             merchant_id: term(),
             terminal_id: term(),
             stan: term(),
             entry_mode: term(),
             cvv2: term(),
             avs_zip: term(),
             avs_address: term(),
             track2: term(),
             emv_data: term(),
             pin_block: term(),
             incremental: term(),
             original_amount: term(),
             processing_code: String.t(),
             response_r030: nil,
             response_r034: nil,
             response_r040: nil,
             response_r073: nil,
             response_r075: nil,
             payment_type: String.t()
           }

  @typep ebt_cash_msg :: ebt_snap_purchase_msg()

  @typep ebt_return_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           pan: term(),
           expiry: term(),
           amount: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           entry_mode: term(),
           track2: term(),
           emv_data: term(),
           original_stan: term(),
           payment_type: String.t()
         }

  @typep gift_activation_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           pan: term(),
           amount: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           entry_mode: term(),
           track2: term()
         }

  @typep gift_mini_statement_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           pan: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           entry_mode: term()
         }

  @typep fleet_details :: %{
           vehicle_id: term(),
           odometer: term(),
           driver_id: term(),
           product_code: term(),
           fleet_id: term()
         }

  @typep fleet_auth_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           pan: term(),
           expiry: term(),
           amount: term(),
           cashback_amount: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           entry_mode: term(),
           cvv2: term(),
           avs_zip: term(),
           avs_address: term(),
           track2: term(),
           emv_data: term(),
           pin_block: term(),
           incremental: term(),
           original_amount: term(),
           processing_code: String.t(),
           response_r030: nil,
           response_r034: nil,
           response_r040: nil,
           response_r073: nil,
           response_r075: nil,
           payment_type: String.t(),
           fleet: fleet_details()
         }

  @typep check_auth_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           routing_number: term(),
           account_number: term(),
           check_number: term(),
           amount: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           id_type: term(),
           id_number: term()
         }

  @typep wic_details :: %{
           wic_items: term(),
           store_id: term(),
           lane_id: term()
         }

  @typep wic_auth_msg :: %{
           mti: String.t(),
           transaction_type: String.t(),
           pan: term(),
           expiry: term(),
           amount: term(),
           cashback_amount: term(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           entry_mode: term(),
           cvv2: term(),
           avs_zip: term(),
           avs_address: term(),
           track2: term(),
           emv_data: term(),
           pin_block: term(),
           incremental: term(),
           original_amount: term(),
           processing_code: String.t(),
           response_r030: nil,
           response_r034: nil,
           response_r040: nil,
           response_r073: nil,
           response_r075: nil,
           payment_type: String.t(),
           wic: wic_details()
         }

  @typep batch_inquiry_msg :: %{
           mti: String.t(),
           reconciliation_type: String.t(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           batch_number: term()
         }

  @typep batch_release_msg :: %{
           mti: String.t(),
           reconciliation_type: String.t(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           batch_number: term(),
           batch_totals: term()
         }

  @typep batch_totals_msg :: %{
           mti: String.t(),
           reconciliation_type: String.t(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term()
         }

  @typep health_check_msg :: %{
           mti: String.t(),
           function_code: String.t(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term()
         }

  @typep key_change_msg :: %{
           mti: String.t(),
           function_code: String.t(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           key_serial_number: term()
         }

  @typep lane_validation_msg :: %{
           mti: String.t(),
           function_code: String.t(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term()
         }

  @typep fleet_batch_close_msg :: %{
           mti: String.t(),
           function_code: String.t(),
           merchant_id: term(),
           terminal_id: term(),
           stan: term(),
           batch_number: term()
         }

  # ── Message type indicators ────────────────────────────────────────────────

  @auth_request "0100"
  @financial_request "0200"
  @financial_advice "0220"
  @reversal_request "0420"
  @reconciliation_request "0500"
  @network_mgmt_request "0800"

  # ── Transaction type codes ────────────────────────────────────────────────

  @tx_purchase "00"
  @tx_cash "01"
  @tx_check_guarantee "06"
  @tx_balance_inquiry "31"
  @tx_activate "38"
  @tx_mini_statement "39"

  # ── Entry modes ───────────────────────────────────────────────────────────

  @entry_swiped "022"
  @entry_keyed "011"

  @doc """
  Build a credit card authorization request.

  ## Required opts

  - `:pan` — primary account number
  - `:expiry` — MMYY format
  - `:amount` — in cents/pennies (integer)
  - `:merchant_id` — RAFT merchant ID
  - `:terminal_id` — terminal identifier
  - `:stan` — systems trace audit number (6 digits)
  - `:entry_mode` — `"022"` (swipe) | `"051"` (EMV) | `"071"` (contactless) | `"011"` (keyed)

  ## Optional opts

  - `:cvv2` — card verification value
  - `:avs_zip` — zip for AVS check
  - `:avs_address` — address for AVS
  - `:track2` — raw track 2 data (card-present)
  - `:emv_data` — EMV TLV hex string (Field 55)
  - `:cashback_amount` — cashback in cents (debit)
  - `:pin_block` — encrypted PIN (DUKPT, debit/EBT)
  - `:incremental` — boolean (incremental auth)
  - `:original_amount` — original auth amount (for incremental)
  """
  @spec build_auth(keyword()) :: auth_msg()
  def build_auth(opts) do
    %{
      mti: @auth_request,
      transaction_type: @tx_purchase,
      pan: Keyword.fetch!(opts, :pan),
      expiry: Keyword.fetch!(opts, :expiry),
      amount: Keyword.fetch!(opts, :amount),
      cashback_amount: Keyword.get(opts, :cashback_amount),
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan),
      entry_mode: Keyword.get(opts, :entry_mode, @entry_keyed),
      cvv2: Keyword.get(opts, :cvv2),
      avs_zip: Keyword.get(opts, :avs_zip),
      avs_address: Keyword.get(opts, :avs_address),
      track2: Keyword.get(opts, :track2),
      emv_data: Keyword.get(opts, :emv_data),
      pin_block: Keyword.get(opts, :pin_block),
      incremental: Keyword.get(opts, :incremental, false),
      original_amount: Keyword.get(opts, :original_amount),
      processing_code: "000000",
      response_r030: nil,
      response_r034: nil,
      response_r040: nil,
      response_r073: nil,
      response_r075: nil
    }
  end

  @doc "Build a credit card sale (auth + auto-capture)."
  @spec build_sale(keyword()) :: auth_msg()
  def build_sale(opts) do
    opts
    |> build_auth()
    |> Map.put(:mti, @financial_request)
  end

  @doc "Build a capture (settlement) message."
  @spec build_capture(keyword()) :: capture_msg()
  def build_capture(opts) do
    %{
      mti: @financial_advice,
      transaction_type: @tx_purchase,
      original_stan: Keyword.fetch!(opts, :original_stan),
      original_auth_code: Keyword.fetch!(opts, :auth_code),
      amount: Keyword.fetch!(opts, :amount),
      partial: Keyword.get(opts, :partial, false),
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan)
    }
  end

  @doc "Build a full reversal message."
  @spec build_reversal(keyword()) :: reversal_msg()
  def build_reversal(opts) do
    %{
      mti: @reversal_request,
      transaction_type: @tx_purchase,
      original_stan: Keyword.fetch!(opts, :original_stan),
      original_auth_code: Keyword.get(opts, :auth_code),
      amount: Keyword.fetch!(opts, :amount),
      partial_amount: Keyword.get(opts, :partial_amount),
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan)
    }
  end

  @doc "Build a refund / credit message."
  @spec build_refund(keyword()) :: refund_msg()
  def build_refund(opts) do
    %{
      mti: @financial_request,
      transaction_type: "20",
      pan: Keyword.fetch!(opts, :pan),
      expiry: Keyword.fetch!(opts, :expiry),
      amount: Keyword.fetch!(opts, :amount),
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan),
      entry_mode: Keyword.get(opts, :entry_mode, @entry_keyed),
      track2: Keyword.get(opts, :track2),
      emv_data: Keyword.get(opts, :emv_data),
      original_stan: Keyword.get(opts, :original_stan)
    }
  end

  @doc "Build a balance inquiry message."
  @spec build_balance_inquiry(keyword()) :: balance_inquiry_msg()
  def build_balance_inquiry(opts) do
    %{
      mti: @auth_request,
      transaction_type: @tx_balance_inquiry,
      pan: Keyword.fetch!(opts, :pan),
      expiry: Keyword.get(opts, :expiry),
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan),
      pin_block: Keyword.get(opts, :pin_block),
      entry_mode: Keyword.get(opts, :entry_mode, @entry_swiped)
    }
  end

  @doc "Build an EBT SNAP purchase message."
  @spec build_ebt_snap_purchase(keyword()) :: ebt_snap_purchase_msg()
  def build_ebt_snap_purchase(opts) do
    opts
    |> build_sale()
    |> Map.put(:payment_type, "EBT_FOOD_STAMP")
    |> Map.put(:processing_code, "200000")
  end

  @doc "Build an EBT Cash Benefits withdrawal."
  @spec build_ebt_cash(keyword()) :: ebt_cash_msg()
  def build_ebt_cash(opts) do
    opts
    |> build_sale()
    |> Map.put(:payment_type, "EBT_CASH_BENEFIT")
    |> Map.put(:transaction_type, @tx_cash)
  end

  @doc "Build an EBT SNAP return/refund."
  @spec build_ebt_return(keyword()) :: ebt_return_msg()
  def build_ebt_return(opts) do
    opts
    |> build_refund()
    |> Map.put(:payment_type, "EBT_FOOD_STAMP")
  end

  @doc "Build a Gift Card activation message."
  @spec build_gift_activation(keyword()) :: gift_activation_msg()
  def build_gift_activation(opts) do
    %{
      mti: @financial_request,
      transaction_type: @tx_activate,
      pan: Keyword.fetch!(opts, :pan),
      amount: Keyword.fetch!(opts, :amount),
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan),
      entry_mode: Keyword.get(opts, :entry_mode, @entry_swiped),
      track2: Keyword.get(opts, :track2)
    }
  end

  @doc "Build a Gift Card add-value (reload) message."
  @spec build_gift_reload(keyword()) :: gift_activation_msg()
  def build_gift_reload(opts) do
    opts
    |> build_gift_activation()
    |> Map.put(:transaction_type, "70")
  end

  @doc "Build a Gift Card mini-statement message."
  @spec build_gift_mini_statement(keyword()) :: gift_mini_statement_msg()
  def build_gift_mini_statement(opts) do
    %{
      mti: @auth_request,
      transaction_type: @tx_mini_statement,
      pan: Keyword.fetch!(opts, :pan),
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan),
      entry_mode: Keyword.get(opts, :entry_mode, @entry_swiped)
    }
  end

  @doc "Build a Fleet card authorization."
  @spec build_fleet_auth(keyword()) :: fleet_auth_msg()
  def build_fleet_auth(opts) do
    base = build_auth(opts)

    fleet = %{
      vehicle_id: Keyword.get(opts, :vehicle_id),
      odometer: Keyword.get(opts, :odometer),
      driver_id: Keyword.get(opts, :driver_id),
      product_code: Keyword.get(opts, :product_code),
      fleet_id: Keyword.get(opts, :fleet_id)
    }

    Map.merge(base, %{payment_type: "FLEET", fleet: fleet})
  end

  @doc "Build a Check/ACH Enhanced Check Authorization."
  @spec build_check_auth(keyword()) :: check_auth_msg()
  def build_check_auth(opts) do
    %{
      mti: @financial_request,
      transaction_type: @tx_check_guarantee,
      routing_number: Keyword.fetch!(opts, :routing_number),
      account_number: Keyword.fetch!(opts, :account_number),
      check_number: Keyword.get(opts, :check_number),
      amount: Keyword.fetch!(opts, :amount),
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan),
      id_type: Keyword.get(opts, :id_type),
      id_number: Keyword.get(opts, :id_number)
    }
  end

  @doc "Build a WIC authorization."
  @spec build_wic_auth(keyword()) :: wic_auth_msg()
  def build_wic_auth(opts) do
    base = build_auth(opts)

    wic = %{
      wic_items: Keyword.get(opts, :wic_items, []),
      store_id: Keyword.get(opts, :store_id),
      lane_id: Keyword.get(opts, :lane_id)
    }

    Map.merge(base, %{payment_type: "WIC", wic: wic})
  end

  # ── Reconciliation ────────────────────────────────────────────────────────

  @doc "Build a batch inquiry message (0500)."
  @spec build_batch_inquiry(keyword()) :: batch_inquiry_msg()
  def build_batch_inquiry(opts) do
    %{
      mti: @reconciliation_request,
      reconciliation_type: "batch_inquiry",
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan),
      batch_number: Keyword.get(opts, :batch_number)
    }
  end

  @doc "Build a batch release (close) message (0500)."
  @spec build_batch_release(keyword()) :: batch_release_msg()
  def build_batch_release(opts) do
    %{
      mti: @reconciliation_request,
      reconciliation_type: "batch_release",
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan),
      batch_number: Keyword.fetch!(opts, :batch_number),
      batch_totals: Keyword.get(opts, :batch_totals, %{})
    }
  end

  @doc "Build a batch totals request."
  @spec build_batch_totals(keyword()) :: batch_totals_msg()
  def build_batch_totals(opts) do
    %{
      mti: @reconciliation_request,
      reconciliation_type: "batch_totals",
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan)
    }
  end

  # ── Network management ────────────────────────────────────────────────────

  @doc "Build a system health check message (0800)."
  @spec build_health_check(keyword()) :: health_check_msg()
  def build_health_check(opts) do
    %{
      mti: @network_mgmt_request,
      function_code: "301",
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan)
    }
  end

  @doc "Build a DUKPT key change request (0800)."
  @spec build_key_change(keyword()) :: key_change_msg()
  def build_key_change(opts) do
    %{
      mti: @network_mgmt_request,
      function_code: "161",
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan),
      key_serial_number: Keyword.fetch!(opts, :key_serial_number)
    }
  end

  @doc "Build a lane validation request."
  @spec build_lane_validation(keyword()) :: lane_validation_msg()
  def build_lane_validation(opts) do
    %{
      mti: @network_mgmt_request,
      function_code: "111",
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan)
    }
  end

  @doc "Build a FleetOne batch close request."
  @spec build_fleet_batch_close(keyword()) :: fleet_batch_close_msg()
  def build_fleet_batch_close(opts) do
    %{
      mti: @network_mgmt_request,
      function_code: "201",
      merchant_id: Keyword.fetch!(opts, :merchant_id),
      terminal_id: Keyword.fetch!(opts, :terminal_id),
      stan: Keyword.fetch!(opts, :stan),
      batch_number: Keyword.fetch!(opts, :batch_number)
    }
  end

  # ── Response helpers ──────────────────────────────────────────────────────

  defmodule Response do
    @moduledoc "Extractors for RAFT ISO 8583 response fields."

    @doc ~s{True if response code indicates approval (`"000"`, `"00"`, or `"0000"`).}
    @spec approved?(%{atom() => term()}) :: boolean()
    def approved?(%{response_code: code}), do: code in ["000", "00", "0000"]
    def approved?(_), do: false

    @doc "Extract response code."
    @spec response_code(%{atom() => term()}) :: String.t() | nil
    def response_code(%{response_code: c}), do: c
    def response_code(_), do: nil

    @doc "Extract authorization code."
    @spec auth_code(%{atom() => term()}) :: String.t() | nil
    def auth_code(%{auth_code: c}), do: c
    def auth_code(_), do: nil

    @doc "Extract Debit Optimization Result (R034)."
    @spec debit_optimization_result(%{atom() => term()}) :: String.t() | nil
    def debit_optimization_result(%{response_r034: r}), do: r
    def debit_optimization_result(_), do: nil

    @doc "Extract 8-digit BIN result (R040)."
    @spec bin8(%{atom() => term()}) :: String.t() | nil
    def bin8(%{response_r040: r}), do: r
    def bin8(_), do: nil

    @doc "Extract Visa Agreement ID (R073)."
    @spec visa_agreement_id(%{atom() => term()}) :: String.t() | nil
    def visa_agreement_id(%{response_r073: r}), do: r
    def visa_agreement_id(_), do: nil

    @doc "Extract Additional Response Data (R030) — AC, NC, SC fields."
    @spec additional_response_data(%{atom() => term()}) :: %{atom() => term()} | nil
    def additional_response_data(%{response_r030: r}), do: r
    def additional_response_data(_), do: nil

    @doc "Extract Raw Network Response Data (R075)."
    @spec raw_network_response(%{atom() => term()}) :: String.t() | nil
    def raw_network_response(%{response_r075: r}), do: r
    def raw_network_response(_), do: nil

    @doc "Extract FraudSight decline indicator."
    @spec fraudsight_declined?(%{atom() => term()}) :: boolean()
    def fraudsight_declined?(%{fraudsight_declined: true}), do: true
    def fraudsight_declined?(_), do: false

    @doc "Extract balance (debit/EBT/Gift)."
    @spec balance(%{atom() => term()}) :: %{atom() => term()} | nil
    def balance(%{balance: b}), do: b
    def balance(_), do: nil
  end

  # ── Submit (TCP/TLS to RAFT) ──────────────────────────────────────────────

  @doc """
  Submit a RAFT ISO 8583 message over TCP/TLS.

  In production, RAFT connection details (host, port, TLS certs) are
  supplied by Worldpay Implementation Manager. This function establishes
  a TLS connection, frames the message in the RAFT envelope, sends it,
  and parses the response.

  **Note:** The actual ISO 8583 bit-map encoding and field serialization
  are proprietary to RAFT. This function is a integration point; replace
  `serialize/1` and `deserialize/1` with the RAFT-specific codec
  provided by Worldpay.
  """
  @spec submit(%{atom() => term()}, Config.t()) ::
          {:ok, %{String.t() => term()}} | {:error, Error.t()}
  def submit(message, %Config{} = config) do
    host = Application.get_env(:worldpay, :raft_host, "raft.worldpay.com")
    port = Application.get_env(:worldpay, :raft_port, 9999)
    timeout = config.timeout

    case connect(host, port, timeout) do
      {:ok, socket} ->
        try do
          payload = serialize(message)
          :ok = :ssl.send(socket, payload)

          case :ssl.recv(socket, 0, timeout) do
            {:ok, response_bytes} ->
              {:ok, deserialize(response_bytes)}

            {:error, reason} ->
              {:error,
               %Error{
                 type: :network_error,
                 reason: reason,
                 message: "RAFT recv failed: #{inspect(reason)}"
               }}
          end
        after
          :ssl.close(socket)
        end

      {:error, reason} ->
        {:error,
         %Error{
           type: :network_error,
           reason: :connection_failed,
           message: "RAFT connect failed: #{inspect(reason)}"
         }}
    end
  end

  # ── private ───────────────────────────────────────────────────────────────

  @spec connect(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, term()} | {:error, term()}
  defp connect(host, port, timeout) do
    tls_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      active: false
    ]

    :ssl.connect(String.to_charlist(host), port, tls_opts, timeout)
  end

  @doc false
  @spec serialize(%{atom() => term()}) :: binary()
  def serialize(message) do
    # Placeholder — replace with RAFT-specific ISO 8583 codec
    # The actual bit-map and field encoding is supplied by Worldpay IM
    mti = Map.get(message, :mti, "0100")
    encoded = Jason.encode!(message)
    length = byte_size(encoded) + 4
    <<length::32>> <> mti <> encoded
  end

  @doc false
  @spec deserialize(binary()) :: %{String.t() => term()}
  def deserialize(bytes) do
    # Placeholder — replace with RAFT-specific ISO 8583 decoder
    case bytes do
      <<_length::32, mti::binary-size(4), rest::binary>> ->
        case Jason.decode(rest) do
          {:ok, fields} -> Map.put(fields, "mti", mti)
          _ -> %{"raw" => bytes, "mti" => mti}
        end

      _ ->
        %{"raw" => bytes}
    end
  end
end
