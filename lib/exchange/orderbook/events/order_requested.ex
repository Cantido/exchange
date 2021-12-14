defmodule Exchange.Orderbook.OrderRequested do
  @derive Jason.Encoder
  @enforce_keys [
    :symbol,
    :account_id,
    :base_asset,
    :quote_asset,
    :order_id,
    :type,
    :side,
    :timestamp
  ]
  defstruct [
    account_id: nil,
    symbol: nil,
    order_id: nil,
    base_asset: nil,
    quote_asset: nil,
    type: nil,
    side: nil,
    time_in_force: :good_til_cancelled,
    price: nil,
    stop_price: nil,
    quantity: nil,
    timestamp: nil
  ]
end
