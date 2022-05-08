defmodule Exchange.Account.Commands.DebitAccount do
  @enforce_keys [
    :account_id,
    :amount
  ]
  defstruct [
    :account_id,
    :amount
  ]
end
