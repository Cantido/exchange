defmodule Exchange.Orderbook do
  @moduledoc """
  Documentation for `Orderbook`.
  """
  alias Exchange.Orderbook.Order
  alias Exchange.Orderbook.PlaceOrder
  alias Exchange.Orderbook.OpenOrderbook
  alias Exchange.Orderbook.OrderbookOpened
  alias Exchange.Orderbook.OrderPlaced
  alias Exchange.Orderbook.OrderExpired
  alias Exchange.Orderbook.TradeExecuted
  alias Commanded.Aggregate.Multi

  defstruct [
    symbol: nil,
    orders: %{},
    last_trade_price: nil
  ]

  def new(symbol) do
    %__MODULE__{
      symbol: symbol
    }
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :limit,
      time_in_force: tif,
      quantity: qty,
      price: price
    }
  ) when not is_nil(tif) and not is_nil(qty) and not is_nil(price) do
    :ok
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :market,
      quantity: qty
    }
  ) when not is_nil(qty) do
    :ok
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :stop_loss,
      quantity: qty,
      stop_price: stop_price
    }
  ) when not is_nil(qty) and not is_nil(stop_price) do
    :ok
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :take_profit,
      quantity: qty,
      stop_price: stop_price
    }
  ) when not is_nil(qty) and not is_nil(stop_price) do
    :ok
  end

  defp validate_place_order_command(_command) do
    {:error, :invalid_order}
  end

  def execute(%__MODULE__{symbol: nil}, %OpenOrderbook{symbol: symbol}) do
    %OrderbookOpened{symbol: symbol}
  end

  def execute(%__MODULE__{}, %OpenOrderbook{}) do
    {:error, :orderbook_already_open}
  end

  def execute(ob, %PlaceOrder{type: :stop_loss} = command) do
    with :ok <- validate_place_order_command(command) do
      OrderPlaced.from_command(command, ob.symbol)
    end
  end

  def execute(ob, %PlaceOrder{type: :take_profit} = command) do
    with :ok <- validate_place_order_command(command) do
      OrderPlaced.from_command(command, ob.symbol)
    end
  end

  def execute(ob, %PlaceOrder{} = command) do
    with :ok <- validate_place_order_command(command) do
      ob
      |> Multi.new()
      |> Multi.execute(&place_order(&1, command))
      |> Multi.execute(&execute_order(&1, command))
      |> Multi.execute(&trigger_stop_orders(&1))
    end
  end

  defp place_order(ob, command) do
    OrderPlaced.from_command(command, ob.symbol)
  end

  defp trigger_stop_orders(ob) do
    stop_limit_orders_to_execute =
      Enum.filter(ob.orders, fn {_id, order} ->
        order.type == :stop_loss and ob.last_trade_price <= order.stop_price
      end)
      |> Map.new()

    stop_limit_order_events =
      Enum.flat_map(stop_limit_orders_to_execute, fn {_id, stop} ->
        execute_order(ob, stop)
      end)

    take_profit_orders_to_execute =
      Enum.filter(ob.orders, fn {_id, order} ->
        order.type == :take_profit and ob.last_trade_price >= order.stop_price
      end)
      |> Map.new()

    take_profit_events =
      Enum.flat_map(take_profit_orders_to_execute, fn {_id, stop} ->
        execute_order(ob, stop)
      end)

    stop_limit_order_events ++ take_profit_events
  end

  defp execute_order(ob, command) do
    sort_order =
      case command.side do
        :sell -> :desc
        :buy -> :asc
      end

    opposite_side =
      case command.side do
        :sell -> :buy
        :buy -> :sell
      end

    orders_to_match = Map.values(ob.orders) |> Enum.filter(& &1.side == opposite_side)

    matching_orders =
      if command.type in [:market, :stop_loss, :take_profit] do
        Enum.sort_by(orders_to_match, & &1.price, sort_order)
      else
        Enum.filter(orders_to_match, fn order ->
          order.price == command.price
        end)
      end

    {trades, remaining_quantity} =
      Enum.reduce_while(matching_orders, {[], command.quantity}, fn order, {events, quantity} ->
        trade =
          case command.side do
            :sell ->
              %TradeExecuted{
                symbol: ob.symbol,
                sell_order_id: command.order_id,
                buy_order_id: order.order_id,
                price: order.price,
                quantity: min(command.quantity, order.quantity),
                maker: :buyer
              }
            :buy ->
              %TradeExecuted{
                symbol: ob.symbol,
                sell_order_id: order.order_id,
                buy_order_id: command.order_id,
                price: order.price,
                quantity: min(order.quantity, command.quantity),
                maker: :seller
              }
          end
        remaining_quantity = quantity - trade.quantity

        if remaining_quantity <= 0 do
          {:halt, {[trade | events], remaining_quantity}}
        else
          {:cont, {[trade | events], remaining_quantity}}
        end
      end)

    if remaining_quantity > 0 do
      if command.type in [:market, :stop_loss, :take_profit] do
        trades ++ [%OrderExpired{order_id: command.order_id}]
      else
        case command.time_in_force do
          :fill_or_kill ->
            [%OrderExpired{order_id: command.order_id}]
          :immediate_or_cancel ->
            trades ++ [%OrderExpired{order_id: command.order_id}]
          :good_til_cancelled ->
            trades
        end
      end
    else
      trades
    end
  end

  # State Mutators

  def apply(ob, %OrderbookOpened{symbol: symbol}) do
    %{ob | symbol: symbol}
  end

  def apply(ob, %OrderPlaced{} = order) do
    new_order = Order.from_map(order)

    Map.update!(ob, :orders, fn orders ->
      Map.put(orders, new_order.order_id, new_order)
    end)
  end

  def apply(ob, %OrderExpired{order_id: order_id}) do
    Map.update!(ob, :orders, fn orders ->
      Map.delete(orders, order_id)
    end)
  end

  def apply(ob, %TradeExecuted{} = trade) do
    ob
    |> Map.update!(:orders, fn orders ->
      orders
      |> Map.update!(trade.sell_order_id, fn order ->
        %{order | quantity: order.quantity - trade.quantity}
      end)
      |> Map.new()
      |> Map.update!(trade.buy_order_id, fn order ->
        %{order | quantity: order.quantity - trade.quantity}
      end)
      |> Enum.reject(fn {_, order} ->
        order.quantity <= 0
      end)
      |> Map.new()
    end)
    |> Map.put(:last_trade_price, trade.price)
  end
end
