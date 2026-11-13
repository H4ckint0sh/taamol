defmodule Taamol.Bookings.AuditEvent do
  @moduledoc "An append-only snapshot of a booking transition."
  use Ecto.Schema

  schema "booking_audit_events" do
    belongs_to :booking, Taamol.Bookings.Booking, type: :binary_id
    belongs_to :actor, Taamol.Accounts.User, type: :binary_id
    field :actor_name, :string
    field :actor_email, :string
    field :action, :string
    field :details, :map, default: %{}
    field :inserted_at, :utc_datetime_usec
  end
end
