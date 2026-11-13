defmodule Taamol.Repo.Migrations.AddActorEmailToBookingAuditEvents do
  use Ecto.Migration

  def change do
    alter table(:booking_audit_events) do
      add :actor_email, :string
    end
  end
end
