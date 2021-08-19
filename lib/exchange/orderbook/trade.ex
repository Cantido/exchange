defmodule Exchange.Orderbook.Trade do
  alias Exchange.Orderbook.TradeExecuted

  def execute(maker_order, taker_order, symbol) do
    case taker_order.side do
      :sell ->
        %TradeExecuted{
          symbol: symbol,
          sell_order_id: taker_order.order_id,
          buy_order_id: maker_order.order_id,
          price: maker_order.price,
          quantity: min(taker_order.quantity, maker_order.quantity),
          maker: :buyer,
          timestamp: taker_order.timestamp
        }
      :buy ->
        %TradeExecuted{
          symbol: symbol,
          sell_order_id: maker_order.order_id,
          buy_order_id: taker_order.order_id,
          price: maker_order.price,
          quantity: min(maker_order.quantity, taker_order.quantity),
          maker: :seller,
          timestamp: taker_order.timestamp
        }
    end
  end
end
