defmodule Exchange.Orderbooks do
  alias Exchange.Commanded
  alias Exchange.Orderbook.Schema.Trade
  alias Exchange.Orderbook.Schema.Order
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
end
