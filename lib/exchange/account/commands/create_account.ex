defmodule Exchange.Account.Commands.CreateAccount do
  @enforce_keys [
    :account_id
  ]
  defstruct [
    :account_id
  ]
end
