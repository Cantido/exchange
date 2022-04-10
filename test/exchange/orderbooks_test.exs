defmodule Exchange.OrderbooksTest do
  use Exchange.DataCase, async: true
  alias Exchange.Orderbooks
  doctest Exchange.Orderbooks

  test "trades returns the last 500 trades" do
    Exchange.Repo.insert(%Exchange.Orderbook.Schema.Symbol{symbol: "BTCUSDC"})

    trades_to_insert =
      Enum.map(1..510, fn i ->
        [
          symbol: "BTCUSDC",
          sell_order_id: UUID.uuid4(),
          buy_order_id: UUID.uuid4(),
          price: i,
          quantity: 1,
          maker: :seller,
          executed_at: DateTime.add(~U[2021-07-26T12:00:00.000000Z], i, :second)
        ]
      end)

    Exchange.Repo.insert_all(Exchange.Orderbook.Schema.Trade, trades_to_insert)

    trades = Orderbooks.trades("BTCUSDC")

    assert Enum.count(trades) == 500
    expected_first_timestamp = DateTime.add(~U[2021-07-26T12:00:00.000000Z], 510, :second)
    assert Enum.at(trades, 0).executed_at == expected_first_timestamp

    expected_last_timestamp = DateTime.add(~U[2021-07-26T12:00:00.000000Z], 11, :second)
    assert Enum.at(trades, -1).executed_at == expected_last_timestamp
  end

  test "klines returns valid candlesticks" do
    Exchange.Repo.insert(%Exchange.Orderbook.Schema.Symbol{symbol: "BTCUSDC"})

    trades_to_insert =
      Enum.map(1..119, fn i ->
        [
          symbol: "BTCUSDC",
          sell_order_id: UUID.uuid4(),
          buy_order_id: UUID.uuid4(),
          price: i,
          quantity: 1,
          maker: :seller,
          executed_at: DateTime.add(~U[2021-07-26T12:00:00.000000Z], i, :second)
        ]
      end)

    Exchange.Repo.insert_all(Exchange.Orderbook.Schema.Trade, trades_to_insert)

    candles =
      Orderbooks.klines(
        "BTCUSDC", :"1m",
        start_time: ~U[2021-07-26T12:00:01.000000Z],
        end_time: ~U[2021-07-26T12:01:59.000000Z]
      )

    assert Enum.count(candles) == 2

    first_candle = Enum.at(candles, 0)

    assert first_candle.open == 1
    assert first_candle.close == 59

    assert first_candle.high == 59
    assert first_candle.low == 1

    second_candle = Enum.at(candles, 1)

    assert second_candle.open == 60
    assert second_candle.close == 119

    assert second_candle.high == 119
    assert second_candle.low == 60

  end
end
