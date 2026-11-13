defmodule Taamol.Repo.Migrations.AddBookingLocationAndPrivacy do
  use Ecto.Migration

  def up do
    alter table(:booking_services) do
      add :private_calendar, :boolean, null: false, default: false
    end

    alter table(:bookings) do
      add :location_type, :string
      add :address, :string
    end

    execute """
    UPDATE booking_services
    SET private_calendar = true
    WHERE resource = 'imam'
      AND (name_sv = 'Imam för vigsel (nikah)' OR name_fa = 'امام برای عقد ازدواج')
    """

    execute """
    UPDATE booking_services
    SET active = false
    WHERE resource = 'premises'
      AND (name_sv = 'Lokal för firande' OR name_fa = 'سالن برای جشن')
    """
  end

  def down do
    alter table(:bookings) do
      remove :location_type
      remove :address
    end

    alter table(:booking_services) do
      remove :private_calendar
    end
  end
end
