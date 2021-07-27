defmodule ExchangeWeb.HistoryLive do
  use ExchangeWeb, :live_view

  def mount(_, _, socket) do
    trades = Exchange.Orderbooks.trades("BTCUSDT")
    {:ok, assign(socket, symbol: "BTCUSDT", trades: trades)}
  end

  def handle_event("place", %{"order" => order}, socket) do
    Exchange.Commanded.dispatch(
      %Exchange.Orderbook.PlaceOrder{
        symbol: "BTCUSDT",
        order_id: UUID.uuid4(),
        type: :limit,
        side: parse_side(order["side"]),
        time_in_force: :good_til_cancelled,
        price: String.to_integer(order["price"]),
        quantity: String.to_integer(order["quantity"]),
        timestamp: DateTime.utc_now()
      },
      consistency: :strong
    )
    trades = Exchange.Orderbooks.trades("BTCUSDT")
    {:noreply, assign(socket, symbol: "BTCUSDT", trades: trades)}
  end

  defp parse_side("buy"), do: :buy
  defp parse_side("sell"), do: :sell

  def handle_event("open", _, socket) do
    :ok = Exchange.Commanded.dispatch(%Exchange.Orderbook.OpenOrderbook{symbol: "BTCUSDT"}, consistency: :strong)

    {:noreply, socket}
  end
end
