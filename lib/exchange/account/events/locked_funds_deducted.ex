defmodule Exchange.Account.Events.LockedFundsDeducted do
  @enforce_keys [
    :account_id,
    :order_id
  ]
  defstruct [
    :account_id,
    :order_id
  ]
end
