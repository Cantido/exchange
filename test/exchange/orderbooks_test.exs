defmodule Exchange.OrderbooksTest do
  use Exchange.DataCase
  doctest Exchange.Orderbooks

  test "trades returns the last 500 trades" do
    trades_to_insert =
      Enum.map(1..510, fn i ->
        [
          symbol: "BTCUSDT",
          sell_order_id: UUID.uuid4(),
          buy_order_id: UUID.uuid4(),
          price: i,
          quantity: 1,
          maker: :seller,
          executed_at: DateTime.add(~U[2021-07-26T12:00:00.000000Z], i, :second)
        ]
      end)

    Exchange.Repo.insert_all(Exchange.Orderbook.Schema.Trade, trades_to_insert)


    trades = Exchange.Orderbooks.trades("BTCUSDT")

    assert Enum.count(trades) == 500
    expected_first_timestamp = DateTime.add(~U[2021-07-26T12:00:00.000000Z], 510, :second)
    assert Enum.at(trades, 0).executed_at == expected_first_timestamp

    expected_last_timestamp = DateTime.add(~U[2021-07-26T12:00:00.000000Z], 11, :second)
    assert Enum.at(trades, -1).executed_at == expected_last_timestamp
  end
end
