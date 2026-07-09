defmodule Worldpay.Partner.Boarding do
  @moduledoc """
  Worldpay **Merchant Boarding API** — onboard merchants programmatically.

  Partners (ISOs) collect merchant business information and submit it via
  this API, giving full control over the merchant onboarding experience.

  ## Example

      {:ok, merchant} = Worldpay.Partner.Boarding.create_merchant(%{
        "merchant" => %{
          "businessName" => "Jane's Bakery",
          "businessType" => "soleTrader",
          "mcc" => "5462",
          "website" => "https://janesbakery.com",
          "contact" => %{
            "firstName" => "Jane",
            "lastName" => "Doe",
            "email" => "jane@example.com",
            "phone" => "+441234567890"
          },
          "address" => %{
            "address1" => "123 High Street",
            "city" => "London",
            "postalCode" => "SW1A 1AA",
            "countryCode" => "GB"
          },
          "bankAccount" => %{
            "accountNumber" => "12345678",
            "sortCode" => "010203",
            "accountName" => "Jane Doe"
          }
        }
      }, config)
  """

  alias Worldpay.{Client, Config}

  @doc "Create (board) a new merchant."
  @spec create_merchant(map(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def create_merchant(body, %Config{} = config) do
    Client.post(
      "/boarding/merchants",
      body,
      [api: :boarding, operation: :create_merchant],
      config
    )
  end

  @doc "Retrieve a boarded merchant by ID."
  @spec get_merchant(String.t(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def get_merchant(merchant_id, %Config{} = config) do
    Client.get(
      "/boarding/merchants/#{merchant_id}",
      [api: :boarding, operation: :get_merchant],
      config
    )
  end

  @doc "Update an existing merchant's details."
  @spec update_merchant(String.t(), map(), Config.t()) ::
          {:ok, map()} | {:error, Worldpay.Error.t()}
  def update_merchant(merchant_id, body, %Config{} = config) do
    Client.put(
      "/boarding/merchants/#{merchant_id}",
      body,
      [api: :boarding, operation: :update_merchant],
      config
    )
  end

  @doc "List boarded merchants for the partner."
  @spec list_merchants(keyword(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def list_merchants(params \\ [], %Config{} = config) do
    query = Keyword.take(params, [:status, :pageSize, :pageNumber])

    Client.get(
      "/boarding/merchants",
      [api: :boarding, operation: :list_merchants, query: query],
      config
    )
  end
end

defmodule Worldpay.Partner.LeadSubmission do
  @moduledoc """
  Worldpay **Lead Submission API** — submit merchant leads to Worldpay Salesforce CRM.

  A Worldpay sales representative contacts the merchant to begin the sales cycle.

  ## Example

      {:ok, lead} = Worldpay.Partner.LeadSubmission.submit(%{
        "lead" => %{
          "firstName" => "John",
          "lastName" => "Smith",
          "email" => "john@example.com",
          "phone" => "+441234567890",
          "businessName" => "Smith & Co",
          "estimatedAnnualVolume" => 120000,
          "partnerReference" => "partner-lead-001"
        }
      }, config)
  """

  alias Worldpay.{Client, Config}

  @doc "Submit a merchant lead to Worldpay Salesforce."
  @spec submit(map(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def submit(body, %Config{} = config) do
    Client.post(
      "/leads",
      body,
      [api: :lead_submission, operation: :submit],
      config
    )
  end

  @doc "Retrieve a lead by ID."
  @spec get(String.t(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def get(lead_id, %Config{} = config) do
    Client.get(
      "/leads/#{lead_id}",
      [api: :lead_submission, operation: :get],
      config
    )
  end
end

defmodule Worldpay.Partner.Notifications do
  @moduledoc """
  Worldpay **Transaction Notification API** — parse partner transaction notifications.

  Worldpay sends authorized transaction details to your HTTPS endpoint
  for debit, credit, and gift card transactions.

  ## Setup

  Your notification URL is registered with Worldpay IM.
  IP whitelist your WAF to allow Worldpay notification IPs.

  ## Usage

  In your webhook controller, parse the incoming notification:

      {:ok, notification} = Worldpay.Partner.Notifications.parse(body)
      notification.transaction_type  # => :credit_sale | :debit_sale | :gift_card | ...
      notification.amount            # => 1999
      notification.approval_number   # => "123456"
  """

  @type notification :: %{
          transaction_type: atom(),
          amount: non_neg_integer() | nil,
          approval_number: String.t() | nil,
          card_type: String.t() | nil,
          card_last4: String.t() | nil,
          merchant_id: String.t() | nil,
          terminal_id: String.t() | nil,
          transaction_date: String.t() | nil,
          reference_number: String.t() | nil,
          raw: map()
        }

  @doc "Parse a partner transaction notification body."
  @spec parse(String.t() | %{String.t() => term()}) :: {:ok, notification()}
  def parse(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} ->
        parse(map)

      {:error, _} ->
        # Try XML. :xmerl_scan.string/2 always returns a 2-tuple on
        # success (it raises on malformed XML), so there's no error
        # tuple to match here.
        {_doc, _rest} = :xmerl_scan.string(String.to_charlist(body), quiet: true)
        {:ok, %{transaction_type: :unknown, raw: %{"xml" => body}}}
    end
  end

  def parse(body) when is_map(body) do
    notification = %{
      transaction_type: classify_transaction(body),
      amount: parse_amount(body["amount"] || body["TransactionAmount"]),
      approval_number: body["approvalNumber"] || body["ApprovalNumber"],
      card_type: body["cardType"] || body["CardType"],
      card_last4: body["cardLast4"] || body["CardNumberLast4"],
      merchant_id: body["merchantId"] || body["MerchantID"],
      terminal_id: body["terminalId"] || body["TerminalID"],
      transaction_date: body["transactionDate"] || body["TransactionDate"],
      reference_number: body["referenceNumber"] || body["ReferenceNumber"],
      raw: body
    }

    {:ok, notification}
  end

  defp classify_transaction(%{"transactionType" => t}) when is_binary(t) do
    sanitized = t |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "_")
    # Bounded input: only Worldpay API constant strings arrive here.
    # Use to_existing_atom/1; fall back to binary_to_atom for new event types.
    try do
      String.to_existing_atom(sanitized)
    rescue
      ArgumentError -> :erlang.binary_to_existing_atom(sanitized, :utf8)
    end
  end

  defp classify_transaction(%{"paymentType" => "Credit"}), do: :credit_sale
  defp classify_transaction(%{"paymentType" => "Debit"}), do: :debit_sale
  defp classify_transaction(%{"paymentType" => "GiftCard"}), do: :gift_card
  defp classify_transaction(%{"paymentType" => "EBT"}), do: :ebt
  defp classify_transaction(_), do: :unknown

  defp parse_amount(nil), do: nil
  defp parse_amount(a) when is_integer(a), do: a

  defp parse_amount(a) when is_binary(a) do
    case Integer.parse(a) do
      {n, _} -> n
      :error -> nil
    end
  end
end

defmodule Worldpay.Partner.TerminalLease do
  @moduledoc """
  Worldpay **Terminal Lease Notification API** — equipment lease alerts.

  Worldpay notifies partners when merchants request terminal equipment leases.
  Parse the incoming notification to action lease requests.
  """

  @type lease_notification :: %{
          merchant_id: String.t() | nil,
          terminal_model: String.t() | nil,
          quantity: non_neg_integer() | nil,
          lease_term: String.t() | nil,
          status: atom(),
          raw: map()
        }

  @doc "Parse a terminal lease notification."
  @spec parse(String.t() | %{String.t() => term()}) :: {:ok, lease_notification()}
  def parse(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> parse(map)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  def parse(body) when is_map(body) do
    notification = %{
      merchant_id: body["merchantId"],
      terminal_model: body["terminalModel"],
      quantity: body["quantity"],
      lease_term: body["leaseTerm"],
      status: lease_status(body["status"]),
      raw: body
    }

    {:ok, notification}
  end

  defp lease_status("pending"), do: :pending
  defp lease_status("approved"), do: :approved
  defp lease_status("shipped"), do: :shipped
  defp lease_status("cancelled"), do: :cancelled
  defp lease_status(_), do: :unknown
end

defmodule Worldpay.HPP do
  @moduledoc """
  Worldpay **Hosted Payment Page (HPP)** API — hosted checkout and pay-by-link.

  Generates HPP session URLs and pay-by-link URLs. The customer is redirected
  to a Worldpay-hosted page to complete payment, keeping merchants fully
  out of PCI scope (SAQ A).

  ## Integration modes

  - **Redirect** — customer redirected from your site to HPP
  - **Lightbox / iFrame** — HPP embedded in your checkout page
  - **Pay-by-link** — shareable URL sent by email/SMS

  ## Example

      {:ok, session} = Worldpay.HPP.create_session(%{
        "merchant" => %{"entity" => "default"},
        "instruction" => %{
          "value" => %{"amount" => 1999, "currency" => "GBP"},
          "narrative" => %{"line1" => "My Store"}
        },
        "resultUrls" => %{
          "successUrl" => "https://example.com/success",
          "failureUrl" => "https://example.com/failure",
          "cancelUrl" => "https://example.com/cancel"
        },
        "expiry" => "PT1H"
      }, config)

      redirect_url = session["_links"]["hpp:js"]["href"]
      # Redirect customer to redirect_url
  """

  alias Worldpay.{Client, Config}

  @doc """
  Create an HPP session (redirect / lightbox / pay-by-link).

  ## Key body fields

  - `instruction.value` — amount + currency (required)
  - `instruction.narrative` — statement descriptor
  - `resultUrls` — successUrl, failureUrl, cancelUrl
  - `expiry` — ISO 8601 duration e.g. `"PT1H"` (1 hour); for pay-by-link
  - `locale` — language/locale e.g. `"en-GB"`, `"fr-FR"`
  - `hostedCustomization` — CSS property overrides
  - `hostedProperties` — HPP feature flags
  - `cancelOn.cvcNotMatched` — boolean (auto-cancel if CVC fails)
  - `orderReference` — merchant order reference
  """
  @spec create_session(map(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def create_session(body, %Config{} = config) do
    Client.post(
      "/hpp/sessions",
      body,
      [api: :hpp, operation: :create_session],
      config
    )
  end

  @doc "Retrieve an HPP session."
  @spec get_session(String.t(), Config.t()) :: {:ok, map()} | {:error, Worldpay.Error.t()}
  def get_session(session_id, %Config{} = config) do
    Client.get(
      "/hpp/sessions/#{session_id}",
      [api: :hpp, operation: :get_session],
      config
    )
  end

  @doc """
  Create a pay-by-link URL.

  Sets a long expiry duration so the link can be shared via email/SMS.
  Returns the shareable URL from the response's `_links.hpp:payByLink.href`.

  ## Options

  - `:expiry` — ISO 8601 duration (default `"P7D"` — 7 days)
  - `:locale` — language e.g. `"en-GB"`
  """
  @spec pay_by_link(map(), Config.t(), keyword()) ::
          {:ok, String.t()} | {:error, Worldpay.Error.t()}
  def pay_by_link(body, %Config{} = config, opts \\ []) do
    expiry = Keyword.get(opts, :expiry, "P7D")
    locale = Keyword.get(opts, :locale)

    body =
      body
      |> Map.put("expiry", expiry)
      |> maybe_put("locale", locale)

    case create_session(body, config) do
      {:ok, session} ->
        link =
          get_in(session, ["_links", "hpp:payByLink", "href"]) ||
            get_in(session, ["_links", "hpp:js", "href"])

        {:ok, link}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Build HPP customization options for `hostedCustomization` field.

  ## Options

  - `:background_color` — CSS color value
  - `:button_color` — primary button color
  - `:font_family` — CSS font family
  - `:logo_url` — URL to merchant logo
  - `:header_text` — checkout page header text
  """
  @spec customization(keyword()) :: %{String.t() => term()}
  def customization(opts \\ []) do
    %{}
    |> maybe_put("backgroundColor", Keyword.get(opts, :background_color))
    |> maybe_put("buttonColor", Keyword.get(opts, :button_color))
    |> maybe_put("fontFamily", Keyword.get(opts, :font_family))
    |> maybe_put("logoUrl", Keyword.get(opts, :logo_url))
    |> maybe_put("headerText", Keyword.get(opts, :header_text))
  end

  @doc """
  Build HPP properties flags for `hostedProperties` field.

  ## Options (all boolean)

  - `:save_card` — show save card option (default false)
  - `:billing_address` — collect billing address
  - `:shipping_address` — collect shipping address
  - `:customer_email` — collect customer email
  - `:show_order_summary` — show order line items
  """
  @spec properties(keyword()) :: %{String.t() => term()}
  def properties(opts \\ []) do
    %{}
    |> maybe_put("saveCard", Keyword.get(opts, :save_card))
    |> maybe_put("billingAddress", Keyword.get(opts, :billing_address))
    |> maybe_put("shippingAddress", Keyword.get(opts, :shipping_address))
    |> maybe_put("customerEmail", Keyword.get(opts, :customer_email))
    |> maybe_put("showOrderSummary", Keyword.get(opts, :show_order_summary))
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v) when is_binary(k), do: Map.put(map, k, v)
end
