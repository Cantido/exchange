defmodule Exchange.Orderbook.Order do
  @enforce_keys [
    :order_id,
    :side,
    :type,
    :price,
    :stop_price,
    :quantity
  ]
  defstruct [
    :order_id,
    :side,
    :type,
    :price,
    :stop_price,
    :quantity
  ]

  def from_map(command) do
    %__MODULE__{
      order_id: command.order_id,
      side: command.side,
      type: command.type,
      price: command.price,
      stop_price: command.stop_price,
      quantity: command.quantity
    }
  end
end
