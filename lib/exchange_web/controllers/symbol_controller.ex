defmodule ExchangeWeb.SymbolController do
  use ExchangeWeb, :controller
  alias Exchange.Orderbooks

  def index(conn, _params) do
    symbols = Orderbooks.symbols() |> Enum.map(& &1.symbol)
    render(conn, symbols: symbols)
  end

  def new(conn, _params) do
    render(conn, conn: conn, changeset: Ecto.Changeset.change(%Exchange.Orderbook.Schema.Symbol{}))
  end

  def create(conn, %{"symbol" => %{"symbol" => symbol}}) do
    Exchange.Commanded.dispatch(
      %Exchange.Orderbook.OpenOrderbook{
        symbol: symbol
      }
    )
    conn
    |> put_flash(:info, "Orderbook for symbol \"#{symbol}\" is being created.")
    |> redirect(to: Routes.symbol_path(conn, :index))
  end
end
