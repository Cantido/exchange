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
  alias Exchange.Wallet

  @enforce_keys :id
  defstruct [
    id: nil,
    wallet: Wallet.new()
  ]

  def execute(%__MODULE__{id: nil}, %CreateAccount{account_id: id}) do
    %AccountCreated{account_id: id}
  end

  def execute(%__MODULE__{}, %CreateAccount{}) do
    {:error, :account_already_exists}
  end

  def execute(%__MODULE__{}, %DebitAccount{account_id: id, amount: amount}) do
    %AccountDebited{account_id: id, amount: amount}
  end

  def execute(%__MODULE__{wallet: wallet}, %CreditAccount{account_id: id, amount: amount}) do
    if Wallet.sufficient_balance?(wallet, amount) do
      %AccountCredited{account_id: id, amount: amount}
    else
      {:error, :not_enough_funds}
    end
  end

  def execute(%__MODULE__{wallet: wallet}, %LockFunds{account_id: id, order_id: order_id, amount: amount}) do
    if Wallet.sufficient_balance?(wallet, amount) do
      %FundsLocked{account_id: id, order_id: order_id, amount: amount}
    else
      {:error, :not_enough_funds}
    end
  end

  def apply(%__MODULE__{id: nil}, %AccountCreated{account_id: id}) do
    %__MODULE__{id: id}
  end

  def apply(%__MODULE__{wallet: wallet} = account, %AccountDebited{amount: amount}) do
    %__MODULE__{account | wallet: Wallet.add(wallet, amount)}
  end

  def apply(%__MODULE__{wallet: wallet} = account, %AccountCredited{amount: amount}) do
    %__MODULE__{account | wallet: Wallet.subtract(wallet, amount)}
  end

  def apply(%__MODULE__{wallet: wallet} = account, %FundsLocked{order_id: order_id, amount: amount}) do
    %__MODULE__{account | wallet: Wallet.lock(wallet, order_id, amount)}
  end
end
