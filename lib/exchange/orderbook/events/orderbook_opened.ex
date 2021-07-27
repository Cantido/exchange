defmodule Exchange.Orderbook.OrderbookOpened do
  @derive Jason.Encoder
  @enforce_keys [
    :symbol
  ]
  defstruct [
    :symbol
  ]
end
