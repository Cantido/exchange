defmodule Exchange.Orderbook.TradeProjector do
  use Commanded.Projections.Ecto,
    application: Exchange.Commanded,
    repo: Exchange.Repo,
    name: "TradeProjector"
  alias Exchange.Orderbook.TradeExecuted
  alias Exchange.Orderbook.Schema.Trade
  alias Exchange.Repo

  project %TradeExecuted{} = event, fn multi ->
    {:ok, ts, _} = DateTime.from_iso8601(event.timestamp)
    projection =
      %Trade{
        symbol: event.symbol,
        sell_order_id: event.sell_order_id,
        buy_order_id: event.buy_order_id,
        price: event.price,
        quantity: event.quantity,
        maker: String.to_existing_atom(event.maker),
        executed_at: ts
      }

    Ecto.Multi.insert(multi, :trade_projection, projection)
  end
end
