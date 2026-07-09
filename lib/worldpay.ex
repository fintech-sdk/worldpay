defmodule Worldpay do
  @moduledoc """
  **Worldpay** — Complete Elixir client for the Worldpay payment platform.

  Covers all 45+ APIs: Access REST, WPG XML, cnpAPI, RAFT, Express,
  Marketplace, Payouts, FraudSight, 3DS, Tokens, and Reporting.

  ## Module map

  ### Access APIs (modern REST)
  | Module | Purpose |
  |---|---|
  | `Worldpay.Payments` | Orchestrated Payments API |
  | `Worldpay.CardPayments` | Modular Card Payments API |
  | `Worldpay.CardPayments.Features` | Advanced features: partial auth, AFT, L2/3, airline, MOTO, LatAm, ACP |
  | `Worldpay.APMs` | 28 Alternative Payment Methods |
  | `Worldpay.ThreeDS` | 3DS Authentication |
  | `Worldpay.FraudSight` | ML fraud risk assessment |
  | `Worldpay.Exemptions` | SCA exemption requests |
  | `Worldpay.Tokens` | Worldpay tokens + NPTs + cryptograms |
  | `Worldpay.NetworkPaymentTokens` | Cross-acquirer NPT management |
  | `Worldpay.CustomerEventService` | NPT lifecycle event webhooks |
  | `Worldpay.SecurityTokenService` | Provision / exchange / detokenize raw PANs |
  | `Worldpay.ForwardAPI` | PCI-scope-reducing proxy |
  | `Worldpay.TokenImport` | Migrate tokens from previous providers |
  | `Worldpay.CardPayouts` | Card payouts (Fast Access ≤30 min) |
  | `Worldpay.AccountPayouts` | Bank account payouts |
  | `Worldpay.MoneyTransfers` | OCT money transfers |
  | `Worldpay.FX` | Foreign exchange / MCP |
  | `Worldpay.AccountTransfers` | Internal account transfers |
  | `Worldpay.Balances` | Balance enquiry |
  | `Worldpay.Statements` | Settlement statements |
  | `Worldpay.PaymentQueries` | Query payment history |
  | `Worldpay.CardBIN` | BIN lookup v1 + v2 |
  | `Worldpay.Verifications` | Card + BAV verification |
  | `Worldpay.AccountUpdater` | Account updater helpers |
  | `Worldpay.HPP` | Hosted Payment Page + pay-by-link |
  | `Worldpay.Reporting.BatchTransactions` | Batch Transaction API |

  ### Marketplace
  | Module | Purpose |
  |---|---|
  | `Worldpay.Marketplaces.Parties` | Party onboarding + KYC + beneficial owners |
  | `Worldpay.Marketplaces.SplitPayments` | Split payments + split refunds |

  ### WPG (XML Gateway)
  | Module | Purpose |
  |---|---|
  | `Worldpay.WPG` | WPG client + convenience wrappers |
  | `Worldpay.WPG.Builder` | XML builders (Direct, HPP, 3DS2, split funding) |
  | `Worldpay.WPG.Parser` | XML → map parser |
  | `Worldpay.WPG.Features` | DCC, Guaranteed Payments, Prime Routing, Lodging, MAC, JSC, etc. |

  ### cnpAPI (US eCommerce)
  | Module | Purpose |
  |---|---|
  | `Worldpay.CNP` | cnpAPI REST client |
  | `Worldpay.CNP.Builder` | XML builders |
  | `Worldpay.CNP.Parser` | XML → map parser |

  ### RAFT / In-Store
  | Module | Purpose |
  |---|---|
  | `Worldpay.RAFT` | ISO 8583 610 interface: all card-present types |
  | `Worldpay.RAFT.Response` | Response field extractors |
  | `Worldpay.Express` | Express Interface (lighter POS integration) |

  ### Partner
  | Module | Purpose |
  |---|---|
  | `Worldpay.Partner.Boarding` | Merchant boarding API |
  | `Worldpay.Partner.LeadSubmission` | Lead submission to Salesforce |
  | `Worldpay.Partner.Notifications` | Transaction notification parser |
  | `Worldpay.Partner.TerminalLease` | Terminal lease notification parser |

  ### Reporting
  | Module | Purpose |
  |---|---|
  | `Worldpay.Reporting.EMAF` | eMAF daily settlement file parser |
  | `Worldpay.Reporting.BatchTransactions` | Batch Transaction API |
  | `Worldpay.Reporting.CNPBatch` | cnpAPI batch file builder + completion parser |

  ### Infrastructure
  | Module | Purpose |
  |---|---|
  | `Worldpay.Webhooks` | Payment lifecycle event parsing + dispatch |
  | `Worldpay.Config` | Runtime configuration |
  | `Worldpay.Error` | Structured error type |
  | `Worldpay.Telemetry` | Telemetry spans |
  | `Worldpay.Client` | HTTP client (Req + Finch + circuit breaker) |
  """

  alias Worldpay.{CardPayments, Config, Payments}

  # ── Top-level convenience delegates ──────────────────────────────────────

  @doc "Authorize via Payments API (orchestrated). See `Worldpay.Payments.authorize/3`."
  defdelegate authorize(instruction, config, opts \\ []), to: Payments

  @doc "Settle a payment. See `Worldpay.CardPayments.settle/3`."
  defdelegate settle(payment_id, config, opts \\ []), to: CardPayments

  @doc "Cancel an authorization. See `Worldpay.CardPayments.cancel/3`."
  defdelegate cancel(payment_id, config, opts \\ []), to: CardPayments

  @doc "Full refund. See `Worldpay.CardPayments.refund/3`."
  defdelegate refund(payment_id, config, opts \\ []), to: CardPayments

  @doc "Partial refund. See `Worldpay.CardPayments.partial_refund/5`."
  defdelegate partial_refund(payment_id, amount, currency, config, opts \\ []), to: CardPayments

  @doc "Query payment events. See `Worldpay.CardPayments.events/2`."
  defdelegate events(payment_id, config), to: CardPayments

  @doc "Build a default `Config.t()` from application env."
  @spec config() :: Config.t()
  def config, do: Config.new()

  @doc "Return the library version."
  @spec version() :: String.t()
  def version, do: to_string(Application.spec(:worldpay, :vsn))
end
