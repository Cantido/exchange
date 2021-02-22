defmodule Exchange.Orderbook.Order do
  alias Exchange.Orderbook.OrderExpired
  alias Exchange.Orderbook.OrderPlaced

  @enforce_keys [
    :order_id,
    :side,
    :type,
    :time_in_force,
    :price,
    :stop_price,
    :quantity
  ]
  defstruct [
    :order_id,
    :side,
    :type,
    :time_in_force,
    :price,
    :stop_price,
    :quantity
  ]

  def from_map(command) do
    %__MODULE__{
      order_id: command.order_id,
      side: command.side,
      type: command.type,
      time_in_force: command.time_in_force,
      price: command.price,
      stop_price: command.stop_price,
      quantity: command.quantity
    }
  end

  def expire(order) do
    %OrderExpired{order_id: order.order_id}
  end

  def place(order, symbol) do
    %OrderPlaced{
      symbol: symbol,
      order_id: order.order_id,
      type: order.type,
      side: order.side,
      time_in_force: order.time_in_force,
      price: order.price,
      stop_price: order.stop_price,
      quantity: order.quantity
    }
  end
end
