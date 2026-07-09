defmodule Worldpay.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/fintech-sdk/worldpay"

  def project do
    [
      app: :worldpay,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Hex package
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,

      # Docs
      name: "Worldpay",
      docs: docs(),

      # Test
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:error_handling, :underspecs]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :xmerl],
      mod: {Worldpay.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # HTTP client
      {:req, "~> 0.5"},

      # JSON
      {:jason, "~> 1.4"},

      # Telemetry
      {:telemetry, "~> 1.2"},

      # Retry / circuit breaker
      {:fuse, "~> 2.4"},

      # Connection pooling via Finch (used by Req)
      {:finch, "~> 0.18"},

      # Dev / test
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end

  defp description do
    "Full-featured Elixir client for the Worldpay payment platform — Access APIs, WPG, " <>
      "RAFT, APMs, Marketplaces, Payouts, FraudSight, 3DS, Tokens and more."
  end

  defp package do
    [
      name: "worldpay",
      maintainers: ["Your Org"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Worldpay Developer Docs" => "https://docs.worldpay.com/apis"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        Core: [Worldpay, Worldpay.Client, Worldpay.Config, Worldpay.Application],
        "Access — Payments": [
          Worldpay.Payments,
          Worldpay.CardPayments,
          Worldpay.APMs
        ],
        "Access — Auth & Risk": [
          Worldpay.ThreeDS,
          Worldpay.FraudSight,
          Worldpay.Exemptions,
          Worldpay.Verifications
        ],
        "Access — Tokens": [
          Worldpay.Tokens,
          Worldpay.NetworkTokens
        ],
        "Access — Payouts": [
          Worldpay.CardPayouts,
          Worldpay.AccountPayouts,
          Worldpay.MoneyTransfers,
          Worldpay.FX
        ],
        "Access — Data": [
          Worldpay.PaymentQueries,
          Worldpay.Events,
          Worldpay.CardBIN,
          Worldpay.AccountUpdater
        ],
        "Access — Finance": [
          Worldpay.AccountTransfers,
          Worldpay.Balances,
          Worldpay.Statements
        ],
        Marketplace: [
          Worldpay.Marketplaces.Parties,
          Worldpay.Marketplaces.SplitPayments
        ],
        "WPG (Legacy Gateway)": [
          Worldpay.WPG,
          Worldpay.WPG.Builder,
          Worldpay.WPG.Parser
        ],
        Schemas: [
          Worldpay.Schema.Amount,
          Worldpay.Schema.PaymentInstrument,
          Worldpay.Schema.Address,
          Worldpay.Schema.Merchant,
          Worldpay.Schema.CustomerAgreement,
          Worldpay.Schema.ThreeDS,
          Worldpay.Schema.FundsTransfer,
          Worldpay.Schema.Narrative
        ],
        Errors: [Worldpay.Error],
        Telemetry: [Worldpay.Telemetry]
      ]
    ]
  end
end
