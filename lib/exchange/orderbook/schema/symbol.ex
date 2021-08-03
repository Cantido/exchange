defmodule Exchange.Orderbook.Schema.Symbol do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id
  schema "symbols" do
    field :symbol, :string, primary_key: true, null: false
    timestamps()
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [])
    |> validate_required([])
  end
end
