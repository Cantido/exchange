defmodule Exchange.OrderPlacementTest do
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
  alias Exchange.Orderbook.RequestOrder
  alias Exchange.Orderbook.OrderRequested
  alias Exchange.Account.Commands.{
    CreateAccount,
    DebitAccount,
    CreditAccount
  }
  alias Exchange.Account.Events.{
    AccountCreated,
    AccountDebited,
    AccountCredited
  }
  alias Commanded.Aggregates.Aggregate
  require Logger
  import Commanded.Assertions.EventAssertions

  test "an account can place an order" do
    account_id = UUID.uuid4()
    maker_order_id = UUID.uuid4()
    taker_order_id = UUID.uuid4()
    price = Money.new(100, :USDC)
    available_quantity = Money.new(150, :BTC)
    wanted_quantity = Money.new(100, :BTC)

    make_market =
      %PlaceOrder{
        symbol: "BTCUSDC",
        order_id: maker_order_id,
        type: :limit,
        side: :sell,
        time_in_force: :good_til_cancelled,
        price: price,
        quantity: available_quantity,
        timestamp: ~U[2021-07-26T12:00:00.000000Z]
      }

    request_order =
      %RequestOrder{
        symbol: "BTCUSDC",
        account_id: account_id,
        order_id: taker_order_id,
        type: :limit,
        side: :buy,
        time_in_force: :good_til_cancelled,
        price: price,
        quantity: wanted_quantity,
        timestamp: ~U[2021-07-26T12:00:01.000000Z]
      }

    :ok = Exchange.Commanded.dispatch(%CreateAccount{account_id: account_id}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(%DebitAccount{account_id: account_id, amount: wanted_quantity}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(%OpenOrderbook{symbol: "BTCUSDC", base_asset: :BTC, quote_asset: :USDC}, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(make_market, consistency: :strong)
    :ok = Exchange.Commanded.dispatch(request_order, consistency: :strong)

    assert_receive_event(Exchange.Commanded, OrderRequested, fn placed ->
      assert placed.order_id == request_order.order_id
    end)

    assert_receive_event(Exchange.Commanded, OrderPlaced, fn placed ->
      placed.order_id == request_order.order_id
    end,
    fn placed ->
      assert placed.order_id == request_order.order_id
      assert placed.type == :limit
      assert placed.side == :buy
      assert placed.time_in_force == :good_til_cancelled
      assert placed.price == price
      assert placed.quantity == wanted_quantity
    end)

    assert_receive_event(Exchange.Commanded, TradeExecuted, fn executed ->
      assert executed.sell_order_id == maker_order_id
      assert executed.buy_order_id == taker_order_id
      assert executed.base_asset == :BTC
      assert executed.quote_asset == :USDC
      assert executed.price == price
      assert executed.quantity == wanted_quantity
      assert executed.maker == :seller
    end)
  end
end
