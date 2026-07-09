defmodule Worldpay.Application do
  @moduledoc false
  use Application

  alias Worldpay.Config

  @default_express_url "https://certtransaction.elementexpress.com"
  @default_cnp_url "https://payments.vantivprelive.com"

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: Worldpay.Finch, pools: finch_pools()},
      Worldpay.Telemetry
    ]

    opts = [strategy: :one_for_one, name: Worldpay.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp finch_pools do
    access_url = resolve_url(:base_url, Config.default_access_url())
    wpg_url = resolve_url(:wpg_base_url, Config.default_wpg_url())
    express_url = Application.get_env(:worldpay, :express_url, @default_express_url)
    cnp_url = Application.get_env(:worldpay, :cnp_url, @default_cnp_url)

    %{
      access_url => [size: 10, count: 1],
      wpg_url => [size: 5, count: 1],
      express_url => [size: 5, count: 1],
      cnp_url => [size: 5, count: 1]
    }
  end

  defp resolve_url(key, default) do
    Application.get_env(:worldpay, key, default)
  end
end
