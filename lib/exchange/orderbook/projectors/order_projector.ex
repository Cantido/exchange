defmodule Exchange.Orderbook.OrderProjector do
  use Commanded.Projections.Ecto,
    application: Exchange.Commanded,
    repo: Exchange.Repo,
    name: "OrderProjector"

  alias Exchange.Orderbook.{OrderPlaced, OrderFilled, OrderExpired}
  alias Exchange.Orderbook.Schema.Order

  project %OrderPlaced{} = event, fn multi ->

    projection =
      %Order{
        id: event.order_id,
        status: :new,
        symbol: event.symbol,
        side: to_existing_atom!(event.side),
        type: to_existing_atom!(event.type),
        time_in_force: to_existing_atom!(event.time_in_force),
        price: amount_or_nil(event.price),
        stop_price: amount_or_nil(event.stop_price),
        quantity: event.quantity.amount,
        timestamp: parse_timestamp!(event.timestamp)
      }

    Ecto.Multi.insert(multi, :order_projection, projection)
  end

  defp amount_or_nil(money) do
    if is_nil(money) do
      nil
    else
      money.amount
    end
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

  project %OrderFilled{} = event, fn multi ->
    order =
      Exchange.Repo.get(Order, event.order_id)
      |> Ecto.Changeset.change(%{status: :filled})

    Ecto.Multi.update(multi, :order_projection, order)
  end

  project %OrderExpired{} = event, fn multi ->
    order =
      Exchange.Repo.get(Order, event.order_id)
      |> Ecto.Changeset.change(%{status: :expired})

    Ecto.Multi.update(multi, :order_projection, order)
  end
end
