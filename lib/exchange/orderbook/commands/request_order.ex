defmodule Exchange.Orderbook.RequestOrder do
  @derive Jason.Encoder
  @enforce_keys [
    :symbol,
    :account_id,
    :order_id,
    :type,
    :side,
    :timestamp
  ]
  defstruct [
    symbol: nil,
    account_id: nil,
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
