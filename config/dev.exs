import Config

# Development config.
# Credentials should be set in config/dev.secret.exs (git-ignored).
# Example:
#
#   config :worldpay,
#     username: "your-try-username",
#     password: "your-try-password"
#
# Or export environment variables:
#   export WORLDPAY_USERNAME="..."
#   export WORLDPAY_PASSWORD="..."

if File.exists?("config/dev.secret.exs") do
  import_config "dev.secret.exs"
end
