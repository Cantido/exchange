defmodule OrderbookTest do
  use Exchange.EventStoreCase
  use ExUnitProperties
  alias Exchange.Orderbook
  alias Exchange.Orderbook.OpenOrderbook
  alias Exchange.Orderbook.OrderbookOpened
  alias Exchange.Orderbook.PlaceOrder
  alias Exchange.Orderbook.OrderPlaced
  alias Exchange.Orderbook.OrderExpired
  alias Exchange.Orderbook.TradeExecuted
  alias Commanded.Aggregates.Aggregate
  require Logger
  import Commanded.Assertions.EventAssertions
  doctest Exchange.Orderbook

  test "open orderbook" do
    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"})

    assert_receive_event(Exchange.Commanded, OrderbookOpened, fn event ->
      assert event.symbol == "BTCUSDT"
    end)
  end

  test "placing a GTC limit order emits an order_placed event" do
    side = :sell
    quantity = 100
    price = 100

    command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "first command ID",
        type: :limit,
        side: side,
        time_in_force: :good_til_cancelled,
        price: price,
        quantity: quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(command, consistency: :strong)

    assert_receive_event(Exchange.Commanded, OrderPlaced, fn placed ->
      assert placed.order_id == command.order_id
      assert placed.type == :limit
      assert placed.side == side
      assert placed.time_in_force == :good_til_cancelled
      assert placed.price == price
      assert placed.quantity == quantity
    end)
  end

  test "good-til-cancelled limit orders match everything available and then go on the books" do
    price = 100
    first_side = :buy
    available_quantity = 100
    wanted_quantity = 150

    first_command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "first command ID",
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
        symbol: "BTCUSDT",
        order_id: "second command ID",
        type: :limit,
        side: second_side,
        time_in_force: :good_til_cancelled,
        price: price,
        quantity: wanted_quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_command, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(second_command, consistency: :strong)

    {sell_id, buy_id} =
      case first_side do
        :buy -> {second_command.order_id, first_command.order_id}
        :sell -> {first_command.order_id, second_command.order_id}
      end

    maker =
      case first_side do
        :buy -> :buyer
        :sell -> :seller
      end

    assert_receive_event(Exchange.Commanded, TradeExecuted, fn executed ->
      assert executed.sell_order_id == sell_id
      assert executed.buy_order_id == buy_id
      assert executed.price == price
      assert executed.quantity == available_quantity
      assert executed.maker == maker
    end)
  end

  test "good-til-cancelled limit orders can get partially filled by later orders" do
    price = 100
    first_side = :buy
    wanted_quantity = 100
    available_quantity = wanted_quantity + 50

    first_command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "first command ID",
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
        symbol: "BTCUSDT",
        order_id: "second command ID",
        type: :limit,
        side: second_side,
        time_in_force: :good_til_cancelled,
        price: price,
        quantity: wanted_quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_command, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(second_command, consistency: :strong)

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

    assert_receive_event(Exchange.Commanded, TradeExecuted, fn trade ->
      assert trade.sell_order_id == sell_command.order_id
      assert trade.buy_order_id == buy_command.order_id
      assert trade.price == price
      assert trade.quantity == wanted_quantity
      assert trade.maker == maker
    end)

    ob = Aggregate.aggregate_state(Exchange.Commanded, Orderbook, "BTCUSDT")

    [{_, remaining_order}] = Map.to_list(ob.orders)

    assert remaining_order.quantity == available_quantity - wanted_quantity
  end

  test "fill-or-kill order is cancelled if there is not enough quantity on the books" do
    price = 100
    first_side = :buy
    available_quantity = 100
    wanted_quantity = available_quantity + 50

    first_command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "first command ID",
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
        symbol: "BTCUSDT",
        order_id: "second command ID",
        type: :limit,
        side: second_side,
        time_in_force: :fill_or_kill,
        price: price,
        quantity: wanted_quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_command, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(second_command, consistency: :strong)

    assert_receive_event(Exchange.Commanded, OrderExpired, fn expired ->
      assert expired.order_id == second_command.order_id
    end)

    ob = Aggregate.aggregate_state(Exchange.Commanded, Orderbook, "BTCUSDT")

    [{_, remaining_order}] = Map.to_list(ob.orders)

    assert remaining_order.quantity == available_quantity
  end

  test "immediate-or-cancel order is partially filled and the rest is cancelled" do
    price = 100
    first_side = :buy
    available_quantity = 100
    wanted_quantity = available_quantity + 50

    second_side =
      case first_side do
        :buy -> :sell
        :sell -> :buy
      end

    first_command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "first command ID",
        type: :limit,
        side: first_side,
        time_in_force: :good_til_cancelled,
        price: price,
        quantity: available_quantity
      }

    second_command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "second command ID",
        type: :limit,
        side: second_side,
        time_in_force: :immediate_or_cancel,
        price: price,
        quantity: wanted_quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_command, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(second_command, consistency: :strong)

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

    assert_receive_event(Exchange.Commanded, TradeExecuted, fn trade ->
      assert trade.sell_order_id == sell_command.order_id
      assert trade.buy_order_id == buy_command.order_id
      assert trade.price == price
      assert trade.quantity == available_quantity
      assert trade.maker == maker
    end)

    assert_receive_event(Exchange.Commanded, OrderExpired, fn second_expired ->
      assert second_expired.__struct__ == OrderExpired
      assert second_expired.order_id == second_command.order_id
    end)

    ob = Aggregate.aggregate_state(Exchange.Commanded, Orderbook, "BTCUSDT")

    assert Enum.empty?(ob.orders)
  end

  test "market orders can partially fill then expire" do
    price = 100
    first_side = :buy
    available_quantity = 100
    wanted_quantity = available_quantity + 50

    second_side =
      case first_side do
        :buy -> :sell
        :sell -> :buy
      end

    first_command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "first command ID",
        type: :limit,
        side: first_side,
        time_in_force: :good_til_cancelled,
        price: price,
        quantity: available_quantity
      }

    second_command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "second command ID",
        type: :market,
        side: second_side,
        time_in_force: nil,
        price: nil,
        quantity: wanted_quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_command, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(second_command, consistency: :strong)

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

    assert_receive_event(Exchange.Commanded, OrderPlaced,
      fn event ->
        event.order_id == second_command.order_id
      end,
      fn placed ->
        assert placed.order_id == second_command.order_id
        assert placed.type == :market
        assert placed.side == second_side
        assert is_nil(placed.price)
        assert placed.quantity == wanted_quantity
      end)

    assert_receive_event(Exchange.Commanded, TradeExecuted, fn trade ->
      assert trade.sell_order_id == sell_command.order_id
      assert trade.buy_order_id == buy_command.order_id
      assert trade.price == price
      assert trade.quantity == available_quantity
      assert trade.maker == maker
    end)

    assert_receive_event(Exchange.Commanded, OrderExpired, fn second_expired ->
      assert second_expired.order_id == second_command.order_id
    end)

    ob = Aggregate.aggregate_state(Exchange.Commanded, Orderbook, "BTCUSDT")

    assert Enum.empty?(ob.orders)
  end

  test "market orders expire immediately if no orders are available" do
    side = :buy
    wanted_quantity = 100

    order =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "order command ID",
        type: :market,
        side: side,
        time_in_force: nil,
        price: nil,
        quantity: wanted_quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(order, consistency: :strong)

    assert_receive_event(Exchange.Commanded, OrderPlaced, fn placed ->
      assert placed.__struct__ == OrderPlaced
      assert placed.order_id == order.order_id
      assert placed.type == :market
      assert placed.side == side
      assert is_nil(placed.price)
      assert placed.quantity == wanted_quantity
    end)

    assert_receive_event(Exchange.Commanded, OrderExpired, fn expired ->
      assert expired.order_id == order.order_id
    end)

    ob = Aggregate.aggregate_state(Exchange.Commanded, Orderbook, "BTCUSDT")

    assert Enum.empty?(ob.orders)
  end

  test "market sell orders fill the highest buys first" do
    quantity = 1
    expected_price = 100

    lower_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "lower buy command ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: expected_price - 10,
        quantity: quantity
      }
    higher_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "higher buy command ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: expected_price,
        quantity: quantity
      }

    market_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "market sell command ID",
        type: :market,
        side: :sell,
        time_in_force: nil,
        price: nil,
        quantity: quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(higher_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(lower_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(market_sell, consistency: :strong)

    assert_receive_event(Exchange.Commanded, OrderPlaced,
      fn event ->
        event.order_id == market_sell.order_id
      end,
      fn placed ->
        assert placed.order_id == market_sell.order_id
        assert placed.type == :market
        assert placed.side == :sell
        assert placed.quantity == quantity
      end)

    assert_receive_event(Exchange.Commanded, TradeExecuted, fn trade ->
      assert trade.sell_order_id == market_sell.order_id
      assert trade.buy_order_id == higher_buy.order_id
      assert trade.price == higher_buy.price
      assert trade.quantity == quantity
    end)
  end

  test "market buy orders fill the lowest sells first" do
    quantity = 1
    expected_price = 100

    lower_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "lower sell command ID",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: expected_price - 10,
        quantity: quantity
      }
    higher_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "higher sell command ID",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: expected_price,
        quantity: quantity
      }

    market_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "market buy ID",
        type: :market,
        side: :buy,
        time_in_force: nil,
        price: nil,
        quantity: quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(lower_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(higher_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(market_buy, consistency: :strong)

    assert_receive_event(Exchange.Commanded, OrderPlaced,
      fn event ->
        event.order_id == market_buy.order_id
      end,
      fn placed ->
        assert placed.order_id == market_buy.order_id
        assert placed.type == :market
        assert placed.side == :buy
        assert placed.quantity == quantity
      end)

    assert_receive_event(Exchange.Commanded, TradeExecuted, fn trade ->
      assert trade.buy_order_id == market_buy.order_id
      assert trade.sell_order_id == lower_sell.order_id
      assert trade.price == lower_sell.price
      assert trade.quantity == quantity
    end)
  end

  test "stop loss sell orders place a market order when a trade price is equal to or less than the stop price" do
    unrelated_quantity = 1
    quantity = 1
    stop_price = 100

    stop_limit_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "stop limit order ID",
        type: :stop_loss,
        side: :sell,
        stop_price: stop_price,
        quantity: quantity
      }

    remaining_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "order the stop limit should buy ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price - 10,
        quantity: quantity
      }

    first_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "First buy ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: unrelated_quantity
      }

    first_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "First sell ID",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: unrelated_quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(stop_limit_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(remaining_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_sell, consistency: :strong)

    assert_receive_event(Exchange.Commanded, TradeExecuted,
      fn event ->
        event.sell_order_id == stop_limit_sell.order_id
      end,
      fn stop_limit_trade ->
        assert stop_limit_trade.sell_order_id == stop_limit_sell.order_id
        assert stop_limit_trade.buy_order_id == remaining_buy.order_id
        assert stop_limit_trade.price == remaining_buy.price
        assert stop_limit_trade.quantity == quantity
      end)
  end

  test "take profit sell orders place a market order when a trade price is equal to or greater than the stop price" do
    unrelated_quantity = 1
    quantity = 1
    stop_price = 100

    take_profit_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "take profit sell command ID",
        type: :take_profit,
        side: :sell,
        stop_price: stop_price,
        quantity: quantity
      }

    remaining_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "buy order that the take profit should match",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price + 10,
        quantity: quantity
      }

    first_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "buy order that should set the price for the take-profit sell",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: unrelated_quantity
      }

    first_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "sell order that should set the price for the take-profit sell",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: unrelated_quantity
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(take_profit_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(remaining_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_sell, consistency: :strong)

    assert_receive_event(Exchange.Commanded, TradeExecuted,
      fn event ->
        event.sell_order_id == take_profit_sell.order_id
      end,
      fn take_profit_trade ->
        assert take_profit_trade.sell_order_id == take_profit_sell.order_id
        assert take_profit_trade.buy_order_id == remaining_buy.order_id
        assert take_profit_trade.price == remaining_buy.price
        assert take_profit_trade.quantity == quantity
      end)
  end
end