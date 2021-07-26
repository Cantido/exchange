defmodule Exchange.Orderbook.OrderProjector do
  use Commanded.Projections.Ecto,
    application: Exchange.Commanded,
    repo: Exchange.Repo,
    name: "OrderProjector"

  alias Exchange.Orderbook.OrderPlaced
  alias Exchange.Orderbook.Schema.Order

  project %OrderPlaced{} = event, fn multi ->
    projection =
      %Order{
        id: event.order_id,
        side: event.side,
        type: event.type,
        time_in_force: event.time_in_force,
        price: event.price,
        stop_price: event.stop_price,
        quantity: event.quantity,
        timestamp: event.timestamp
      }

    Ecto.Multi.insert(multi, :order_projection, projection)
  end
end
