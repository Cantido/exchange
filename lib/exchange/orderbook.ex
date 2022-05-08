defmodule Exchange.Orderbook do
  @moduledoc """
  Documentation for `Orderbook`.
  """
  alias Exchange.Orderbook.Order
  alias Exchange.Orderbook.Trade
  alias Exchange.Orderbook.RequestOrder
  alias Exchange.Orderbook.OrderRequested
  alias Exchange.Orderbook.PlaceOrder
  alias Exchange.Orderbook.OpenOrderbook
  alias Exchange.Orderbook.OrderbookOpened
  alias Exchange.Orderbook.OrderPlaced
  alias Exchange.Orderbook.OrderFilled
  alias Exchange.Orderbook.OrderExpired
  alias Exchange.Orderbook.TradeExecuted
  alias Commanded.Aggregate.Multi
  alias Money.Currency

  defguard is_time_in_force(tif) when
    not is_nil(tif) and (
      tif == :good_til_cancelled or
      tif == :immediate_or_cancel or
      tif == :fill_or_kill
    )

  @derive Jason.Encoder
  defstruct [
    symbol: nil,
    base_asset: nil,
    quote_asset: nil,
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
  ) when is_time_in_force(tif) do
    cond do
      not Money.positive?(qty) -> {:error, :invalid_quantity}
      not Money.positive?(price) -> {:error, :invalid_price}
      true -> :ok
    end
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :market,
      quantity: qty
    }
  ) do
    if Money.negative?(qty) do
      {:error, :invalid_quantity}
    else
      :ok
    end
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :stop_loss,
      quantity: qty,
      stop_price: stop_price
    }
  ) do
    cond do
      not Money.positive?(qty) -> {:error, :invalid_quantity}
      not Money.positive?(stop_price) -> {:error, :invalid_stop_price}
      true -> :ok
    end
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :stop_loss_limit,
      time_in_force: tif,
      quantity: qty,
      price: price,
      stop_price: stop_price
    }
  ) when is_time_in_force(tif) do
    cond do
      not Money.positive?(qty) -> {:error, :invalid_quantity}
      not Money.positive?(price) -> {:error, :invalid_price}
      not Money.positive?(stop_price) -> {:error, :invalid_stop_price}
      true -> :ok
    end
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :take_profit_limit,
      time_in_force: tif,
      quantity: qty,
      price: price,
      stop_price: stop_price
    }
  ) when is_time_in_force(tif) do
    cond do
      not Money.positive?(qty) -> {:error, :invalid_quantity}
      not Money.positive?(price) -> {:error, :invalid_price}
      not Money.positive?(stop_price) -> {:error, :invalid_stop_price}
      true -> :ok
    end
  end

  defp validate_place_order_command(
    %PlaceOrder{
      type: :take_profit,
      quantity: qty,
      stop_price: stop_price
    }
  ) do
    cond do
      not Money.positive?(qty) -> {:error, :invalid_quantity}
      not Money.positive?(stop_price) -> {:error, :invalid_stop_price}
      true -> :ok
    end
  end

  defp validate_place_order_command(_command) do
    {:error, :invalid_order}
  end

  def execute(
    %__MODULE__{symbol: nil},
    %OpenOrderbook{symbol: symbol, base_asset: ba, quote_asset: qa}) do
    cond do
      not String.valid?(symbol) -> {:error, :invalid_symbol}
      not Currency.exists?(ba) -> {:error, :base_asset_unknown}
      not Currency.exists?(qa) -> {:error, :quote_asset_unknown}
        true -> %OrderbookOpened{symbol: symbol, base_asset: Currency.to_atom(ba), quote_asset: Currency.to_atom(qa)}
    end
  end

  def execute(%__MODULE__{}, %OpenOrderbook{}) do
    {:error, :orderbook_already_open}
  end


  def execute(%__MODULE__{symbol: nil}, _) do
    {:error, :orderbook_not_opened}
  end

  def execute(%__MODULE__{} = ob, %RequestOrder{} = command) do
    %OrderRequested{
      account_id: command.account_id,
      order_id: command.order_id,
      symbol: ob.symbol,
      base_asset: ob.base_asset,
      quote_asset: ob.quote_asset,
      price: command.price,
      quantity: command.quantity,
      side: command.side,
      type: command.type,
      timestamp: command.timestamp
    }
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
    |> Enum.reject(& is_nil(&1.stop_price))
    |> Enum.sort_by(& &1.stop_price, {:desc, Money})
  end

  defp orders_ascending(ob) do
    Map.values(ob.orders)
    |> Enum.reject(& is_nil(&1.stop_price))
    |> Enum.sort_by(& &1.stop_price, {:asc, Money})
  end

  defp place_order(ob, command) do
    Order.place(command, ob.symbol)
  end

  defp match_order(ob, order) do
    cond do
      is_nil(ob.last_trade_price) ->
        # In case an order gets placed before we've executed any trades
        nil
      not Map.has_key?(ob.orders, order.order_id) ->
        # just in case some weird circumstance gives us an order that's already been executed
        nil
      Order.execute?(order, ob.last_trade_price) ->
        execute_order(ob, Order.to_execution_order(order))
      true ->
        nil
    end
  end

  defp execute_order(ob, taker_order) do
    {trades, remaining_quantity} =
      Order.find_matching_orders(taker_order, Map.values(ob.orders))
      |> Enum.reduce_while({[], taker_order.quantity}, fn maker_order, {events, quantity} ->
        trade = Trade.execute(maker_order, taker_order, ob.base_asset, ob.quote_asset)

        remaining_quantity = Money.subtract(quantity, trade.quantity)

        result =
          if Money.equals?(trade.quantity, maker_order.quantity) do
            fill = Order.fill(maker_order)
            {[fill | [trade | events]], remaining_quantity}
          else
            {[trade | events], remaining_quantity}
          end

        if Money.negative?(remaining_quantity) do
          raise "Negative quantity remaining while processing order #{taker_order.order_id}"
        end

        if Money.zero?(remaining_quantity) do
          {:halt, result}
        else
          {:cont, result}
        end
      end)

    if Money.positive?(remaining_quantity) do
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
      fill = Order.fill(taker_order)

      Enum.reverse([fill | trades])
    end
  end

  # State Mutators

  def apply(ob, %OrderbookOpened{symbol: symbol, base_asset: ba, quote_asset: qa}) do
    %{ob | symbol: symbol, base_asset: ba, quote_asset: qa}
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
        %{order | quantity: Money.subtract(order.quantity, trade.quantity)}
      end)
      |> Map.update!(trade.buy_order_id, fn order ->
        %{order | quantity: Money.subtract(order.quantity, trade.quantity)}
      end)
    end)
    |> Map.put(:last_trade_price, trade.price)
  end

  def apply(ob, %OrderRequested{}) do
    ob
  end
end
