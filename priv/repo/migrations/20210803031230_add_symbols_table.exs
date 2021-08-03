defmodule Exchange.Repo.Migrations.AddSymbolsTable do
  use Ecto.Migration

  def change do
    create table("symbols", primary_key: false) do
      add :symbol, :string, primary_key: true
      timestamps()
    end

    alter table("orders") do
      modify :symbol, references("symbols", column: :symbol, type: :string)
    end

    alter table("trades") do
      modify :symbol, references("symbols", column: :symbol, type: :string)
    end
  end
end
