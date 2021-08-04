defmodule Exchange.Orderbooks do
  alias Exchange.Commanded
  alias Exchange.Orderbook.Schema.Trade
  alias Exchange.Orderbook.Schema.Order
  alias Exchange.Orderbook.Schema.Symbol
  alias Exchange.Orderbook.OpenOrderbook
  alias Exchange.Orderbook.PlaceOrder
  alias Exchange.Repo
  import Ecto.Query

  def trades(symbol) do
    Repo.all(
      from t in Trade,
      where: t.symbol == ^symbol,
      order_by: [desc: t.executed_at],
      limit: 500
    )
  end

  def klines(symbol, interval, opts \\ []) do
    limit = min(1000, Keyword.get(opts, :limit, 500))
    interval_seconds =
      case interval do
        :"1m" -> 60
      end

    max_length_seconds = limit * interval_seconds

    start_time =
      Keyword.get(opts, :start_time, DateTime.utc_now())
      |> beginning_of_minute()

    stop_time =
      Keyword.get(opts, :end_time, DateTime.add(start_time, -max_length_seconds, :second))
      |> end_of_minute()

    Repo.all(
      from t in Trade,
      where: t.symbol == ^symbol,
      where: fragment("? between ? and ?", t.executed_at, ^start_time, ^stop_time),
      order_by: [asc: t.executed_at]
    )
    |> Enum.chunk_by(&beginning_of_minute(&1.executed_at))
    |> Enum.map(fn trades ->
        prices = Enum.map(trades, & &1.price)
        %{
          open_time: beginning_of_minute(Enum.at(trades, 0).executed_at),
          close_time: end_of_minute(Enum.at(trades, 0).executed_at),
          open: Enum.at(prices, 0),
          close: Enum.at(prices, -1),
          high: Enum.max(prices),
          low: Enum.min(prices),
          volume: Enum.map(trades, & &1.quantity) |> Enum.sum(),
          price_volume: Enum.sum(prices)
        }
    end)
  end

  defp end_of_minute(%DateTime{} = date) do
    {ms, precision} = date.microsecond

    if date.second == 0 and ms == 0 do
      date
    else
      %DateTime{
        date |
          second: 0,
          microsecond: {0, precision}
      }
      |> DateTime.add(60, :second)
    end
  end

  defp beginning_of_minute(%DateTime{} = date) do
    {ms, precision} = date.microsecond

    if date.second == 0 and ms == 0 do
      date
    else
      %DateTime{
        date |
          second: 0,
          microsecond: {0, precision}
      }
    end
  end

  def bids(symbol) do
    Repo.all(
      from o in Order,
      where: o.symbol == ^symbol,
      where: o.side == :buy,
      where: o.status in [:new],
      order_by: [desc: o.price],
      limit: 100
    )
  end

  def asks(symbol) do
    Repo.all(
      from o in Order,
      where: o.symbol == ^symbol,
      where: o.side == :sell,
      where: o.status in [:new],
      order_by: [asc: o.price],
      limit: 100
    )
  end

  def symbols do
    Repo.all(Symbol)
  end
end
