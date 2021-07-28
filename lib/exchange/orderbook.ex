defmodule Exchange.Orderbook do
  @moduledoc """
  Documentation for `Orderbook`.
  """
  alias Exchange.Orderbook.Order
  alias Exchange.Orderbook.PlaceOrder
  alias Exchange.Orderbook.OpenOrderbook
  alias Exchange.Orderbook.OrderbookOpened
  alias Exchange.Orderbook.OrderPlaced
  alias Exchange.Orderbook.OrderFilled
  alias Exchange.Orderbook.OrderExpired
  alias Exchange.Orderbook.TradeExecuted
  alias Commanded.Aggregate.Multi

  defguard is_symbol(symbol) when
    is_binary(symbol) and
    byte_size(symbol) >= 1

  defguard is_time_in_force(tif) when
    not is_nil(tif) and (
      tif == :good_til_cancelled or
      tif == :immediate_or_cancel or
      tif == :fill_or_kill
    )

  defguard is_price(price) when
    is_integer(price) and price > 0

  defguard is_quantity(qty) when
    is_integer(qty) and qty > 0

  @derive Jason.Encoder
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
  ) when is_time_in_force(tif) and is_quantity(qty) and is_price(price) do
    :ok
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :market,
      quantity: qty
    }
  ) when is_quantity(qty) do
    :ok
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :stop_loss,
      quantity: qty,
      stop_price: stop_price
    }
  ) when is_quantity(qty) and is_price(stop_price) do
    :ok
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :stop_loss_limit,
      time_in_force: tif,
      quantity: qty,
      price: price,
      stop_price: stop_price
    }
  ) when is_time_in_force(tif) and is_price(price) and is_quantity(qty) and is_price(stop_price) do
    :ok
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :take_profit_limit,
      time_in_force: tif,
      quantity: qty,
      price: price,
      stop_price: stop_price
    }
  ) when is_time_in_force(tif) and is_price(price) and is_quantity(qty) and is_price(stop_price) do
    :ok
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :take_profit,
      quantity: qty,
      stop_price: stop_price
    }
  ) when is_quantity(qty) and is_price(stop_price) do
    :ok
  end

  defp validate_place_order_command(_command) do
    {:error, :invalid_order}
  end

  def execute(%__MODULE__{symbol: nil}, %OpenOrderbook{symbol: symbol}) when is_symbol(symbol) do
    if String.valid?(symbol) do
      %OrderbookOpened{symbol: symbol}
    else
      {:error, :invalid_symbol}
    end
  end

  def execute(%__MODULE__{}, %OpenOrderbook{}) do
    {:error, :orderbook_already_open}
  end


  def execute(%__MODULE__{symbol: nil}, _) do
    {:error, :orderbook_not_opened}
  end

  def execute(ob, %PlaceOrder{} = command) do
    with :ok <- validate_place_order_command(command) do
      ob
      |> Multi.new()
      |> Multi.execute(&place_order(&1, command))
      |> Multi.execute(&execute_order(&1, command))
      |> Multi.reduce(orders_descending(ob), &match_order(&1, &2))
      |> Multi.reduce(orders_ascending(ob), &match_order(&1, &2))
    end
  end

  defp orders_descending(ob) do
    Map.values(ob.orders)
    |> Enum.sort_by(& &1.stop_price, :desc)
  end

  defp orders_ascending(ob) do
    Map.values(ob.orders)
    |> Enum.sort_by(& &1.stop_price, :asc)
  end

  defp place_order(ob, command) do
    Order.place(command, ob.symbol)
  end

  defp match_order(ob, order) do
    cond do
      not Map.has_key?(ob.orders, order.order_id) ->
        # just in case some weird circumstance gives us an order that's already been executed
        nil
      order.type == :stop_loss and order.side == :sell and ob.last_trade_price <= order.stop_price ->
        execute_order(ob, %{order | type: :market})
      order.type == :stop_loss and order.side == :buy and ob.last_trade_price >= order.stop_price ->
        execute_order(ob, %{order | type: :market})
      order.type == :stop_loss_limit and order.side == :sell and ob.last_trade_price <= order.stop_price ->
        execute_order(ob, %{order | type: :limit})
      order.type == :stop_loss_limit and order.side == :buy and ob.last_trade_price >= order.stop_price ->
        execute_order(ob, %{order | type: :limit})
      order.type == :take_profit and order.side == :sell and ob.last_trade_price >= order.stop_price ->
        execute_order(ob, %{order | type: :market})
      order.type == :take_profit and order.side == :buy and ob.last_trade_price <= order.stop_price ->
        execute_order(ob, %{order | type: :market})
      order.type == :take_profit_limit and order.side == :sell and ob.last_trade_price >= order.stop_price ->
        execute_order(ob, %{order | type: :limit})
      order.type == :take_profit_limit and order.side == :buy and ob.last_trade_price <= order.stop_price ->
        execute_order(ob, %{order | type: :limit})
      true ->
        nil
    end
  end

  defp execute_order(ob, taker_order) do
    sort_order =
      case taker_order.side do
        :sell -> :desc
        :buy -> :asc
      end

    maker_side =
      case taker_order.side do
        :sell -> :buy
        :buy -> :sell
      end

    orders_to_match =
      Map.values(ob.orders)
      |> Enum.filter(& &1.side == maker_side)
      |> Enum.filter(& &1.type == :limit)

    matching_orders =
      if taker_order.type == :market  do
        Enum.sort_by(orders_to_match, & &1.price, sort_order)
      else
        Enum.filter(orders_to_match, fn potential_match ->
          potential_match.price == taker_order.price
        end)
      end

    {trades, remaining_quantity} =
      Enum.reduce_while(matching_orders, {[], taker_order.quantity}, fn maker_order, {events, quantity} ->
        trade =
          case taker_order.side do
            :sell ->
              %TradeExecuted{
                symbol: ob.symbol,
                sell_order_id: taker_order.order_id,
                buy_order_id: maker_order.order_id,
                price: maker_order.price,
                quantity: min(taker_order.quantity, maker_order.quantity),
                maker: :buyer,
                timestamp: taker_order.timestamp
              }
            :buy ->
              %TradeExecuted{
                symbol: ob.symbol,
                sell_order_id: maker_order.order_id,
                buy_order_id: taker_order.order_id,
                price: maker_order.price,
                quantity: min(maker_order.quantity, taker_order.quantity),
                maker: :seller,
                timestamp: taker_order.timestamp
              }
          end

        remaining_quantity = quantity - trade.quantity

        result =
          if trade.quantity == maker_order.quantity do
            fill =
              %OrderFilled{
                order_id: maker_order.order_id
              }
            {[fill | [trade | events]], remaining_quantity}
          else
            {[trade | events], remaining_quantity}
          end

        if remaining_quantity <= 0 do
          {:halt, result}
        else
          {:cont, result}
        end
      end)

    if remaining_quantity > 0 do
      if taker_order.type == :market do
        Enum.reverse([Order.expire(taker_order) | trades])
      else
        case taker_order.time_in_force do
          :fill_or_kill ->
            [Order.expire(taker_order)]
          :immediate_or_cancel ->
            Enum.reverse([Order.expire(taker_order) | trades])
          :good_til_cancelled ->
            Enum.reverse(trades)
        end
      end
    else
      fill =
        %OrderFilled{
          order_id: taker_order.order_id
        }

      Enum.reverse([fill | trades])
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

  def apply(ob, %OrderFilled{order_id: order_id}) do
    Map.update!(ob, :orders, fn orders ->
      Map.delete(orders, order_id)
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
      |> Map.update!(trade.buy_order_id, fn order ->
        %{order | quantity: order.quantity - trade.quantity}
      end)
    end)
    |> Map.put(:last_trade_price, trade.price)
  end
end
