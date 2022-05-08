defmodule Exchange.Account.Commands.LockFunds do
  @enforce_keys [
    :account_id,
    :order_id,
    :amount
  ]
  defstruct [
    :account_id,
    :order_id,
    :amount
  ]
end
