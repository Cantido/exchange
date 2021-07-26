defmodule Exchange.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :side, :string, null: false
      add :time_in_force, :string, null: false
      add :price, :integer, null: false
      add :stop_price, :integer
      add :quantity, :integer, null: false
      add :timestamp, :utc_datetime_usec, null: false

      timestamps()
    end

  end
end
