defmodule Exchange.Orderbook.Order do
  alias Exchange.Orderbook.OrderExpired
  alias Exchange.Orderbook.OrderPlaced

  @derive Jason.Encoder
  @enforce_keys [
    :order_id,
    :side,
    :type,
    :time_in_force,
    :price,
    :stop_price,
    :quantity,
    :timestamp
  ]
  defstruct [
    :order_id,
    :side,
    :type,
    :time_in_force,
    :price,
    :stop_price,
    :quantity,
    :timestamp
  ]

  def from_map(command) do
    %__MODULE__{
      order_id: command.order_id,
      side: command.side,
      type: command.type,
      time_in_force: command.time_in_force,
      price: command.price,
      stop_price: command.stop_price,
      quantity: command.quantity,
      timestamp: command.timestamp
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
      quantity: order.quantity,
      timestamp: order.timestamp
    }
  end

  def find_matching_orders(taker_order, maker_orders) do
    maker_side =
      case taker_order.side do
        :sell -> :buy
        :buy -> :sell
      end

    maker_orders =
      maker_orders
      |> Enum.filter(& &1.side == maker_side)
      |> Enum.filter(& &1.type == :limit)

    if taker_order.type == :market  do
      sort_order = sort_for_match(taker_order)

      Enum.sort_by(maker_orders, & &1.price, sort_order)
    else
      Enum.filter(maker_orders, fn maker_order ->
        maker_order.price == taker_order.price
      end)
    end
  end

  defp sort_for_match(%{side: :sell}), do: :desc
  defp sort_for_match(%{side: :buy}), do: :asc

  def execute?(%{type: :stop_loss, side: :sell, stop_price: stop_price}, last_trade_price) do
    last_trade_price <= stop_price
  end

  def execute?(%{type: :stop_loss, side: :buy, stop_price: stop_price}, last_trade_price) do
    last_trade_price >= stop_price
  end

  def execute?(%{type: :stop_loss_limit, side: :sell, stop_price: stop_price}, last_trade_price) do
    last_trade_price <= stop_price
  end

  def execute?(%{type: :stop_loss_limit, side: :buy, stop_price: stop_price}, last_trade_price) do
    last_trade_price >= stop_price
  end

  def execute?(%{type: :take_profit, side: :sell, stop_price: stop_price}, last_trade_price) do
    last_trade_price >= stop_price
  end

  def execute?(%{type: :take_profit, side: :buy, stop_price: stop_price}, last_trade_price) do
    last_trade_price <= stop_price
  end

  def execute?(%{type: :take_profit_limit, side: :sell, stop_price: stop_price}, last_trade_price) do
    last_trade_price >= stop_price
  end

  def execute?(%{type: :take_profit_limit, side: :buy, stop_price: stop_price}, last_trade_price) do
    last_trade_price <= stop_price
  end

  def execute?(_order, _price) do
    false
  end

  def to_execution_order(%{type: :stop_loss} = order) do
    %{order | type: :market}
  end

  def to_execution_order(%{type: :take_profit} = order) do
      %{order | type: :market}
  end

  def to_execution_order(%{type: :stop_loss_limit} = order) do
      %{order | type: :limit}
  end

  def to_execution_order(%{type: :take_profit_limit} = order) do
      %{order | type: :limit}
  end
end
