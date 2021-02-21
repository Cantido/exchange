defmodule Exchange.EventStoreCase do
  use ExUnit.CaseTemplate

  setup do
    on_exit(fn ->
      :ok = Application.stop(:exchange)
      :ok = Application.stop(:commanded)

      {:ok, _apps} = Application.ensure_all_started(:exchange)
    end)
  end
end
