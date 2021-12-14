defmodule Exchange.Router do
  use Commanded.Commands.Router
  alias Exchange.Orderbook
  alias Exchange.Account

  identify Orderbook, by: :symbol
  identify Account, by: :account_id

  dispatch [
      Orderbook.OpenOrderbook,
      Orderbook.RequestOrder,
      Orderbook.PlaceOrder
    ],
    to: Orderbook

  dispatch [
    Account.Commands.CreateAccount,
    Account.Commands.DebitAccount,
    Account.Commands.CreditAccount,
    Account.Commands.LockFunds,
    Account.Commands.DeductLockedFunds,
    Account.Commands.UnlockFunds
  ],
  to: Account
end
