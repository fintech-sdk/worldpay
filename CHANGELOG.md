# Changelog

All notable changes to the `worldpay` Elixir hex package are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [1.0.0] — 2026-06-25

### Added

**Access REST APIs**
- `Worldpay.Payments` — Orchestrated Payments API: card/plain, card/checkout, card/token, card/networkToken, Apple Pay, Google Pay; auto-settlement; ACP (Agentic Commerce Protocol)
- `Worldpay.CardPayments` — Modular Card Payments API: CIT, MIT (subscription/installment/unscheduled), partial auth, fast refunds, AFTs, PayFac, Level 2/3, airline data, MOTO, co-badged routing, account updater, South Korea domestic, LatAm installments, MCC 6012/6051
- `Worldpay.APMs` — 28 Alternative Payment Methods: iDEAL, PayPal, Klarna, Klarna recurring, BLIK, Pix, ACH, SEPA, Swish, Open Banking, MyBank, Multibanco, Przelewy24, BANCOMAT Pay, Euteller, Konbini, SafetyPay, PaysafeCard, WeChat Pay, Toss Pay, Trustly, Bancontact, Bizum, Alipay, Alipay HK, Alipay+, Canadian EFT, UnionPay; partial reverse, partial settle, requestExpired event
- `Worldpay.ThreeDS` — 3DS API: web (Cardinal JS), iOS SDK, Android SDK; device data collection; challenged/authenticated/unAuthenticated/authenticationOutage outcomes; CB extras; `build_auth_object/1` convenience helper; ACP/Google Pay 3DS (Jun 2026)
- `Worldpay.FraudSight` — ML risk assessment; SCA exemption (TRA) in same call; Apple Pay + Google Pay support; outcome update for 3rd-party gateways; `assess_and_extract_href/2`
- `Worldpay.Exemptions` — Standalone SCA exemptions: TRA, lowValue, trustedBeneficiary, authenticationOutage
- `Worldpay.Tokens` — Worldpay tokens (create, get, update, delete, detokenize); Network tokens/NPTs (provision, get, delete, cryptogram provisioning); namespace scoping; PAR support
- `Worldpay.Verifications` — Card verification (intelligent, dynamic cardOnFile); Beneficiary Account Verification (BAV v2025-01-01); inReview outcome
- `Worldpay.CardBIN` — BIN lookup v1 + v2; funding type, DCC eligibility, co-badge brands, anonymousPrepaid, multipleAccountAccess
- `Worldpay.AccountUpdater` — Real-time (Visa); file-based batch XML helpers (card, token, batch envelope)
- `Worldpay.PaymentQueries` — Date range, transactionReference, paymentId, historical (pre-Jun 2024)

**Payouts**
- `Worldpay.CardPayouts` — Basic disbursement; Fast Access (≤30 min, Mastercard Send v4+); wallet payouts; Apple Pay MITs; fallback to basic option; 31-day search
- `Worldpay.AccountPayouts` — Bank account payouts; channel/routedChannel; estimatedSettlementDate in webhook; BAV integration
- `Worldpay.MoneyTransfers` — OCT original credit transactions; wallet unload; gaming payouts
- `Worldpay.FX` — Rate pairings; FX quotes; forward rate locking; PAYOUT LIVE RATE intent (Mar 2025)
- `Worldpay.AccountTransfers` — Internal fund transfers between virtual balance accounts
- `Worldpay.Balances` — Balance enquiry on virtual accounts
- `Worldpay.Statements` — Settlement deposit summaries

**Marketplace**
- `Worldpay.Marketplaces.Parties` — Party create/get/update; payout instruments; balance accounts; beneficial owners (CRUD); KYC identity verification; orchestrated + modular flows; US SSN support
- `Worldpay.Marketplaces.SplitPayments` — Split settled payment across balance accounts; split refunds; fee/commission deductions; v2025-06-25

**WPG (Legacy XML Gateway)**
- `Worldpay.WPG` — Submit, authorize, capture, cancel, refund, inquiry convenience wrappers
- `Worldpay.WPG.Builder` — Direct order, token order, HPP order, capture, cancel, refund, inquiry, 3DS2 auth, split funding, Level 2/3 enhanced data, installment data
- `Worldpay.WPG.Parser` — XML → map parser using `:xmerl`; `last_event/1`, `order_code/1`, `risk_score/1` extractors

**cnpAPI (US eCommerce)**
- `Worldpay.CNP` — sale, authorization, capture, credit, void, reversal, echeck_sale, echeck_void, echeck_credit, register_token, funding_instruction
- `Worldpay.CNP.Builder` — XML builders for all transaction types; Dynamic Payout funding instructions; Level 2/3 enhanced data; lodging info; stored credentials; FraudSight webSessionId; customer info
- `Worldpay.CNP.Parser` — XML → map parser; `approved?/1`, `response_code/1`, `txn_id/1`, `fraud_results/1`

**Events & Webhooks**
- `Worldpay.Webhooks` — Parse all 25+ lifecycle events; `Worldpay.Webhooks.Handler` behaviour; APM vs card event discrimination; payout events; token events; Pix events; `handle/2` dispatcher

**Infrastructure**
- `Worldpay.Config` — Runtime config with env var overrides; 12-factor compliant; try/live URL derivation; Basic Auth encoding
- `Worldpay.Error` — Structured error with type, status, reason, message, custom_code, validation_errors, raw body
- `Worldpay.Telemetry` — `[:worldpay, :request, :start/stop/exception]` spans; structured logger handler
- `Worldpay.Client` — Req-based HTTP client; WP-Api-Version header; idempotency keys; WP-CorrelationId; HATEOAS href resolution; circuit breaker (`:fuse`); XML client for WPG
- Worldpay.Application — OTP supervisor; Finch connection pools (Access + WPG)

**Schemas**
- `Worldpay.Schema.Amount` — `value` + `currency`
- `Worldpay.Schema.Address` — billing/shipping address; nil-dropping serialization
- `Worldpay.Schema.Narrative` — statement line1/line2
- `Worldpay.Schema.Merchant` — entity + optional MCC + PayFac object
- `Worldpay.Schema.CustomerAgreement` — cardOnFile/subscription/installment/unscheduled; storedCardUsage; schemeReference
- `Worldpay.Schema.ThreeDS` — eci, authenticationValue, transactionId, version, challengePreference
- `Worldpay.Schema.FundsTransfer` — AFT type, purpose, sender, recipient
- `Worldpay.Schema.PaymentInstrument` — all 7 instrument types with type-safe serialization

**Tests**
- Bypass-based HTTP integration tests for all Access APIs
- Unit tests for all schema modules, Config, Error, Webhooks, WPG Builder/Parser, cnpAPI Builder/Parser
- `Worldpay.Factory` test data factory
- Async test suite throughout

[1.0.0]: https://github.com/your-org/worldpay/releases/tag/v1.0.0
