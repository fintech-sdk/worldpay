# Worldpay

Full-featured Elixir hex package for the [Worldpay payment platform](https://docs.worldpay.com/apis).

Covers all **45 APIs and products** across Access REST APIs, WPG XML gateway,
cnpAPI (US eCommerce), Marketplace onboarding, Payouts, FraudSight, 3DS, and more.

## Features

- ✅ **Payments API** — orchestrated (FraudSight + 3DS + token + auth in one call)
- ✅ **Card Payments API** — modular CITs, MITs, partial auth, AFTs, PayFac, Level 2/3
- ✅ **28 APMs** — iDEAL, PayPal, Klarna, BLIK, Pix, ACH, SEPA, Swish, Open Banking, and more
- ✅ **3DS API** — web, iOS, Android SDK flows; CB extras; authenticationOutage exemption
- ✅ **FraudSight** — standalone and embedded; ML risk assessment; SCA exemption (TRA)
- ✅ **Exemptions API** — TRA, low-value, trusted beneficiary, authenticationOutage
- ✅ **Tokens API** — Worldpay tokens + Visa/MC network tokens (NPTs) + cryptograms
- ✅ **Card Payouts** — Fast Access (≤30 min), basic disbursement, Apple Pay wallet payouts
- ✅ **Account Payouts** — push funds to bank accounts; BAV verification
- ✅ **Money Transfers (OCTs)** — original credit transactions
- ✅ **FX API** — rate pairings, quotes, forward rates, payout live rate
- ✅ **Marketplace APIs** — Parties, KYC, beneficial owners, balance accounts, split payments
- ✅ **Payment Queries** — date range, reference, paymentId lookups
- ✅ **Card BIN API** — v1 + v2; funding type, DCC eligibility, co-badge brands
- ✅ **Verifications** — card verification + Beneficiary Account Verification (BAV)
- ✅ **Account Updater** — real-time (Visa) + file-based batch helpers
- ✅ **WPG** — full XML gateway: Direct, HPP, Direct Elements, split funding, 3DS2, DCC
- ✅ **cnpAPI** — US eCommerce: auth, sale, credit, void, capture, eCheck, Dynamic Payout, FraudSight, Level 2/3, Lodging
- ✅ **Webhooks** — parse and dispatch all 25+ lifecycle events
- ✅ **Telemetry** — `:telemetry` spans on every API call
- ✅ **Circuit breaker** — via `:fuse`; per-API protection
- ✅ **Idempotency** — automatic key generation on all mutations
- ✅ **HATEOAS** — action link helpers; href resolution on settle/cancel

## Installation

```elixir
def deps do
  [{:worldpay, "~> 1.0"}]
end
```

## Configuration

```elixir
# config/runtime.exs
import Config

config :worldpay,
  username: System.fetch_env!("WORLDPAY_USERNAME"),
  password: System.fetch_env!("WORLDPAY_PASSWORD"),
  environment: :try,                    # :try | :live
  api_version: "2025-01-01",
  wpg_merchant_code: System.get_env("WORLDPAY_WPG_MERCHANT_CODE"),
  wpg_username: System.get_env("WORLDPAY_WPG_USERNAME"),
  wpg_password: System.get_env("WORLDPAY_WPG_PASSWORD"),
  cnp_merchant_id: System.get_env("WORLDPAY_CNP_MERCHANT_ID"),
  cnp_user: System.get_env("WORLDPAY_CNP_USER"),
  cnp_password: System.get_env("WORLDPAY_CNP_PASSWORD"),
  timeout: 30_000,
  retry_count: 3,
  circuit_breaker: true
```

## Quick start

### Card payment (Payments API)

```elixir
config = Worldpay.Config.new()

{:ok, auth} =
  Worldpay.authorize(%{
    "transactionReference" => "order-001",
    "merchant" => %{"entity" => "default"},
    "instruction" => %{
      "narrative" => %{"line1" => "My Store"},
      "value" => %{"amount" => 1999, "currency" => "GBP"},
      "paymentInstrument" => %{
        "type" => "card/plain",
        "cardHolderName" => "Jane Doe",
        "cardNumber" => "4444333322221111",
        "cardExpiryDate" => %{"month" => 5, "year" => 2035},
        "cvc" => "123"
      }
    }
  }, config)

payment_id = auth["paymentId"]

{:ok, _} = Worldpay.settle(payment_id, config)
{:ok, _} = Worldpay.refund(payment_id, config)
```

### APM payment — iDEAL

```elixir
{:ok, result} =
  Worldpay.APMs.pay(%{
    "transactionReference" => "order-002",
    "merchant" => %{"entity" => "default"},
    "instruction" => %{
      "value" => %{"amount" => 1500, "currency" => "EUR"},
      "paymentInstrument" => Worldpay.APMs.ideal(),
      "narrative" => %{"line1" => "My Store"}
    },
    "resultUrls" => %{
      "successUrl" => "https://example.com/success",
      "cancelUrl" => "https://example.com/cancel"
    }
  }, config)
```

### Full 3DS flow

```elixir
# 1. Device data collection
{:ok, ddc} = Worldpay.ThreeDS.device_data(session_href, config)
# → embed ddc["_links"]["3ds:deviceDataCollection"]["href"] in iFrame

# 2. Authenticate
{:ok, auth} = Worldpay.ThreeDS.authenticate(auth_body, config)
threeDS = Worldpay.ThreeDS.build_auth_object(auth)

# 3. Authorize with 3DS result
{:ok, payment} =
  Worldpay.CardPayments.authorize(
    Map.put(instruction, "threeDS", threeDS),
    config
  )
```

### MIT subscription

```elixir
# First payment stores token + scheme reference
{:ok, first} = Worldpay.CardPayments.authorize(cit_body, config)
token_href = get_in(first, ["instruction", "paymentInstrument", "href"])
scheme_ref = first["schemeReference"]

# Subsequent MITs
body = Worldpay.CardPayments.build_mit(
  transaction_reference: "sub-002",
  narrative: "Monthly Plan",
  amount: 999,
  currency: "USD",
  payment_instrument: %{"type" => "card/token", "href" => token_href},
  scheme_reference: scheme_ref
)
{:ok, _} = Worldpay.CardPayments.mit(body, config)
```

### Marketplace — split payment

```elixir
# 1. Onboard seller
{:ok, party} = Worldpay.Marketplaces.Parties.create(party_body, config)

# 2. Authorize payment
{:ok, auth} = Worldpay.CardPayments.authorize(payment_body, config)

# 3. Settle
{:ok, _} = Worldpay.CardPayments.settle(auth["paymentId"], config)

# 4. Split
{:ok, _} =
  Worldpay.Marketplaces.SplitPayments.split(%{
    "merchant" => %{"entity" => "default"},
    "paymentId" => auth["paymentId"],
    "splits" => [
      %{"type" => "marketplace", "amount" => %{"value" => 8500, "currency" => "GBP"}, "partyId" => party["partyId"]},
      %{"type" => "fee",         "amount" => %{"value" => 1500, "currency" => "GBP"}, "partyId" => "platform-party"}
    ]
  }, config)
```

### Webhook handler

```elixir
# In your Phoenix controller:
def handle(conn, _params) do
  {:ok, body, conn} = Plug.Conn.read_body(conn)

  case Worldpay.Webhooks.parse(body) do
    {:ok, event} ->
      MyApp.PaymentEvents.handle_event(event)
      send_resp(conn, 200, "ok")

    {:error, reason} ->
      send_resp(conn, 400, "bad request")
  end
end

# Your handler module:
defmodule MyApp.PaymentEvents do
  @behaviour Worldpay.Webhooks.Handler

  @impl true
  def handle_event(%{type: :authorized, payment_id: id}), do: Orders.mark_authorized(id)
  def handle_event(%{type: :settled, payment_id: id}),    do: Orders.mark_settled(id)
  def handle_event(%{type: :charged_back} = event),       do: Disputes.open(event)
  def handle_event(_event), do: :ok
end
```

### WPG Direct

```elixir
xml =
  Worldpay.WPG.Builder.order(
    order_code: "wpg-001",
    amount: 1999,
    currency: "GBP",
    card_number: "4444333322221111",
    exp_month: "05",
    exp_year: "2035",
    card_holder: "Jane Doe",
    cvc: "123"
  )
  |> Worldpay.WPG.Builder.envelope(merchant_code: config.wpg_merchant_code)

{:ok, response} = Worldpay.WPG.submit(xml, config)
Worldpay.WPG.Parser.last_event(response)  # => "AUTHORISED"
```

### cnpAPI (US eCommerce)

```elixir
{:ok, result} =
  Worldpay.CNP.sale([
    id: "txn-001",
    order_id: "order-001",
    amount: 1999,
    card: %{
      number: "4444333322221111",
      exp_month: 5,
      exp_year: 2035,
      type: "VI",
      cvc: "123"
    }
  ], config)

Worldpay.CNP.Parser.approved?(result)   # => true
Worldpay.CNP.Parser.txn_id(result)      # => "82737588000000"
```

## Telemetry

Attach handlers to monitor every API call:

```elixir
:telemetry.attach_many(
  "worldpay-logger",
  [
    [:worldpay, :request, :start],
    [:worldpay, :request, :stop],
    [:worldpay, :request, :exception]
  ],
  &Worldpay.Telemetry.log_handler/4,
  nil
)
```

## Module reference

| Module | Purpose |
|---|---|
| `Worldpay` | Top-level facade + convenience delegates |
| `Worldpay.Payments` | Orchestrated Payments API |
| `Worldpay.CardPayments` | Modular Card Payments API |
| `Worldpay.APMs` | 28 Alternative Payment Methods |
| `Worldpay.ThreeDS` | 3DS Authentication |
| `Worldpay.FraudSight` | ML fraud risk assessment |
| `Worldpay.Exemptions` | SCA exemptions |
| `Worldpay.Tokens` | Worldpay + Network tokens |
| `Worldpay.CardPayouts` | Card payouts (Fast Access) |
| `Worldpay.AccountPayouts` | Bank account payouts |
| `Worldpay.MoneyTransfers` | OCT money transfers |
| `Worldpay.FX` | Foreign exchange / MCP |
| `Worldpay.AccountTransfers` | Internal account transfers |
| `Worldpay.Balances` | Balance enquiry |
| `Worldpay.Statements` | Settlement statements |
| `Worldpay.PaymentQueries` | Query payment history |
| `Worldpay.CardBIN` | BIN lookup v1 + v2 |
| `Worldpay.Verifications` | Card + BAV verification |
| `Worldpay.AccountUpdater` | Account updater batch helpers |
| `Worldpay.Marketplaces.Parties` | Party onboarding + KYC |
| `Worldpay.Marketplaces.SplitPayments` | Split payments |
| `Worldpay.WPG` | WPG XML gateway |
| `Worldpay.WPG.Builder` | WPG XML builder |
| `Worldpay.WPG.Parser` | WPG XML parser |
| `Worldpay.CNP` | cnpAPI US eCommerce |
| `Worldpay.CNP.Builder` | cnpAPI XML builder |
| `Worldpay.CNP.Parser` | cnpAPI XML parser |
| `Worldpay.Webhooks` | Webhook parsing + dispatch |
| `Worldpay.Config` | Runtime configuration |
| `Worldpay.Error` | Structured error type |
| `Worldpay.Telemetry` | Telemetry spans |

## License

MIT
