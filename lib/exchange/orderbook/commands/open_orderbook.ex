defmodule Exchange.Orderbook.OpenOrderbook do
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
