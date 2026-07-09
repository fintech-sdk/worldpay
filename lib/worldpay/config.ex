defmodule Worldpay.Config do
  @moduledoc """
  Runtime configuration for the Worldpay client.

  ## Application config

      config :worldpay,
        username: "your-username",
        password: "your-password",
        environment: :try,
        api_version: "2025-01-01",
        wpg_merchant_code: "MYMERCHANT",
        wpg_username: "wpg-user",
        wpg_password: "wpg-pass",
        timeout: 30_000,
        retry_count: 3,
        circuit_breaker: true

  ## Environment variable overrides (take precedence)

  - `WORLDPAY_USERNAME`
  - `WORLDPAY_PASSWORD`
  - `WORLDPAY_ENVIRONMENT` — `"try"` or `"live"`
  - `WORLDPAY_API_VERSION`
  - `WORLDPAY_WPG_MERCHANT_CODE`
  - `WORLDPAY_WPG_USERNAME`
  - `WORLDPAY_WPG_PASSWORD`
  """

  alias Worldpay.Error

  @type environment :: :try | :live

  @type t :: %__MODULE__{
          username: String.t() | nil,
          password: String.t() | nil,
          environment: environment(),
          base_url: String.t(),
          wpg_base_url: String.t(),
          api_version: String.t(),
          wpg_merchant_code: String.t() | nil,
          wpg_username: String.t() | nil,
          wpg_password: String.t() | nil,
          timeout: non_neg_integer(),
          retry_count: non_neg_integer(),
          circuit_breaker: boolean()
        }

  defstruct [
    :username,
    :password,
    :wpg_merchant_code,
    :wpg_username,
    :wpg_password,
    environment: :try,
    base_url: "https://try.access.worldpay.com",
    wpg_base_url: "https://secure-test.worldpay.com",
    api_version: "2025-01-01",
    timeout: 30_000,
    retry_count: 3,
    circuit_breaker: true
  ]

  @try_url "https://try.access.worldpay.com"
  @live_url "https://access.worldpay.com"
  @wpg_try_url "https://secure-test.worldpay.com"
  @wpg_live_url "https://secure.worldpay.com"

  @doc "Default Access API base URL (try environment)."
  @spec default_access_url() :: String.t()
  def default_access_url, do: @try_url

  @doc "Default WPG base URL (try environment)."
  @spec default_wpg_url() :: String.t()
  def default_wpg_url, do: @wpg_try_url

  @doc """
  Build a `Config` from application env and environment variables.

  Environment variables take precedence over application config.
  The `overrides` keyword list takes the highest precedence.
  """
  @spec new(keyword()) :: t()
  def new(overrides \\ []) do
    app_env = Application.get_all_env(:worldpay)

    base =
      __MODULE__
      |> struct(app_env)
      |> apply_env_overrides()
      |> derive_urls()

    struct(base, overrides)
  end

  @doc "Encode Basic Auth header value for Access APIs."
  @spec basic_auth(t()) :: String.t()
  def basic_auth(%__MODULE__{username: u, password: p})
      when is_binary(u) and is_binary(p) do
    Base.encode64("#{u}:#{p}")
  end

  def basic_auth(%__MODULE__{}) do
    raise Error,
      type: :configuration_error,
      reason: :missing_credentials,
      message: "Worldpay username and password must be set"
  end

  @doc "Encode Basic Auth header value for WPG."
  @spec wpg_basic_auth(t()) :: String.t()
  def wpg_basic_auth(%__MODULE__{wpg_username: u, wpg_password: p})
      when is_binary(u) and is_binary(p) do
    Base.encode64("#{u}:#{p}")
  end

  def wpg_basic_auth(%__MODULE__{}) do
    raise Error,
      type: :configuration_error,
      reason: :missing_wpg_credentials,
      message: "Worldpay WPG username and password must be set"
  end

  # ── private ─────────────────────────────────────────────────────────────

  @spec apply_env_overrides(t()) :: t()
  defp apply_env_overrides(cfg) do
    cfg
    |> maybe_override(:username, System.get_env("WORLDPAY_USERNAME"))
    |> maybe_override(:password, System.get_env("WORLDPAY_PASSWORD"))
    |> maybe_override_env(System.get_env("WORLDPAY_ENVIRONMENT"))
    |> maybe_override(:api_version, System.get_env("WORLDPAY_API_VERSION"))
    |> maybe_override(:wpg_merchant_code, System.get_env("WORLDPAY_WPG_MERCHANT_CODE"))
    |> maybe_override(:wpg_username, System.get_env("WORLDPAY_WPG_USERNAME"))
    |> maybe_override(:wpg_password, System.get_env("WORLDPAY_WPG_PASSWORD"))
  end

  @spec derive_urls(t()) :: t()
  defp derive_urls(%__MODULE__{environment: :live} = cfg) do
    %{cfg | base_url: @live_url, wpg_base_url: @wpg_live_url}
  end

  defp derive_urls(%__MODULE__{environment: :try} = cfg) do
    %{cfg | base_url: @try_url, wpg_base_url: @wpg_try_url}
  end

  # Narrow: value is always String.t() | nil from System.get_env/1.
  @spec maybe_override(t(), atom(), String.t() | nil) :: t()
  defp maybe_override(cfg, _key, nil), do: cfg
  defp maybe_override(cfg, _key, ""), do: cfg
  defp maybe_override(cfg, key, val) when is_binary(val), do: Map.put(cfg, key, val)

  # Narrowed to the exact arity and input shape used: no key arg, env string or nil.
  @spec maybe_override_env(t(), String.t() | nil) :: t()
  defp maybe_override_env(cfg, nil), do: cfg
  defp maybe_override_env(cfg, "live"), do: %{cfg | environment: :live}
  defp maybe_override_env(cfg, _other), do: %{cfg | environment: :try}
end
