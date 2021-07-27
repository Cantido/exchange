defmodule Exchange.Orderbook.Schema.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "orders" do
    field :symbol, :string
    field :side, Ecto.Enum, values: [:buy, :sell]
    field :type, Ecto.Enum, values: [
      :market, :limit, :stop_loss, :stop_loss_limit, :take_profit, :take_profit_limit, :limit_maker
    ]
    field :time_in_force, Ecto.Enum, values: [:good_til_cancelled, :immediate_or_cancel, :fill_or_kill]
    field :price, :integer
    field :quantity, :integer
    field :stop_price, :integer
    field :timestamp, :utc_datetime_usec

    timestamps()
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:side, :type, :time_in_force, :price, :stop_price, :quantity, :timestamp])
    |> validate_required([:side, :type, :time_in_force, :price, :stop_price, :quantity, :timestamp])
  end
end
