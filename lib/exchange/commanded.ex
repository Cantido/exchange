defmodule Exchange.Commanded do
  use Commanded.Application, otp_app: :exchange,
  event_store: [
    adapter: Application.fetch_env!(:commanded, :event_store_adapter),
    event_store: Exchange.EventStore
  ]
end
