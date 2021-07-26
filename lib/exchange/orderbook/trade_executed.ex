defmodule Exchange.Orderbook.TradeExecuted do
  @derive Jason.Encoder
  @enforce_keys [
    :symbol,
    :sell_order_id,
    :buy_order_id,
    :price,
    :quantity,
    :maker,
    :timestamp
  ]
  defstruct [
    :symbol,
    :sell_order_id,
    :buy_order_id,
    :price,
    :quantity,
    :maker,
    :timestamp
  ]
end
