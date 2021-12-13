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

  def create(conn, %{"symbol" => %{"symbol" => symbol, "base_asset" => base_asset, "quote_asset" => quote_asset}}) do
    Exchange.Commanded.dispatch(
      %Exchange.Orderbook.OpenOrderbook{
        symbol: symbol,
        base_asset: base_asset,
        quote_asset: quote_asset
      }
    )
    conn
    |> put_flash(:info, "Orderbook for symbol \"#{symbol}\" is being created.")
    |> redirect(to: Routes.symbol_path(conn, :index))
  end
end
