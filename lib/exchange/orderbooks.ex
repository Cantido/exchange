defmodule Exchange.Orderbooks do
  alias Exchange.Commanded
  alias Exchange.Orderbook.Schema.Trade
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
end
