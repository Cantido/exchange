defmodule Exchange.Orderbook.TradeExecuted do
  @enforce_keys [
    :sell_order_id,
    :buy_order_id,
    :price,
    :quantity,
    :maker
  ]
  defstruct [
    :sell_order_id,
    :buy_order_id,
    :price,
    :quantity,
    :maker
  ]
end
