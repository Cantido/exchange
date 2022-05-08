defmodule Exchange.Account.Events.AccountDebited do
  @enforce_keys [
    :account_id,
    :amount
  ]
  defstruct [
    :account_id,
    :amount
  ]
end
