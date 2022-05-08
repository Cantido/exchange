defmodule Exchange.Wallet do
  defstruct [
    balances: %{},
    locks: %{}
  ]

  def new do
    %__MODULE__{}
  end

  def add(%__MODULE__{balances: balances} = wallet, %Money{} = money) do
    balances =
      Map.update(balances, money.currency, money, &Money.add(&1, money))

    %__MODULE__{wallet | balances: balances}
  end

  def subtract(%__MODULE__{balances: balances} = wallet, money) do
    current_balance = get_balance(wallet, money.currency)

    if sufficient_balance?(wallet, money) do
      new_balances =
        Map.update(balances, money.currency, money, &Money.subtract(&1, money))

      %__MODULE__{wallet | balances: new_balances}
    else
      raise "Insufficient balance to subtract"
    end


  end

  def get_balance(%__MODULE__{balances: balances}, asset) do
    Map.get(balances, asset, Money.new(0, asset))
  end


  @doc """
  Checks if a balance contains at least some amount.

  ## Examples

      iex> Wallet.new()
      ...> |> Wallet.add(Money.new(5, :BTC))
      ...> |> Wallet.sufficient_balance?(Money.new(2, :BTC))
      true

      iex> Wallet.new()
      ...> |> Wallet.add(Money.new(5, :BTC))
      ...> |> Wallet.sufficient_balance?(Money.new(5, :BTC))
      true

      iex> Wallet.new()
      ...> |> Wallet.sufficient_balance?(Money.new(2, :BTC))
      false
  """
  def sufficient_balance?(wallet, money) do
    Money.cmp(get_balance(wallet, money.currency), money) in [:gt, :eq]
  end

  def locked_by?(%__MODULE__{locks: locks}, order_id) do
    Map.has_key?(locks, order_id)
  end

  def lock(%__MODULE__{balances: balances, locks: locks} = wallet, order_id, money) do
    current_balance = get_balance(wallet, money.currency)

    unless Money.cmp(current_balance, money) == :gt do
      raise "insufficient balance to lock"
    end
    if locked_by?(wallet, order_id) do
      raise "Funds already locked by order"
    end

    new_balance = Money.subtract(current_balance, money)

    %__MODULE__{
      balances: Map.put(balances, new_balance.currency, new_balance),
      locks: Map.put(locks, order_id, money)
    }
  end
end
