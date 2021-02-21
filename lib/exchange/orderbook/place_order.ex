defmodule Exchange.Orderbook.PlaceOrder do
  @derive Jason.Encoder
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
