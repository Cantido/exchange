defmodule Exchange.Router do
  use Commanded.Commands.Router
  alias Exchange.Orderbook
  alias Exchange.Account

  identify Orderbook, by: :symbol
  identify Account, by: :account_id

  dispatch [
      Orderbook.OpenOrderbook,
      Orderbook.PlaceOrder
    ],
    to: Orderbook

  dispatch [
    Account.Commands.CreateAccount,
    Account.Commands.DebitAccount,
    Account.Commands.CreditAccount
  ],
  to: Account
end
