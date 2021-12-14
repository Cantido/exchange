defmodule Exchange.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Exchange.Repo,
      Exchange.Commanded,
      Exchange.OrderPlacement,
      Exchange.Orderbook.TradeProjector,
      Exchange.Orderbook.OrderProjector,
      Exchange.Orderbook.SymbolProjector,
      ExchangeWeb.Telemetry,
      {Phoenix.PubSub, name: Exchange.PubSub},
      ExchangeWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Exchange.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    ExchangeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
