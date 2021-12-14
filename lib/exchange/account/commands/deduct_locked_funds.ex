defmodule Exchange.Account.Commands.DeductLockedFunds do
  @enforce_keys [
    :account_id,
    :order_id
  ]
  defstruct [
    :account_id,
    :order_id
  ]
end
