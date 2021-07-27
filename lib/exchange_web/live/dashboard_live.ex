defmodule ExchangeWeb.DashboardLive do
  use ExchangeWeb, :live_view

  def mount(_, _, socket) do
    {:ok, load(socket, "BTCUSDT")}
  end

  def handle_event("place_order", %{"order" => order}, socket) do
    Exchange.Commanded.dispatch(
      %Exchange.Orderbook.PlaceOrder{
        symbol: "BTCUSDT",
        order_id: UUID.uuid4(),
        type: :limit,
        side: String.to_existing_atom(order["side"]),
        time_in_force: :good_til_cancelled,
        price: String.to_integer(order["price"]),
        quantity: String.to_integer(order["quantity"]),
        timestamp: DateTime.utc_now()
      },
      consistency: :strong
    )
    {:noreply, load(socket, "BTCUSDT")}
  end

  def handle_event("open", _, socket) do
    :ok = Exchange.Commanded.dispatch(%Exchange.Orderbook.OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)

    {:noreply, socket}
  end

  defp load(socket, symbol) do
    trades = Exchange.Orderbooks.trades(symbol)
    bids = Exchange.Orderbooks.bids(symbol)
    asks = Exchange.Orderbooks.asks(symbol)
    assign(socket, symbol: symbol, trades: trades, bids: bids, asks: asks)
  end
end
