import Config

# Runtime configuration — reads from environment variables at startup.
# This file is evaluated at runtime, not compile time.
#
# All Worldpay credentials MUST be supplied via environment variables
# in production. Never hardcode credentials.

if config_env() in [:prod, :try] do
  config :worldpay,
    username: System.fetch_env!("WORLDPAY_USERNAME"),
    password: System.fetch_env!("WORLDPAY_PASSWORD"),
    environment: if(System.get_env("WORLDPAY_ENVIRONMENT") == "live", do: :live, else: :try),
    api_version: System.get_env("WORLDPAY_API_VERSION", "2025-01-01"),
    wpg_merchant_code: System.get_env("WORLDPAY_WPG_MERCHANT_CODE"),
    wpg_username: System.get_env("WORLDPAY_WPG_USERNAME"),
    wpg_password: System.get_env("WORLDPAY_WPG_PASSWORD"),
    cnp_merchant_id: System.get_env("WORLDPAY_CNP_MERCHANT_ID"),
    cnp_user: System.get_env("WORLDPAY_CNP_USER"),
    cnp_password: System.get_env("WORLDPAY_CNP_PASSWORD"),
    timeout: String.to_integer(System.get_env("WORLDPAY_TIMEOUT", "30000")),
    circuit_breaker: System.get_env("WORLDPAY_CIRCUIT_BREAKER", "true") == "true"
end
