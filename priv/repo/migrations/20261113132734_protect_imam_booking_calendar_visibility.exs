defmodule Taamol.Repo.Migrations.ProtectImamBookingCalendarVisibility do
  use Ecto.Migration

  def up do
    alter table(:bookings) do
      add :private_calendar, :boolean, null: false, default: false
    end

    execute """
    UPDATE bookings AS b
    SET private_calendar = true
    FROM booking_services AS s
    WHERE b.service_id = s.id AND s.resource = 'imam'
    """

    alter table(:booking_services) do
      remove :private_calendar
    end
  end

  def down do
    alter table(:booking_services) do
      add :private_calendar, :boolean, null: false, default: false
    end

    execute """
    UPDATE booking_services
    SET private_calendar = true
    WHERE resource = 'imam'
      AND (name_sv = 'Imam för vigsel (nikah)' OR name_fa = 'امام برای عقد ازدواج')
    """

    alter table(:bookings) do
      remove :private_calendar
    end
  end
end
