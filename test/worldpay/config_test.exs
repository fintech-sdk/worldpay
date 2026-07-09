defmodule Worldpay.ConfigTest do
  use ExUnit.Case, async: true

  alias Worldpay.Config
  alias Worldpay.Factory

  describe "new/1" do
    test "defaults to try environment" do
      config = Config.new(username: "u", password: "p")
      assert config.environment == :try
      assert config.base_url == "https://try.access.worldpay.com"
    end

    test "sets live URLs when environment is :live" do
      config = Config.new(username: "u", password: "p", environment: :live)
      assert config.base_url == "https://access.worldpay.com"
      assert config.wpg_base_url == "https://secure.worldpay.com"
    end

    test "api_version defaults to 2025-01-01" do
      config = Config.new(username: "u", password: "p")
      assert config.api_version == "2025-01-01"
    end

    test "overrides apply correctly" do
      config = Config.new(username: "custom-user", password: "custom-pass", timeout: 5_000)
      assert config.username == "custom-user"
      assert config.password == "custom-pass"
      assert config.timeout == 5_000
    end
  end

  describe "basic_auth/1" do
    test "returns base64 encoded credentials" do
      config = Config.new(username: "user", password: "pass")
      encoded = Config.basic_auth(config)
      assert encoded == Base.encode64("user:pass")
    end

    test "raises on missing credentials" do
      config = %Config{}

      assert_raise Worldpay.Error, fn ->
        Config.basic_auth(config)
      end
    end
  end

  describe "wpg_basic_auth/1" do
    test "returns base64 encoded WPG credentials" do
      config = Config.new(wpg_username: "wpg-user", wpg_password: "wpg-pass")
      encoded = Config.wpg_basic_auth(config)
      assert encoded == Base.encode64("wpg-user:wpg-pass")
    end
  end
end
