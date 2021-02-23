defmodule Exchange.Orderbook.Schema.Trade do
  use Ecto.Schema

  schema "trades" do
    field :symbol, :string
    field :sell_order_id, :binary_id
    field :buy_order_id, :binary_id
    field :price, :integer
    field :quantity, :integer
    field :maker, Ecto.Enum, values: [:buyer, :seller]
  end
end
