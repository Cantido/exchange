defmodule Exchange.Orderbook.SymbolProjector do
  use Commanded.Projections.Ecto,
    application: Exchange.Commanded,
    repo: Exchange.Repo,
    name: "SymbolProjector"
  alias Exchange.Orderbook.OrderbookOpened
  alias Exchange.Orderbook.Schema.Symbol

  project %OrderbookOpened{} = event, fn multi ->
    projection =
      %Symbol{
        symbol: event.symbol,
      }

    Ecto.Multi.insert(multi, :symbol_projection, projection)
  end
end
