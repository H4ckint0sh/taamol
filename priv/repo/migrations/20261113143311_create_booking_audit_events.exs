defmodule Taamol.Repo.Migrations.CreateBookingAuditEvents do
  use Ecto.Migration

  def up do
    create table(:booking_audit_events) do
      add :booking_id, references(:bookings, type: :binary_id, on_delete: :delete_all),
        null: false

      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :actor_name, :string
      add :action, :string, null: false
      add :details, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:booking_audit_events, [:booking_id, :inserted_at, :id])
    create index(:booking_audit_events, [:actor_id])

    execute """
    CREATE FUNCTION protect_booking_audit_events() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'UPDATE' AND OLD.actor_id IS NOT NULL AND NEW.actor_id IS NULL
         AND (to_jsonb(NEW) - 'actor_id') = (to_jsonb(OLD) - 'actor_id') THEN
        RETURN NEW;
      END IF;
      IF TG_OP = 'DELETE' AND pg_trigger_depth() > 1 THEN
        RETURN OLD;
      END IF;
      RAISE EXCEPTION 'booking audit events are immutable';
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER booking_audit_events_immutable
    BEFORE UPDATE OR DELETE ON booking_audit_events
    FOR EACH ROW EXECUTE FUNCTION protect_booking_audit_events()
    """
  end

  def down do
    execute "DROP TRIGGER booking_audit_events_immutable ON booking_audit_events"
    execute "DROP FUNCTION protect_booking_audit_events()"
    drop table(:booking_audit_events)
  end
end
