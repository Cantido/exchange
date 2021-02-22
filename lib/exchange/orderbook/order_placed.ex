defmodule Exchange.Orderbook.OrderPlaced do
  @derive Jason.Encoder
  @enforce_keys [
    :symbol,
    :order_id,
    :type,
    :side
  ]
  defstruct [
    :symbol,
    :order_id,
    :type,
    :side,
    :time_in_force,
    :price,
    :stop_price,
    :quantity
  ]
end
