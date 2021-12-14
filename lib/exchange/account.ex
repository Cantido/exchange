defmodule Exchange.Account do
  alias Exchange.Account.Commands.{
    CreateAccount,
    DebitAccount,
    CreditAccount,
    LockFunds,
    DeductLockedFunds,
    UnlockFunds
  }
  alias Exchange.Account.Events.{
    AccountCreated,
    AccountDebited,
    AccountCredited,
    FundsLocked,
    FundsUnlocked,
    LockedFundsDeducted
  }
  alias Exchange.{Balance, Balances}

  @enforce_keys :id
  defstruct [
    id: nil,
    balances: Balances.new()
  ]

  def execute(%__MODULE__{id: nil}, %CreateAccount{account_id: id}) do
    %AccountCreated{account_id: id}
  end

  def execute(%__MODULE__{}, %CreateAccount{}) do
    {:error, :account_already_exists}
  end

  def execute(%__MODULE__{}, %DebitAccount{account_id: id, amount: amount, asset: asset}) do
    %AccountDebited{account_id: id, amount: amount, asset: asset}
  end

  def execute(%__MODULE__{balances: balances}, %CreditAccount{account_id: id, amount: amount, asset: asset}) do
    if Balances.sufficient_balance?(balances, asset, amount) do
      %AccountCredited{account_id: id, amount: amount, asset: asset}
    else
      {:error, :not_enough_funds}
    end
  end

  def execute(%__MODULE__{balances: balances}, %LockFunds{account_id: id, order_id: order_id, amount: amount, asset: asset}) do
    if Balances.sufficient_balance?(balances, asset, amount) do
      %FundsLocked{account_id: id, order_id: order_id, amount: amount, asset: asset}
    else
      {:error, :not_enough_funds}
    end
  end

  def apply(%__MODULE__{id: nil}, %AccountCreated{account_id: id}) do
    %__MODULE__{id: id}
  end

  def apply(%__MODULE__{balances: balances} = account, %AccountDebited{amount: amount, asset: asset}) do
    %__MODULE__{account | balances: Balances.add(balances, asset, amount)}
  end

  def apply(%__MODULE__{balances: balances} = account, %AccountCredited{amount: amount, asset: asset}) do
    %__MODULE__{account | balances: Balances.subtract(balances, asset, amount)}
  end

  def apply(%__MODULE__{balances: balances} = account, %FundsLocked{order_id: order_id, amount: amount, asset: asset}) do
    %__MODULE__{account | balances: Balances.lock(balances, order_id, asset, amount)}
  end
end
