defmodule Exchange.OrderbookTest do
  use Exchange.EventStoreCase
  use ExUnitProperties
  alias Exchange.Orderbook
  alias Exchange.Orderbook.OpenOrderbook
  alias Exchange.Orderbook.OrderbookOpened
  alias Exchange.Orderbook.PlaceOrder
  alias Exchange.Orderbook.OrderPlaced
  alias Exchange.Orderbook.OrderFilled
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
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
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

  test "placing an order returns an error when the orderbook hasn't been opened yet" do
    command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "first command ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: 1,
        quantity: 1,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    {:error, :orderbook_not_opened} = Exchange.Commanded.dispatch(command, consistency: :strong)
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
        quantity: available_quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
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
        quantity: wanted_quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
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

    assert_receive_event(Exchange.Commanded, OrderFilled, fn filled ->
      assert filled.order_id == first_command.order_id
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
        quantity: available_quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
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
        quantity: wanted_quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
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
        quantity: available_quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
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
        quantity: wanted_quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
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
        quantity: available_quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    second_command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "second command ID",
        type: :limit,
        side: second_side,
        time_in_force: :immediate_or_cancel,
        price: price,
        quantity: wanted_quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
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
        quantity: available_quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    second_command =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "second command ID",
        type: :market,
        side: second_side,
        time_in_force: nil,
        price: nil,
        quantity: wanted_quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
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
        quantity: wanted_quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
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
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }
    higher_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "higher buy command ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: expected_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    market_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "market sell command ID",
        type: :market,
        side: :sell,
        time_in_force: nil,
        price: nil,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
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
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }
    higher_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "higher sell command ID",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: expected_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    market_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "market buy ID",
        type: :market,
        side: :buy,
        time_in_force: nil,
        price: nil,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:02Z]
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

  test "stop loss sell orders execute when the stop price is below market price" do
    unrelated_quantity = 1
    quantity = 1
    market_price = 90
    stop_price = 100
    eventual_trade_price = 80

    stop_limit_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "stop limit order ID",
        type: :stop_loss,
        side: :sell,
        stop_price: stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    remaining_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "order the stop limit should buy ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: eventual_trade_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    first_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "First buy ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:02Z]
      }

    first_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "First sell ID",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:03Z]
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

  test "stop loss buy orders are executed when market price is above the stop price" do
    unrelated_quantity = 1
    quantity = 1
    stop_price = 100
    market_price = 110
    eventual_trade_price = 120

    stop_limit_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "stop limit order ID",
        type: :stop_loss,
        side: :buy,
        stop_price: stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    remaining_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "order the stop limit should buy ID",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: eventual_trade_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    first_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "First buy ID",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:02Z]
      }

    first_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "First sell ID",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:03Z]
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(stop_limit_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(remaining_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_sell, consistency: :strong)

    assert_receive_event(Exchange.Commanded, TradeExecuted,
      fn event ->
        event.buy_order_id == stop_limit_buy.order_id
      end,
      fn stop_limit_trade ->
        assert stop_limit_trade.sell_order_id == remaining_sell.order_id
        assert stop_limit_trade.buy_order_id == stop_limit_buy.order_id
        assert stop_limit_trade.price == remaining_sell.price
        assert stop_limit_trade.quantity == quantity
      end)
  end

  test "take profit sell orders execute when market price is greater than the stop price" do
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
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    remaining_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "buy order that the take profit should match",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price + 10,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    first_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "buy order that should set the price for the take-profit sell",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:02Z]
      }

    first_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "sell order that should set the price for the take-profit sell",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:03Z]
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

  test "take profit buy orders execute when market price is lower than the stop price" do
    unrelated_quantity = 1
    quantity = 1
    market_price = 100
    stop_price = 110
    eventual_trade_price = 120

    take_profit_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "take profit sell command ID",
        type: :take_profit,
        side: :buy,
        stop_price: stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    remaining_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "buy order that the take profit should match",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: eventual_trade_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    first_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "buy order that should set the price for the take-profit sell",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:02Z]
      }

    first_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "sell order that should set the price for the take-profit sell",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:03Z]
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(take_profit_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(remaining_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_sell, consistency: :strong)

    assert_receive_event(Exchange.Commanded, TradeExecuted,
      fn event ->
        event.buy_order_id == take_profit_buy.order_id
      end,
      fn take_profit_trade ->
        assert take_profit_trade.sell_order_id == remaining_sell.order_id
        assert take_profit_trade.buy_order_id == take_profit_buy.order_id
        assert take_profit_trade.price == remaining_sell.price
        assert take_profit_trade.quantity == quantity
      end)
  end

  test "stop-loss-sell orders can trigger other stop-loss-sell orders by moving the price" do
    quantity = 1
    initial_trade_price = 100
    first_stop_price = initial_trade_price
    first_stop_trade_price = initial_trade_price - 10
    second_stop_price = first_stop_trade_price
    second_stop_trade_price = first_stop_trade_price - 10

    # The initial buy/sell get executed and matched first, setting the first price

    intial_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "First buy that triggers the first stop order",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: initial_trade_price,
        quantity: 1,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    initial_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "First sell that triggers the first stop order",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: initial_trade_price,
        quantity: 1,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    # The price set by the initial sell triggers the first stop order.
    # This trade lowers the price, since it executes as a market order.

    first_stop_limit_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "stop limit sell that gets executed first",
        type: :stop_loss,
        side: :sell,
        stop_price: first_stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:02Z]
      }

    buy_for_first_stop =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "Order that the first stop should buy",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: first_stop_trade_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:03Z]
      }

    # Since the price was lowered by the stop-loss order, that triggers another stop order.

    second_stop_limit_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "stop limit sell that gets executed second",
        type: :stop_loss,
        side: :sell,
        stop_price: second_stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:04Z]
      }

    buy_for_second_stop =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "Order that the second stop should buy",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: second_stop_trade_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:05Z]
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_stop_limit_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(second_stop_limit_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(buy_for_first_stop, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(buy_for_second_stop, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(intial_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(initial_sell, consistency: :strong)

    assert_receive_event(Exchange.Commanded, TradeExecuted,
      fn event ->
        event.sell_order_id == first_stop_limit_sell.order_id
      end,
      fn trade ->
        assert trade.sell_order_id == first_stop_limit_sell.order_id
        assert trade.buy_order_id == buy_for_first_stop.order_id
        assert trade.price == first_stop_trade_price
        assert trade.quantity == quantity
      end)

    assert_receive_event(Exchange.Commanded, TradeExecuted,
      fn event ->
        event.sell_order_id == second_stop_limit_sell.order_id
      end,
      fn trade ->
        assert trade.sell_order_id == second_stop_limit_sell.order_id
        assert trade.buy_order_id == buy_for_second_stop.order_id
        assert trade.price == second_stop_trade_price
        assert trade.quantity == quantity
      end)
  end

  test "market buy orders don't match existing stop-loss sell orders" do
    quantity = 1
    market_price = 110
    stop_price = 105

    stop_limit_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "stop limit order that should be left alone",
        type: :stop_loss,
        side: :sell,
        stop_price: stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    limit_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "order that the market order should buy",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    market_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "The order that should buy the limit sell",
        type: :market,
        side: :buy,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:02Z]
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(stop_limit_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(limit_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(market_buy, consistency: :strong)

    assert_receive_event(Exchange.Commanded, TradeExecuted,
      fn event ->
        event.buy_order_id == market_buy.order_id
      end,
      fn trade ->
        assert trade.sell_order_id == limit_sell.order_id
        assert trade.buy_order_id == market_buy.order_id
        assert trade.price == market_price
        assert trade.quantity == quantity
      end)
  end

  test "market sell orders don't match existing take-profit buy orders" do
    quantity = 1
    market_price = 105
    stop_price = 110

    take_profit_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "stop limit order that should be left alone",
        type: :take_profit,
        side: :buy,
        stop_price: stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    limit_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "order that the market order should buy",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    market_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "The order that should buy the limit sell",
        type: :market,
        side: :sell,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:02Z]
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(take_profit_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(limit_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(market_sell, consistency: :strong)

    assert_receive_event(Exchange.Commanded, TradeExecuted,
      fn event ->
        event.sell_order_id == market_sell.order_id
      end,
      fn trade ->
        assert trade.sell_order_id == market_sell.order_id
        assert trade.buy_order_id == limit_buy.order_id
        assert trade.price == market_price
        assert trade.quantity == quantity
      end)
  end

  test "stop-loss-limit sell orders can be executed once they are triggered" do
    unrelated_quantity = 1
    quantity = 1
    market_price = 100
    stop_price = 110

    stop_loss_limit_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "stop-loss-limit order",
        type: :stop_loss_limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        stop_price: stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    remaining_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "buy order that the stop-loss-limit should match",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    first_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "buy order that triggers the stop-loss-limit sell",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:02Z]
      }

    first_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "sell order that triggers the stop-loss-limit sell",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:03Z]
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(stop_loss_limit_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(remaining_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_sell, consistency: :strong)

    assert_receive_event(Exchange.Commanded, TradeExecuted,
      fn event ->
        event.sell_order_id == stop_loss_limit_sell.order_id
      end,
      fn trade ->
        assert trade.sell_order_id == stop_loss_limit_sell.order_id
        assert trade.buy_order_id == remaining_buy.order_id
        assert trade.price == stop_price
        assert trade.quantity == quantity
      end)
  end

  test "take-profit-limit sell orders can be executed once they are triggered" do
    unrelated_quantity = 1
    quantity = 1
    market_price = 100
    stop_price = 90

    take_profit_limit_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "take-profit-limit order",
        type: :take_profit_limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        stop_price: stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:00Z]
      }

    remaining_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "buy order that the take-profit-limit should match",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: stop_price,
        quantity: quantity,
        timestamp: ~U[2021-07-26T12:00:01Z]
      }

    first_buy =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "buy order that triggers the take-profit-limit sell",
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:02Z]
      }

    first_sell =
      %PlaceOrder{
        symbol: "BTCUSDT",
        order_id: "sell order that triggers the take-profit-limit sell",
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: market_price,
        quantity: unrelated_quantity,
        timestamp: ~U[2021-07-26T12:00:03Z]
      }

    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(take_profit_limit_sell, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(remaining_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_buy, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(first_sell, consistency: :strong)

    assert_receive_event(Exchange.Commanded, TradeExecuted,
      fn event ->
        event.sell_order_id == take_profit_limit_sell.order_id
      end,
      fn trade ->
        assert trade.sell_order_id == take_profit_limit_sell.order_id
        assert trade.buy_order_id == remaining_buy.order_id
        assert trade.price == stop_price
        assert trade.quantity == quantity
      end)
  end
end
