defmodule Exchange.Balance do
  @enforce_keys [
    :asset
  ]
  defstruct [
    asset: nil,
    free: 0,
    locks: %{}
  ]

  def new(asset) do
    %__MODULE__{asset: asset}
  end

  @doc """
  Add funds to this balance.

  ## Examples

      iex> Balance.new("BTC")
      ...> |> Balance.add(1)
      ...> |> Balance.free()
      1
  """
  def add(%__MODULE__{free: free} = balance, amount) do
    %__MODULE__{balance | free: free + amount}
  end

  @doc """
  Subtract funds from this balance. Raises if there are not enough funds.

  ## Examples

      iex> Balance.new("BTC")
      ...> |> Balance.add(5)
      ...> |> Balance.subtract(2)
      ...> |> Balance.free()
      3
  """
  def subtract(%__MODULE__{free: free} = balance, amount) do
    unless sufficient_balance?(balance, amount) do
      raise "Cannot subtract #{amount} from a balance of #{free}"
    end
    %__MODULE__{balance | free: free - amount}
  end

  def free(%__MODULE__{free: free}) do
    free
  end

  @doc """
  Checks if a balance contains at least some amount.

      iex> Balance.new("BTC")
      ...> |> Balance.add(5)
      ...> |> Balance.sufficient_balance?(2)
      true

      iex> Balance.new("BTC")
      ...> |> Balance.sufficient_balance?(2)
      false
  """
  def sufficient_balance?(%__MODULE__{free: free}, amount) do
    free - amount >= 0
  end

  def locked_by?(%__MODULE__{locks: locks}, order_id) do
    Map.has_key?(locks, order_id)
  end


  @doc """
  Lock funds for an order.

  ## Examples

      iex> Balance.new("BTC")
      ...> |> Balance.add(5)
      ...> |> Balance.lock("my order", 2)
      ...> |> Balance.free()
      3
  """
  def lock(%__MODULE__{free: free, locks: locks} = balance, order_id, amount) do
    unless sufficient_balance?(balance, amount) do
      raise "free funds too low to lock"
    end
    if locked_by?(balance, order_id) do
      raise "funds already locked for order #{order_id}"
    end

    %__MODULE__{balance |
      free: free - amount,
      locks: Map.put(locks, order_id, amount)
    }
  end
end
