defmodule Exchange.Account.Events.FundsLocked do
  @enforce_keys [
    :account_id,
    :order_id,
    :asset,
    :amount
  ]
  defstruct [
    :account_id,
    :order_id,
    :asset,
    :amount
  ]
end
