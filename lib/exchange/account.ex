defmodule Exchange.Account do
  alias Exchange.Account.Commands.{
    CreateAccount,
    DebitAccount
  }
  alias Exchange.Account.Events.{
    AccountCreated,
    AccountDebited
  }
  alias Exchange.Balance

  @enforce_keys :id
  defstruct [
    id: nil,
    balances: %{}
  ]

  def execute(%__MODULE__{id: nil}, %CreateAccount{account_id: id}) do
    %AccountCreated{account_id: id}
  end

  def execute(%__MODULE__{}, %DebitAccount{account_id: id, amount: amount, asset: asset}) do
    %AccountDebited{account_id: id, amount: amount, asset: asset}
  end

  def apply(%__MODULE__{id: nil}, %AccountCreated{account_id: id}) do
    %__MODULE__{id: id}
  end

  def apply(%__MODULE__{balances: balances} = account, %AccountDebited{amount: amount, asset: asset}) do
    new_balances =
      Map.update(
        balances,
        asset,
        %Balance{asset: asset, free: amount},
        fn balance -> Balance.add(balance, amount) end
      )

    %__MODULE__{account| balances: new_balances}
  end
end
