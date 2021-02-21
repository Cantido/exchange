defmodule Exchange.Router do
  use Commanded.Commands.Router
  alias Exchange.Orderbook

  identify Orderbook, by: :symbol

  dispatch [
      Orderbook.OpenOrderbook,
      Orderbook.PlaceOrder
    ],
    to: Orderbook,
    identity: :account_number
end
