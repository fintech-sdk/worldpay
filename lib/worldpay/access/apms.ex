defmodule Worldpay.APMs do
  @moduledoc """
  Worldpay **APMs API** — Alternative Payment Methods.

  Supports 28 APMs across eWallets, bank transfers, direct debits, BNPL,
  and local card schemes.

  ## Supported APMs

  ACH · Alipay China · Alipay HK · Alipay+ · BANCOMAT Pay · Bancontact ·
  Bizum · BLIK · Canadian EFT · Euteller · iDEAL · Klarna · Konbini ·
  Multibanco · MyBank · Open Banking · PayPal · PaysafeCard · Pix ·
  Przelewy24 · SafetyPay · SEPA Direct Debit · Swish · Toss Pay ·
  Trustly · WeChat Pay · China UnionPay

  ## Lifecycle actions

  Follow `_actions` links from responses, or use the convenience functions:

      {:ok, _} = Worldpay.APMs.settle(payment_id, config)
      {:ok, _} = Worldpay.APMs.reverse(payment_id, config)
      {:ok, _} = Worldpay.APMs.partial_reverse(payment_id, 500, "EUR", config)
  """

  alias Worldpay.{Client, Config, Error}

  @valid_klarna_types ~w[payLater payNow payOverTime buyNowPayLater]

  @doc "Initiate an APM payment."
  @spec pay(map(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def pay(body, %Config{} = config, opts \\ []) do
    Client.post(
      "/payments/alternative/direct",
      body,
      [api: :apms, operation: :pay, idempotency_key: key(opts)],
      config
    )
  end

  @doc "Settle an APM payment."
  @spec settle(String.t(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def settle(payment_id, %Config{} = config, opts \\ []) do
    Client.post(
      "/payments/alternative/#{payment_id}/settlements",
      %{},
      [api: :apms, operation: :settle, idempotency_key: key(opts)],
      config
    )
  end

  @doc "Partial settle an APM payment."
  @spec partial_settle(String.t(), non_neg_integer(), String.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def partial_settle(payment_id, amount, currency, %Config{} = config, opts \\ []) do
    body = %{"value" => %{"amount" => amount, "currency" => currency}}

    Client.post(
      "/payments/alternative/#{payment_id}/settlements",
      body,
      [api: :apms, operation: :partial_settle, idempotency_key: key(opts)],
      config
    )
  end

  @doc "Reverse (cancel) an APM payment."
  @spec reverse(String.t(), Config.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def reverse(payment_id, %Config{} = config, opts \\ []) do
    Client.post(
      "/payments/alternative/#{payment_id}/reversals",
      %{},
      [api: :apms, operation: :reverse, idempotency_key: key(opts)],
      config
    )
  end

  @doc "Partial reverse an APM payment."
  @spec partial_reverse(String.t(), non_neg_integer(), String.t(), Config.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def partial_reverse(payment_id, amount, currency, %Config{} = config, opts \\ []) do
    body = %{"value" => %{"amount" => amount, "currency" => currency}}

    Client.post(
      "/payments/alternative/#{payment_id}/reversals",
      body,
      [api: :apms, operation: :partial_reverse, idempotency_key: key(opts)],
      config
    )
  end

  @doc "Get APM payment status."
  @spec get(String.t(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(payment_id, %Config{} = config) do
    Client.get(
      "/payments/alternative/#{payment_id}",
      [api: :apms, operation: :get],
      config
    )
  end

  @doc "POST to an `_actions` link returned in a previous APM response."
  @spec action(String.t(), map(), Config.t()) :: {:ok, map()} | {:error, Error.t()}
  def action(href, body \\ %{}, %Config{} = config) do
    Client.post(
      href_to_path(href),
      body,
      [api: :apms, operation: :action, idempotency_key: generate_key()],
      config
    )
  end

  # ── Payment instrument builders ───────────────────────────────────────────

  @doc "Build an iDEAL payment instrument."
  @spec ideal(keyword()) :: %{String.t() => String.t()}
  def ideal(opts \\ []) do
    %{"type" => "ideal/redirect"}
    |> put_if_present("tokenHref", Keyword.get(opts, :token_href))
  end

  @doc "Build a PayPal payment instrument."
  @spec paypal(keyword()) :: %{String.t() => String.t()}
  def paypal(opts \\ []) do
    %{"type" => "paypal/redirect"}
    |> put_if_present("shopperEmail", Keyword.get(opts, :shopper_email))
    |> put_if_present("shopperName", Keyword.get(opts, :shopper_name))
  end

  @doc "Build a Klarna payment instrument."
  @spec klarna(String.t(), keyword()) :: %{String.t() => term()}
  def klarna(klarna_type \\ "payLater", opts \\ []) do
    unless klarna_type in @valid_klarna_types do
      raise ArgumentError,
            "Invalid Klarna type: #{inspect(klarna_type)}. Must be one of #{inspect(@valid_klarna_types)}"
    end

    %{"type" => "klarna/#{klarna_type}"}
    |> put_if_present("locale", Keyword.get(opts, :locale))
    |> put_if_present("shopperEmail", Keyword.get(opts, :shopper_email))
    |> put_if_present("shopperPhone", Keyword.get(opts, :shopper_phone))
    |> put_if_present("passthroughData", Keyword.get(opts, :passthrough_data))
  end

  @doc "Build an ACH / eCheck payment instrument."
  @spec ach(String.t(), String.t(), String.t()) :: %{String.t() => String.t()}
  def ach(account_number, routing_number, account_type \\ "checking") do
    %{
      "type" => "ach/direct",
      "accountNumber" => account_number,
      "routingNumber" => routing_number,
      "accountType" => account_type
    }
  end

  @doc "Build a SEPA Direct Debit instrument."
  @spec sepa(String.t(), String.t()) :: %{String.t() => String.t()}
  def sepa(iban, mandate_reference) do
    %{"type" => "sepa/direct", "iban" => iban, "mandateReference" => mandate_reference}
  end

  @doc "Build a Pix instrument (requires Brazilian CPF document)."
  @spec pix(String.t(), keyword()) :: %{String.t() => term()}
  def pix(cpf, opts \\ []) do
    %{
      "type" => "pix/qrCode",
      "identityDocuments" => [%{"type" => "CPF", "reference" => cpf}]
    }
    |> put_if_present("expiryIn", Keyword.get(opts, :expiry_in))
  end

  @doc "Build a Swish instrument."
  @spec swish(String.t()) :: %{String.t() => String.t()}
  def swish(phone_number) do
    %{"type" => "swish/redirect", "shopperPhone" => phone_number}
  end

  @doc "Build a BLIK instrument."
  @spec blik(String.t()) :: %{String.t() => String.t()}
  def blik(blik_code) do
    %{"type" => "blik/direct", "blikCode" => blik_code}
  end

  @doc "Build a WeChat Pay instrument."
  @spec wechat_pay() :: %{String.t() => String.t()}
  def wechat_pay, do: %{"type" => "wechatPay/redirect"}

  @doc "Build an Open Banking instrument."
  @spec open_banking(keyword()) :: %{String.t() => String.t()}
  def open_banking(opts \\ []) do
    %{"type" => "openBanking/redirect"}
    |> put_if_present("bankId", Keyword.get(opts, :bank_id))
    |> put_if_present("countryCode", Keyword.get(opts, :country_code))
  end

  @doc "Build a Przelewy24 instrument."
  @spec przelewy24(keyword()) :: %{String.t() => String.t()}
  def przelewy24(opts \\ []) do
    %{"type" => "przelewy24/redirect"}
    |> put_if_present("shopperEmail", Keyword.get(opts, :shopper_email))
  end

  @doc "Build a Bancontact instrument."
  @spec bancontact(keyword()) :: %{String.t() => String.t()}
  def bancontact(opts \\ []) do
    %{"type" => "bancontact/redirect"}
    |> put_if_present("shopperName", Keyword.get(opts, :shopper_name))
  end

  @doc "Build a MyBank instrument."
  @spec my_bank(keyword()) :: %{String.t() => String.t()}
  def my_bank(opts \\ []) do
    %{"type" => "myBank/redirect"}
    |> put_if_present("bankId", Keyword.get(opts, :bank_id))
  end

  @doc "Build a Canadian EFT instrument."
  @spec canadian_eft(String.t(), String.t(), String.t()) :: %{String.t() => String.t()}
  def canadian_eft(account_number, transit_number, institution_number) do
    %{
      "type" => "eft/direct",
      "accountNumber" => account_number,
      "transitNumber" => transit_number,
      "institutionNumber" => institution_number
    }
  end

  @doc "Build an Alipay instrument."
  @spec alipay(String.t()) :: %{String.t() => String.t()}
  def alipay(variant \\ "alipay") do
    %{"type" => "#{variant}/redirect"}
  end

  # ── private ───────────────────────────────────────────────────────────────

  @spec href_to_path(String.t()) :: String.t()
  defp href_to_path("https://" <> _ = href) do
    uri = URI.parse(href)
    uri.path || href
  end

  defp href_to_path(path), do: path

  @spec key(keyword()) :: String.t()
  defp key(opts), do: Keyword.get(opts, :idempotency_key, generate_key())

  @spec generate_key() :: String.t()
  defp generate_key, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  @spec put_if_present(%{String.t() => String.t()}, String.t(), String.t() | nil) :: %{
          String.t() => String.t()
        }
  defp put_if_present(map, _k, nil), do: map
  defp put_if_present(map, k, v), do: Map.put(map, k, v)
end
