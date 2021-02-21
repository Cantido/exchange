defmodule Exchange.Orderbook.OrderPlaced do
  @derive Jason.Encoder
  @enforce_keys [
    :order_id,
    :type,
    :side
  ]
  defstruct [
    :order_id,
    :type,
    :side,
    :time_in_force,
    :price,
    :stop_price,
    :quantity
  ]

  def from_command(command) do
    %__MODULE__{
      order_id: command.order_id,
      type: command.type,
      side: command.side,
      time_in_force: command.time_in_force,
      price: command.price,
      stop_price: command.stop_price,
      quantity: command.quantity
    }
  end
end
