defmodule Exchange.Account.Commands.DebitAccount do
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
