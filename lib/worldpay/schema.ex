defmodule Worldpay.Schema.Amount do
  @moduledoc "Monetary amount with currency."

  @type t :: %__MODULE__{value: non_neg_integer(), currency: String.t()}

  @enforce_keys [:value, :currency]
  defstruct [:value, :currency]

  @doc "Build from a string-keyed or atom-keyed map."
  @spec from_map(%{String.t() => term()} | %{atom() => term()}) :: t()
  def from_map(%{"value" => v, "currency" => c}), do: %__MODULE__{value: v, currency: c}
  def from_map(%{value: v, currency: c}), do: %__MODULE__{value: v, currency: c}

  @doc "Serialize to a string-keyed map."
  @spec to_map(t()) :: %{String.t() => term()}
  def to_map(%__MODULE__{value: v, currency: c}), do: %{"value" => v, "currency" => c}
end

defmodule Worldpay.Schema.Address do
  @moduledoc "Billing or shipping address."

  @type t :: %__MODULE__{
          address1: String.t() | nil,
          address2: String.t() | nil,
          address3: String.t() | nil,
          postal_code: String.t() | nil,
          city: String.t() | nil,
          state: String.t() | nil,
          country_code: String.t() | nil
        }

  defstruct [:address1, :address2, :address3, :postal_code, :city, :state, :country_code]

  @doc "Serialize to a string-keyed map, omitting nil values."
  def to_map(%__MODULE__{} = a) do
    %{
      "address1" => a.address1,
      "address2" => a.address2,
      "address3" => a.address3,
      "postalCode" => a.postal_code,
      "city" => a.city,
      "state" => a.state,
      "countryCode" => a.country_code
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end
end

defmodule Worldpay.Schema.Narrative do
  @moduledoc "Statement narrative (merchant descriptor on card statement)."

  @type t :: %__MODULE__{line1: String.t(), line2: String.t() | nil}

  @enforce_keys [:line1]
  defstruct [:line1, :line2]

  @doc "Serialize to a string-keyed map."
  @spec to_map(t()) :: %{String.t() => String.t()}
  def to_map(%__MODULE__{line1: l1, line2: nil}), do: %{"line1" => l1}
  def to_map(%__MODULE__{line1: l1, line2: l2}), do: %{"line1" => l1, "line2" => l2}
end

defmodule Worldpay.Schema.Merchant do
  @moduledoc "Merchant entity reference, including optional PayFac data."

  @type t :: %__MODULE__{
          entity: String.t(),
          mcc: String.t() | nil,
          payment_facilitator: %{String.t() => term()} | nil
        }

  @enforce_keys [:entity]
  defstruct [:entity, :mcc, :payment_facilitator]

  @doc "Serialize to a string-keyed map."
  def to_map(%__MODULE__{} = m) do
    %{"entity" => m.entity}
    |> put_present("mcc", m.mcc)
    |> put_present("paymentFacilitator", m.payment_facilitator)
  end

  @spec put_present(%{String.t() => term()}, String.t(), term()) :: %{String.t() => term()}
  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, val), do: Map.put(map, key, val)
end

defmodule Worldpay.Schema.CustomerAgreement do
  @moduledoc """
  Stored credential agreement types:
  `:card_on_file` | `:subscription` | `:installment` | `:unscheduled`
  """

  @type agreement_type :: :card_on_file | :subscription | :installment | :unscheduled
  @type stored_card_usage :: :first | :subsequent

  @type t :: %__MODULE__{
          type: agreement_type(),
          stored_card_usage: stored_card_usage() | nil,
          scheme_reference: String.t() | nil
        }

  @enforce_keys [:type]
  defstruct [:type, :stored_card_usage, :scheme_reference]

  @doc "Serialize to a string-keyed map."
  @spec to_map(t()) :: %{String.t() => String.t()}
  def to_map(%__MODULE__{} = ca) do
    %{"type" => encode_type(ca.type)}
    |> put_present("storedCardUsage", encode_usage(ca.stored_card_usage))
    |> put_present("schemeReference", ca.scheme_reference)
  end

  @spec encode_type(agreement_type()) :: String.t()
  defp encode_type(:card_on_file), do: "cardOnFile"
  defp encode_type(:subscription), do: "subscription"
  defp encode_type(:installment), do: "installment"
  defp encode_type(:unscheduled), do: "unscheduled"

  @spec encode_usage(stored_card_usage() | nil) :: String.t() | nil
  defp encode_usage(:first), do: "first"
  defp encode_usage(:subsequent), do: "subsequent"
  defp encode_usage(nil), do: nil

  @spec put_present(%{String.t() => String.t()}, String.t(), String.t() | nil) ::
          %{String.t() => String.t()}
  defp put_present(map, _k, nil), do: map
  defp put_present(map, k, v) when is_binary(v), do: Map.put(map, k, v)
end

defmodule Worldpay.Schema.ThreeDS do
  @moduledoc "3DS authentication result to attach to a payment."

  @type t :: %__MODULE__{
          eci: String.t() | nil,
          authentication_value: String.t() | nil,
          transaction_id: String.t() | nil,
          version: String.t() | nil,
          type: String.t(),
          challenge_preference: String.t() | nil
        }

  defstruct [
    :eci,
    :authentication_value,
    :transaction_id,
    :version,
    :challenge_preference,
    type: "integrated"
  ]

  @doc "Serialize to a string-keyed map."
  @spec to_map(t()) :: %{String.t() => String.t()}
  def to_map(%__MODULE__{} = t) do
    %{"type" => t.type}
    |> put_present("eci", t.eci)
    |> put_present("authenticationValue", t.authentication_value)
    |> put_present("transactionId", t.transaction_id)
    |> put_present("version", t.version)
    |> put_present("challengePreference", t.challenge_preference)
  end

  @spec put_present(%{String.t() => String.t()}, String.t(), String.t() | nil) ::
          %{String.t() => String.t()}
  defp put_present(map, _k, nil), do: map
  defp put_present(map, k, v) when is_binary(v), do: Map.put(map, k, v)
end

defmodule Worldpay.Schema.FundsTransfer do
  @moduledoc "Account Funding Transaction (AFT) metadata."

  @type t :: %__MODULE__{
          type: String.t() | nil,
          purpose: String.t() | nil,
          sender: %{String.t() => term()} | nil,
          recipient: %{String.t() => term()} | nil
        }

  defstruct [:type, :purpose, :sender, :recipient]

  @doc "Serialize to a string-keyed map."
  def to_map(%__MODULE__{} = ft) do
    %{}
    |> put_present("type", ft.type)
    |> put_present("purpose", ft.purpose)
    |> put_present("sender", ft.sender)
    |> put_present("recipient", ft.recipient)
  end

  defp put_present(map, _k, nil), do: map
  defp put_present(map, k, v), do: Map.put(map, k, v)
end

defmodule Worldpay.Schema.PaymentInstrument do
  @moduledoc """
  Payment instrument variants.

  | `:type` | Description |
  |---|---|
  | `"card/plain"` | Raw card details |
  | `"card/checkout"` | Checkout SDK session href |
  | `"card/token"` | Stored Worldpay token href |
  | `"card/networkToken"` | Network token href + optional cryptogram |
  | `"card/networkToken+applepay"` | Decrypted Apple Pay network token |
  | `"card/networkToken+googlepay"` | Decrypted Google Pay network token |
  """

  alias Worldpay.Schema.Address

  @type t :: %__MODULE__{
          type: String.t(),
          card_holder_name: String.t() | nil,
          card_number: String.t() | nil,
          expiry_month: non_neg_integer() | nil,
          expiry_year: non_neg_integer() | nil,
          cvc: String.t() | nil,
          billing_address: Address.t() | nil,
          href: String.t() | nil,
          cryptogram: String.t() | nil,
          eci: String.t() | nil,
          session_href: String.t() | nil,
          token: String.t() | nil
        }

  @enforce_keys [:type]
  defstruct [
    :type,
    :card_holder_name,
    :card_number,
    :expiry_month,
    :expiry_year,
    :cvc,
    :billing_address,
    :href,
    :cryptogram,
    :eci,
    :session_href,
    :token
  ]

  @doc "Serialize to a string-keyed map for the Worldpay API."
  @spec to_map(t()) :: %{String.t() => term()}
  def to_map(%__MODULE__{type: "card/plain"} = pi) do
    %{
      "type" => "card/plain",
      "cardHolderName" => pi.card_holder_name,
      "cardNumber" => pi.card_number,
      "cardExpiryDate" => %{"month" => pi.expiry_month, "year" => pi.expiry_year}
    }
    |> put_present("cvc", pi.cvc)
    |> put_present("billingAddress", serialize_address(pi.billing_address))
  end

  def to_map(%__MODULE__{type: "card/checkout"} = pi) do
    %{"type" => "card/checkout", "href" => pi.session_href}
  end

  def to_map(%__MODULE__{type: "card/token"} = pi) do
    %{"type" => "card/token", "href" => pi.href}
    |> put_present("cvc", pi.cvc)
  end

  def to_map(%__MODULE__{type: "card/networkToken"} = pi) do
    %{"type" => "card/networkToken", "href" => pi.href}
    |> put_present("cryptogram", pi.cryptogram)
    |> put_present("eci", pi.eci)
  end

  def to_map(%__MODULE__{type: t} = pi)
      when t in ["card/networkToken+applepay", "card/networkToken+googlepay"] do
    %{"type" => t, "token" => pi.token}
  end

  def to_map(%__MODULE__{type: t} = pi) do
    %{"type" => t}
    |> put_present("href", pi.href)
    |> put_present("token", pi.token)
  end

  @spec serialize_address(Address.t() | nil) :: %{String.t() => String.t()} | nil
  defp serialize_address(nil), do: nil
  defp serialize_address(addr), do: Address.to_map(addr)

  @spec put_present(%{String.t() => term()}, String.t(), term()) :: %{String.t() => term()}
  defp put_present(map, _k, nil), do: map
  defp put_present(map, k, v), do: Map.put(map, k, v)
end
