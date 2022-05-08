defmodule Exchange.Account.Commands.CreditAccount do
  @enforce_keys [
    :account_id,
    :amount
  ]
  defstruct [
    :account_id,
    :amount
  ]
end
