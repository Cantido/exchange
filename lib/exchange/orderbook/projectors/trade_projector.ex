defmodule Exchange.Orderbook.TradeProjector do
  use Commanded.Projections.Ecto,
    application: Exchange.Commanded,
    repo: Exchange.Repo,
    name: "TradeProjector"
  alias Exchange.Orderbook.TradeExecuted
  alias Exchange.Orderbook.Schema.Trade

  project %TradeExecuted{} = event, fn multi ->
    projection =
      %Trade{
        symbol: event.base_asset <> event.quote_asset,
        sell_order_id: event.sell_order_id,
        buy_order_id: event.buy_order_id,
        price: event.price.amount,
        quantity: event.quantity.amount,
        maker: to_existing_atom!(event.maker),
        executed_at: parse_timestamp!(event.timestamp)
      }

    Ecto.Multi.insert(multi, :trade_projection, projection)
  end

  defp to_existing_atom!(val) when is_atom(val), do: val
  defp to_existing_atom!(val) when is_binary(val), do: String.to_existing_atom(val)

  defp parse_timestamp!(%DateTime{} = timestamp) do
    timestamp
  end

  defp parse_timestamp!(timestamp) when is_binary(timestamp) do
    {:ok, ts, _} = DateTime.from_iso8601(timestamp)
    ts
  end
end
