defmodule ExchangeWeb.DashboardLive do
  use ExchangeWeb, :live_view
  alias EventStore.RecordedEvent
  alias Exchange.EventStore

  def mount(%{"id" => symbol}, _, socket) do
    :ok = EventStore.subscribe("$all",
      selector: fn %RecordedEvent{event_type: type, data: data} ->
          type == "Elixir.Exchange.Orderbook.TradeExecuted" and
          data.symbol == symbol
      end,
      mapper: fn %RecordedEvent{data: data} -> data end)

    {:ok, load(socket, symbol)}
  end

  def handle_event("place_order", %{"order" => order}, socket) do
    Exchange.Commanded.dispatch(
      %Exchange.Orderbook.PlaceOrder{
        symbol: socket.assigns[:symbol],
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
    {:noreply, load(socket, "BTCUSDC")}
  end

  def handle_info({:events, events}, socket) do
    trades =
      Enum.map(events, &Map.take(&1, [:timestamp, :price]))
      |> Enum.map(fn event ->
        event
        |> Map.put(:executed_at, event.timestamp)
        |> Map.delete(:timestamp)
      end)
    {:noreply, push_event(socket, "trades", %{trades: trades})}
  end

  defp load(socket, symbol) do
    trades = Exchange.Orderbooks.trades(symbol) |> Enum.map(&Map.take(&1, [:executed_at, :price]))
    bids = Exchange.Orderbooks.bids(symbol)
    asks = Exchange.Orderbooks.asks(symbol)
    assign(socket, symbol: symbol, trades: trades, bids: bids, asks: asks)
  end
end
