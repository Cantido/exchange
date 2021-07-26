defmodule Exchange.Orderbook.OrderPlaced do
  @derive Jason.Encoder
  @enforce_keys [
    :symbol,
    :order_id,
    :type,
    :side,
    :timestamp
  ]
  defstruct [
    :symbol,
    :order_id,
    :type,
    :side,
    :time_in_force,
    :price,
    :stop_price,
    :quantity,
    :timestamp
  ]
end
