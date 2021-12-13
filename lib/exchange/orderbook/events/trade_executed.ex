defmodule Exchange.Orderbook.TradeExecuted do
  @derive Jason.Encoder
  @enforce_keys [
    :sell_order_id,
    :buy_order_id,
    :base_asset,
    :quote_asset,
    :price,
    :quantity,
    :maker,
    :timestamp
  ]
  defstruct [
    :sell_order_id,
    :buy_order_id,
    :base_asset,
    :quote_asset,
    :price,
    :quantity,
    :maker,
    :timestamp
  ]
end
