defmodule Exchange.Balances do
  alias Exchange.Balance

  def new do
    %{}
  end

  def add(balances, asset, amount) do
    Map.update(
      balances,
      asset,
      %Balance{asset: asset, free: amount},
      fn balance -> Balance.add(balance, amount) end
    )
  end

  def subtract(balances, asset, amount) do
    Map.update!(
      balances,
      asset,
      fn balance -> Balance.subtract(balance, amount) end
    )
  end

  def get_balance(balances, asset) do
    Map.get(balances, asset, %Balance{asset: asset})
  end
end
