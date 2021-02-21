defmodule Exchange.Orderbook.OrderExpired do
  @enforce_keys [
    :order_id
  ]
  defstruct [
    :order_id
  ]
end
