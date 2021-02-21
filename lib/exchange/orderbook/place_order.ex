defmodule Exchange.Orderbook.PlaceOrder do
  @enforce_keys [
    :order_id,
    :type,
    :side
  ]
  defstruct [
    :order_id,
    :type,
    :side,
    :time_in_force,
    :price,
    :stop_price,
    :quantity
  ]
end
