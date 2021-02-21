defmodule Exchange.Orderbook do
  @moduledoc """
  Documentation for `Orderbook`.
  """
  alias Exchange.Orderbook.TradeExecuted
  alias Exchange.Orderbook.PlaceOrder
  alias Exchange.Orderbook.OrderPlaced
  alias Exchange.Orderbook.OrderExpired

  defstruct [
    sell_orders: %{},
    buy_orders: %{},
    stop_loss_orders: %{},
    take_profit_orders: %{}
  ]

  def new do
    %__MODULE__{}
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

  def execute(_ob, %PlaceOrder{type: :stop_loss} = command) do
    with :ok <- validate_place_order_command(command) do
      [OrderPlaced.from_command(command)]
    end
  end

  def execute(_ob, %PlaceOrder{type: :take_profit} = command) do
    with :ok <- validate_place_order_command(command) do
      [OrderPlaced.from_command(command)]
    end
  end

  def execute(ob, %PlaceOrder{} = command) do
    with :ok <- validate_place_order_command(command) do
      order_placed = OrderPlaced.from_command(command)

      first_order_events = execute_order(ob, command)
      events = execute_stop_losses(ob, first_order_events)
      events = execute_take_profits(ob, events)

      [order_placed | events]
    end
  end

  defp execute_stop_losses(ob, events, previously_executed_orders \\ %{}, past_events \\ []) do
    if Enum.any?(events) do
      executed_orders =
        Enum.filter(ob.stop_loss_orders, fn {id, slo} ->
          Enum.any?(events, fn event ->
            event.__struct__ == TradeExecuted and
              event.price <= slo.stop_price and
              not Map.has_key?(previously_executed_orders, id)
          end)
        end)
        |> Map.new()

      more_events =
        Enum.flat_map(executed_orders, fn {_id, stop} ->
          execute_order(ob, stop)
        end)

      execute_stop_losses(ob, more_events, Map.merge(executed_orders, previously_executed_orders), past_events ++ events)
    else
      past_events
    end
  end

  defp execute_take_profits(ob, events, previously_executed_orders \\ %{}, past_events \\ []) do
    if Enum.any?(events) do
      executed_orders =
        Enum.filter(ob.take_profit_orders, fn {id, tpo} ->
          Enum.any?(events, fn event ->
            event.__struct__ == TradeExecuted and
              event.price >= tpo.stop_price and
              not Map.has_key?(previously_executed_orders, id)
          end)
        end)
        |> Map.new()

      more_events =
        Enum.flat_map(executed_orders, fn {_id, stop} ->
          execute_order(ob, stop)
        end)

      execute_stop_losses(ob, more_events, Map.merge(executed_orders, previously_executed_orders), past_events ++ events)
    else
      past_events
    end
  end

  defp execute_order(ob, command) do
    orders_to_filter =
      case command.side do
        :sell -> ob.buy_orders
        :buy -> ob.sell_orders
      end

    sort_order =
      case command.side do
        :sell -> :desc
        :buy -> :asc
      end

    matching_orders =
      if command.type in [:market, :stop_loss, :take_profit] do
        Map.values(orders_to_filter)
        |> Enum.sort_by(& &1.price, sort_order)
      else
        Map.values(orders_to_filter)
        |> Enum.filter(fn order ->
          order.price == command.price
        end)
      end

    {trades, remaining_quantity} =
      Enum.reduce_while(matching_orders, {[], command.quantity}, fn order, {events, quantity} ->
        trade =
          case command.side do
            :sell ->
              %TradeExecuted{
                sell_order_id: command.order_id,
                buy_order_id: order.order_id,
                price: order.price,
                quantity: min(command.quantity, order.quantity),
                maker: :buyer
              }
            :buy ->
              %TradeExecuted{
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

  def apply(ob, %OrderPlaced{type: :stop_loss} = order) do
    new_order = %{order_id: order.order_id, side: order.side, type: :stop_loss, stop_price: order.stop_price, quantity: order.quantity}
    %{ob | stop_loss_orders: Map.put(ob.stop_loss_orders, new_order.order_id, new_order)}
  end

  def apply(ob, %OrderPlaced{type: :take_profit} = order) do
    new_order = %{order_id: order.order_id, side: order.side, type: :take_profit, stop_price: order.stop_price, quantity: order.quantity}
    %{ob | take_profit_orders: Map.put(ob.take_profit_orders, new_order.order_id, new_order)}
  end

  def apply(ob, %OrderPlaced{side: :sell} = sell_order) do
    new_order = %{order_id: sell_order.order_id, price: sell_order.price, quantity: sell_order.quantity}
    %{ob | sell_orders: Map.put(ob.sell_orders, new_order.order_id, new_order)}
  end

  def apply(ob, %OrderPlaced{side: :buy} = buy_order) do
    new_order = %{order_id: buy_order.order_id, price: buy_order.price, quantity: buy_order.quantity}
    %{ob | buy_orders: Map.put(ob.buy_orders, new_order.order_id, new_order)}
  end

  def apply(ob, %OrderExpired{order_id: order_id}) do
    %{ob |
      sell_orders: Map.delete(ob.sell_orders, order_id),
      buy_orders: Map.delete(ob.buy_orders, order_id)
    }
  end

  def apply(ob, %TradeExecuted{maker: :buyer} = trade) do
    buy_orders =
      Map.update!(ob.buy_orders, trade.buy_order_id, fn order ->
        %{order | quantity: order.quantity - trade.quantity}
      end)
      |> Enum.reject(fn {_, order} ->
        order.quantity <= 0
      end)
      |> Map.new()

    %{ob | buy_orders: buy_orders}
  end

  def apply(ob, %TradeExecuted{maker: :seller} = trade) do
    sell_orders =
      Map.update!(ob.sell_orders, trade.sell_order_id, fn order ->
        %{order | quantity: order.quantity - trade.quantity}
      end)
      |> Enum.reject(fn {_, order} ->
        order.quantity <= 0
      end)
      |> Map.new()

    %{ob | sell_orders: sell_orders}
  end
end
