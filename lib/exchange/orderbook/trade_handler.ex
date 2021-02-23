defmodule Exchange.Orderbook.TradeHandler do
  use Commanded.Event.Handler,
    application: Exchange.Commanded,
    name: "TradeHandler"
  alias Exchange.Orderbook.TradeExecuted
  alias Exchange.Orderbook.Schema.Trade
  alias Exchange.Repo

  def handle(%TradeExecuted{} = event, _metadata) do
    %Trade{
      symbol: event.symbol,
      sell_order_id: event.sell_order_id,
      buy_order_id: event.buy_order_id,
      price: event.price,
      quantity: event.quantity,
      maker: event.maker
    }
    |> Repo.insert!()
  end
end
