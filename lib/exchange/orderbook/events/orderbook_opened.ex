defmodule Exchange.Orderbook.OrderbookOpened do
  @derive Jason.Encoder
  @enforce_keys [
    :symbol,
    :quote_asset,
    :base_asset
  ]
  defstruct [
    :symbol,
    :quote_asset,
    :base_asset
  ]
end
