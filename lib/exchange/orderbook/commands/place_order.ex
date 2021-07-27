defmodule Exchange.Orderbook.PlaceOrder do
  @derive Jason.Encoder
  @enforce_keys [
    :symbol,
    :order_id,
    :type,
    :side,
    :timestamp
  ]
  defstruct [
    symbol: nil,
    order_id: nil,
    type: nil,
    side: nil,
    time_in_force: :good_til_cancelled,
    price: nil,
    stop_price: nil,
    quantity: nil,
    timestamp: nil
  ]
end
