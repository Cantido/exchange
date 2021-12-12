defmodule Exchange.Balance do
  @enforce_keys [
    :asset
  ]
  defstruct [
    asset: nil,
    free: 0,
    locked: 0
  ]

  def add(%__MODULE__{free: free} = balance, amount) do
    %__MODULE__{balance | free: free + amount}
  end
end
