defmodule Exchange.EventStoreCase do
  use ExUnit.CaseTemplate

  setup do
    on_exit(fn ->
      :ok = Application.stop(:exchange)
      :ok = Application.stop(:commanded)

      {:ok, _apps} = Application.ensure_all_started(:exchange)
    end)
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Exchange.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Exchange.Repo, {:shared, self()})
    end

    :ok
  end
end
