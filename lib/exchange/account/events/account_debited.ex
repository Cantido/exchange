defmodule Exchange.Account.Events.AccountDebited do
  @enforce_keys [
    :account_id,
    :asset,
    :amount
  ]
  defstruct [
    :account_id,
    :asset,
    :amount
  ]
end
