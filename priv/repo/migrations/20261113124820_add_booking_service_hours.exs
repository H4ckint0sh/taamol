defmodule Taamol.Repo.Migrations.AddBookingServiceHours do
  use Ecto.Migration

  def up do
    alter table(:booking_services) do
      add :opens_at, :time, null: false, default: "09:00:00"
      add :closes_at, :time, null: false, default: "22:00:00"
    end

    execute """
    UPDATE booking_services
    SET opens_at = '08:00:00', closes_at = '20:00:00', duration_minutes = 720
    WHERE name_sv = 'Lokal för minnesceremoni (khatm)'
       OR name_fa = 'سالن برای مراسم ختم'
    """
  end

  def down do
    alter table(:booking_services) do
      remove :opens_at
      remove :closes_at
    end
  end
end
