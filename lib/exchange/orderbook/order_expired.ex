defmodule Exchange.Orderbook.OrderExpired do
  @derive Jason.Encoder
  @enforce_keys [
    :order_id
  ]
  defstruct [
    :order_id
  ]
end
