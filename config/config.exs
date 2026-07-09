import Config

# Default application configuration.
# Override in environment-specific files or via runtime.exs.
config :worldpay,
  environment: :try,
  api_version: "2025-01-01",
  timeout: 30_000,
  retry_count: 3,
  circuit_breaker: true

import_config "#{config_env()}.exs"
