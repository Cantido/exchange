defmodule OrderbookTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Exchange.Orderbook
  alias Exchange.Orderbook.PlaceOrder
  alias Exchange.Orderbook.OrderPlaced
  alias Exchange.Orderbook.OrderExpired
  alias Exchange.Orderbook.TradeExecuted
  require Logger
  import Commanded.Assertions.EventAssertions
  doctest Exchange.Orderbook

  test "open orderbook" do
    :ok = Exchange.Commanded.dispatch(%Exchange.Orderbook.OpenOrderbook{symbol: "BTCUSDT"})

    assert_receive_event(Exchange.Commanded, Exchange.Orderbook.OrderbookOpened, fn event ->
      assert event.symbol == "BTCUSDT"
    end)
  end

  property "good-til-cancelled limit orders match everything available and then go on the books" do
    check all price <- integer(1..100),
              first_side <- member_of([:buy, :sell]),
              available_quantity <- integer(1..100),
              wanted_quantity <- integer((available_quantity + 1)..200) do

      first_command =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :limit,
          side: first_side,
          time_in_force: :good_til_cancelled,
          price: price,
          quantity: available_quantity
        }

      second_side =
        case first_side do
          :buy -> :sell
          :sell -> :buy
        end

      second_command =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :limit,
          side: second_side,
          time_in_force: :good_til_cancelled,
          price: price,
          quantity: wanted_quantity
        }

      {ob, _} = apply_commands(Orderbook.new("BTCUSDT"), first_command)
      {_, events} = apply_commands(ob, second_command)

      assert Enum.count(events) == 2
      [placed, executed] = events

      {sell_command, buy_command} =
        case first_side do
          :buy -> {second_command, first_command}
          :sell -> {first_command, second_command}
        end

      maker =
        case first_side do
          :buy -> :buyer
          :sell -> :seller
        end

      assert placed.__struct__ == OrderPlaced
      assert placed.order_id == second_command.order_id
      assert placed.type == :limit
      assert placed.side == second_side
      assert placed.time_in_force == :good_til_cancelled
      assert placed.price == price
      assert placed.quantity == wanted_quantity

      assert executed.__struct__ == TradeExecuted
      assert executed.sell_order_id == sell_command.order_id
      assert executed.buy_order_id == buy_command.order_id
      assert executed.price == price
      assert executed.quantity == available_quantity
      assert executed.maker == maker
    end
  end

  property "good-til-cancelled limit orders can get partially filled by later orders" do
    check all price <- integer(1..100),
              first_side <- member_of([:buy, :sell]),
              wanted_quantity <- integer(1..100),
              available_quantity <- integer((wanted_quantity + 1)..200) do

      first_command =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :limit,
          side: first_side,
          time_in_force: :good_til_cancelled,
          price: price,
          quantity: available_quantity
        }

      second_side =
        case first_side do
          :buy -> :sell
          :sell -> :buy
        end

      second_command =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :limit,
          side: second_side,
          time_in_force: :good_til_cancelled,
          price: price,
          quantity: wanted_quantity
        }

      {ob, _} = apply_commands(Orderbook.new("BTCUSDT"), first_command)
      {ob, events} = apply_commands(ob, second_command)

      assert Enum.count(events) == 2
      [placed, trade] = events

      {sell_command, buy_command} =
        case first_side do
          :buy -> {second_command, first_command}
          :sell -> {first_command, second_command}
        end

      maker =
        case first_side do
          :buy -> :buyer
          :sell -> :seller
        end

      assert placed.__struct__ == OrderPlaced
      assert placed.order_id == second_command.order_id
      assert placed.type == :limit
      assert placed.side == second_side
      assert placed.time_in_force == :good_til_cancelled
      assert placed.price == price
      assert placed.quantity == wanted_quantity

      assert trade.__struct__ == TradeExecuted
      assert trade.sell_order_id == sell_command.order_id
      assert trade.buy_order_id == buy_command.order_id
      assert trade.price == price
      assert trade.quantity == wanted_quantity
      assert trade.maker == maker

      [{_, remaining_order}] =
        case first_side do
          :buy -> ob.buy_orders
          :sell -> ob.sell_orders
        end
        |> Map.to_list()

      assert remaining_order.quantity == available_quantity - wanted_quantity
    end
  end

  property "fill-or-kill order is cancelled if there is not enough quantity on the books" do
    check all price <- integer(1..100),
              first_side <- member_of([:buy, :sell]),
              available_quantity <- integer(1..100),
              wanted_quantity <- integer((available_quantity + 1)..200) do

      first_command =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :limit,
          side: first_side,
          time_in_force: :good_til_cancelled,
          price: price,
          quantity: available_quantity
        }

      second_side =
        case first_side do
          :buy -> :sell
          :sell -> :buy
        end

      second_command =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :limit,
          side: second_side,
          time_in_force: :fill_or_kill,
          price: price,
          quantity: wanted_quantity
        }

      {ob, _} = apply_commands(Orderbook.new("BTCUSDT"), first_command)
      {_, events} = apply_commands(ob, second_command)

      assert Enum.count(events) == 2
      [placed, expired] = events

      assert placed.__struct__ == OrderPlaced
      assert placed.order_id == second_command.order_id
      assert placed.type == :limit
      assert placed.side == second_side
      assert placed.time_in_force == :fill_or_kill
      assert placed.price == price
      assert placed.quantity == wanted_quantity

      assert expired.__struct__ == OrderExpired
      assert expired.order_id == second_command.order_id

      [{_, remaining_order}] =
        case first_side do
          :buy -> ob.buy_orders
          :sell -> ob.sell_orders
        end
        |> Map.to_list()

      assert remaining_order.quantity == available_quantity
    end
  end

  property "immediate-or-cancel order is partially filled and the rest is cancelled" do
    check all price <- integer(1..100),
              first_side <- member_of([:buy, :sell]),
              wanted_quantity <- integer(2..100),
              available_quantity <- integer(1..(wanted_quantity - 1)) do

      second_side =
        case first_side do
          :buy -> :sell
          :sell -> :buy
        end

      first_command =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :limit,
          side: first_side,
          time_in_force: :good_til_cancelled,
          price: price,
          quantity: available_quantity
        }

      second_command =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :limit,
          side: second_side,
          time_in_force: :immediate_or_cancel,
          price: price,
          quantity: wanted_quantity
        }

      {ob, _} = apply_commands(Orderbook.new("BTCUSDT"), first_command)
      {ob, events} = apply_commands(ob, second_command)

      assert Enum.count(events) == 3, "events were #{inspect events}"
      [placed, trade, second_expired] = events

      {sell_command, buy_command} =
        case first_side do
          :buy -> {second_command, first_command}
          :sell -> {first_command, second_command}
        end

      maker =
        case first_side do
          :buy -> :buyer
          :sell -> :seller
        end

      assert placed.__struct__ == OrderPlaced
      assert placed.order_id == second_command.order_id
      assert placed.type == :limit
      assert placed.side == second_side
      assert placed.time_in_force == :immediate_or_cancel
      assert placed.price == price
      assert placed.quantity == wanted_quantity

      assert trade.__struct__ == TradeExecuted
      assert trade.sell_order_id == sell_command.order_id
      assert trade.buy_order_id == buy_command.order_id
      assert trade.price == price
      assert trade.quantity == available_quantity
      assert trade.maker == maker

      assert second_expired.__struct__ == OrderExpired
      assert second_expired.order_id == second_command.order_id

      assert Enum.empty?(ob.sell_orders)
      assert Enum.empty?(ob.buy_orders)
    end
  end

  property "market orders can partially fill then expire" do
    check all price <- integer(1..100),
              first_side <- member_of([:buy, :sell]),
              wanted_quantity <- integer(2..100),
              available_quantity <- integer(1..(wanted_quantity - 1)) do

      second_side =
        case first_side do
          :buy -> :sell
          :sell -> :buy
        end

      first_command =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :limit,
          side: first_side,
          time_in_force: :good_til_cancelled,
          price: price,
          quantity: available_quantity
        }

      second_command =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :market,
          side: second_side,
          time_in_force: nil,
          price: nil,
          quantity: wanted_quantity
        }

      {ob, _} = apply_commands(Orderbook.new("BTCUSDT"), first_command)
      {ob, events} = apply_commands(ob, second_command)

      assert Enum.count(events) == 3, "events were #{inspect events}"
      [placed, trade, second_expired] = events

      {sell_command, buy_command} =
        case first_side do
          :buy -> {second_command, first_command}
          :sell -> {first_command, second_command}
        end

      maker =
        case first_side do
          :buy -> :buyer
          :sell -> :seller
        end

      assert placed.__struct__ == OrderPlaced
      assert placed.order_id == second_command.order_id
      assert placed.type == :market
      assert placed.side == second_side
      assert is_nil(placed.price)
      assert placed.quantity == wanted_quantity

      assert trade.__struct__ == TradeExecuted
      assert trade.sell_order_id == sell_command.order_id
      assert trade.buy_order_id == buy_command.order_id
      assert trade.price == price
      assert trade.quantity == available_quantity
      assert trade.maker == maker

      assert second_expired.__struct__ == OrderExpired
      assert second_expired.order_id == second_command.order_id

      assert Enum.empty?(ob.sell_orders)
      assert Enum.empty?(ob.buy_orders)
    end
  end

  property "market orders expire immediately if no orders are available" do
    check all side <- member_of([:buy, :sell]),
              wanted_quantity <- integer(1..100)do

      order =
        %PlaceOrder{
          order_id: UUID.uuid4(),
          type: :market,
          side: side,
          time_in_force: nil,
          price: nil,
          quantity: wanted_quantity
        }

      {ob, events} = apply_commands(Orderbook.new("BTCUSDT"), order)

      assert Enum.count(events) == 2, "events were #{inspect events}"
      [placed, expired] = events

      assert placed.__struct__ == OrderPlaced
      assert placed.order_id == order.order_id
      assert placed.type == :market
      assert placed.side == side
      assert is_nil(placed.price)
      assert placed.quantity == wanted_quantity

      assert expired.__struct__ == OrderExpired
      assert expired.order_id == order.order_id

      assert Enum.empty?(ob.sell_orders)
      assert Enum.empty?(ob.buy_orders)
    end
  end

  test "market sell orders fill the highest buys first" do
    quantity = 1
    expected_price = 100

    lower_buy =
      %PlaceOrder{
        order_id: UUID.uuid4(),
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: expected_price - 10,
        quantity: quantity
      }
    higher_buy =
      %PlaceOrder{
        order_id: UUID.uuid4(),
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: expected_price,
        quantity: quantity
      }

    market_sell =
      %PlaceOrder{
        order_id: UUID.uuid4(),
        type: :market,
        side: :sell,
        time_in_force: nil,
        price: nil,
        quantity: quantity
      }


    {ob, _} = apply_commands(Orderbook.new("BTCUSDT"), higher_buy)
    {ob, _} = apply_commands(ob, lower_buy)
    {_ob, events} = apply_commands(ob, market_sell)

    assert Enum.count(events) == 2
    [placed, trade] = events

    assert placed.order_id == market_sell.order_id
    assert placed.type == :market
    assert placed.side == :sell
    assert placed.quantity == quantity

    assert trade.sell_order_id == market_sell.order_id
    assert trade.buy_order_id == higher_buy.order_id
    assert trade.price == higher_buy.price
    assert trade.quantity == quantity
  end

  test "market buy orders fill the lowest sells first" do
    quantity = 1
    expected_price = 100

    lower_sell =
      %PlaceOrder{
        order_id: UUID.uuid4(),
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: expected_price - 10,
        quantity: quantity
      }
    higher_sell =
      %PlaceOrder{
        order_id: UUID.uuid4(),
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: expected_price,
        quantity: quantity
      }

    market_buy =
      %PlaceOrder{
        order_id: UUID.uuid4(),
        type: :market,
        side: :buy,
        time_in_force: nil,
        price: nil,
        quantity: quantity
      }


    {ob, _} = apply_commands(Orderbook.new("BTCUSDT"), lower_sell)
    {ob, _} = apply_commands(ob, higher_sell)
    {_ob, events} = apply_commands(ob, market_buy)

    assert Enum.count(events) == 2
    [placed, trade] = events

    assert placed.order_id == market_buy.order_id
    assert placed.type == :market
    assert placed.side == :buy
    assert placed.quantity == quantity

    assert trade.buy_order_id == market_buy.order_id
    assert trade.sell_order_id == lower_sell.order_id
    assert trade.price == lower_sell.price
    assert trade.quantity == quantity
  end

  test "stop loss sell orders place a market order when a trade price is equal to or less than the stop price" do
    unrelated_quantity = 1
    quantity = 1
    stop_price = 100

    stop_limit_sell =
      %PlaceOrder{
        order_id: "stop limit order ID",
        type: :stop_loss,
        side: :sell,
        stop_price: stop_price,
        quantity: quantity
      }

    remaining_buy =
      %PlaceOrder{
        order_id: "order the stop limit should buy ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price - 10,
        quantity: quantity
      }

    first_buy =
      %PlaceOrder{
        order_id: "First buy ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: unrelated_quantity
      }

    first_sell =
      %PlaceOrder{
        order_id: "First sell ID",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: unrelated_quantity
      }

    {ob, _} = apply_commands(Orderbook.new("BTCUSDT"), stop_limit_sell)
    {ob, _} = apply_commands(ob, remaining_buy)
    {ob, _} = apply_commands(ob, first_buy)
    {_ob, events} = apply_commands(ob, first_sell)

    assert Enum.count(events) == 3
    [_first_sell_placed, _first_trade, stop_limit_trade] = events

    assert stop_limit_trade.sell_order_id == stop_limit_sell.order_id
    assert stop_limit_trade.buy_order_id == remaining_buy.order_id
    assert stop_limit_trade.price == remaining_buy.price
    assert stop_limit_trade.quantity == quantity
  end

  test "take profit sell orders place a market order when a trade price is equal to or greater than the stop price" do
    unrelated_quantity = 1
    quantity = 1
    stop_price = 100

    take_profit_sell =
      %PlaceOrder{
        order_id: UUID.uuid4(),
        type: :take_profit,
        side: :sell,
        stop_price: stop_price,
        quantity: quantity
      }

    remaining_buy =
      %PlaceOrder{
        order_id: UUID.uuid4(),
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price + 10,
        quantity: quantity
      }

    first_buy =
      %PlaceOrder{
        order_id: UUID.uuid4(),
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: unrelated_quantity
      }

    first_sell =
      %PlaceOrder{
        order_id: UUID.uuid4(),
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: unrelated_quantity
      }

    {ob, _} = apply_commands(Orderbook.new("BTCUSDT"), take_profit_sell)
    {ob, _} = apply_commands(ob, remaining_buy)
    {ob, _} = apply_commands(ob, first_buy)
    {_ob, events} = apply_commands(ob, first_sell)

    assert Enum.count(events) == 3
    [_first_sell_placed, _first_trade, take_profit_trade] = events

    assert take_profit_trade.sell_order_id == take_profit_sell.order_id
    assert take_profit_trade.buy_order_id == remaining_buy.order_id
    assert take_profit_trade.price == remaining_buy.price
    assert take_profit_trade.quantity == quantity
  end

  defp apply_commands(ob, commands) when is_list(commands) do
    Enum.reduce(commands, {ob, []}, fn command, {ob, events} ->
      Logger.debug("Executing command #{inspect command}")
      new_events = Orderbook.execute(ob, command)
      ob =
        Enum.reduce(new_events, ob, fn event, ob ->
          Logger.debug("Applying event #{inspect event}")
          Orderbook.apply(ob, event)
        end)
      {ob, new_events ++ events}
    end)
  end

  defp apply_commands(ob, command) do
    apply_commands(ob, [command])
  end
end
