defmodule ExchangeWeb.API.OrderController do
  use ExchangeWeb, :controller

  def create(conn, params) do
    id = UUID.uuid4()
    :ok =
      Exchange.Commanded.dispatch(
        %Exchange.Orderbook.PlaceOrder{
          symbol: params["symbol_id"],
          order_id: id,
          type: :limit,
          side: String.to_existing_atom(params["side"]),
          time_in_force: :good_til_cancelled,
          price: params["price"],
          quantity: params["quantity"],
          timestamp: DateTime.utc_now()
        }
      )

    conn
    |> put_status(:accepted)
    |> json(%{id: id})
  end
end
