defmodule Exchange.Repo.Migrations.AddTrades do
  use Ecto.Migration

  def change do
    create table("trades") do
      add :symbol, :string, null: false
      add :sell_order_id, :binary_id, null: false
      add :buy_order_id, :binary_id, null: false
      add :price, :integer, null: false
      add :quantity, :integer, null: false
      add :maker, :string, null: false
    end
  end
end
