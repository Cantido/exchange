defmodule Exchange.Account.Events.AccountCredited do
  @enforce_keys [
    :account_id,
    :amount
  ]
  defstruct [
    :account_id,
    :amount
  ]
end
