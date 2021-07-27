defmodule Exchange.Orderbook.OrderProjector do
  use Commanded.Projections.Ecto,
    application: Exchange.Commanded,
    repo: Exchange.Repo,
    name: "OrderProjector"

  alias Exchange.Orderbook.{OrderPlaced, OrderFilled, OrderExpired}
  alias Exchange.Orderbook.Schema.Order

  project %OrderPlaced{} = event, fn multi ->
    {:ok, ts, _} = DateTime.from_iso8601(event.timestamp)
    projection =
      %Order{
        id: event.order_id,
        status: :new,
        symbol: event.symbol,
        side: String.to_existing_atom(event.side),
        type: String.to_existing_atom(event.type),
        time_in_force: String.to_existing_atom(event.time_in_force),
        price: event.price,
        stop_price: event.stop_price,
        quantity: event.quantity,
        timestamp: ts
      }

    Ecto.Multi.insert(multi, :order_projection, projection)
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
