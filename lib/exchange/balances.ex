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


  @doc """
  Checks if a balance contains at least some amount.

  ## Examples

      iex> Balances.new()
      ...> |> Balances.add("BTC", 5)
      ...> |> Balances.sufficient_balance?("BTC", 2)
      true

      iex> Balances.new()
      ...> |> Balances.sufficient_balance?("BTC", 2)
      false
  """
  def sufficient_balance?(balances, asset, amount) do
    Map.has_key?(balances, asset) and Balance.sufficient_balance?(balances[asset], amount)
  end

  def locked_by?(balances, asset, order_id) do
    Map.has_key?(balances, asset) and Balance.locked_by?(balances[asset], order_id)
  end

  def lock(balances, order_id, asset, amount) do
    unless Map.has_key?(balances, asset) do
      raise "asset #{inspect asset} not in balances, cannot lock #{inspect amount} units"
    end
    Map.update!(
      balances,
      asset,
      fn balance -> Balance.lock(balance, order_id, amount) end
    )
  end
end
