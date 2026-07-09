import Config

# Configure Worldpay for test environment
config :worldpay,
  username: "test-user",
  password: "test-password",
  environment: :try,
  api_version: "2025-01-01",
  wpg_merchant_code: "TESTMERCHANT",
  wpg_username: "wpg-test-user",
  wpg_password: "wpg-test-pass",
  cnp_merchant_id: "test-merchant",
  cnp_user: "cnp-test",
  cnp_password: "cnp-test-pass",
  timeout: 5_000,
  circuit_breaker: false
