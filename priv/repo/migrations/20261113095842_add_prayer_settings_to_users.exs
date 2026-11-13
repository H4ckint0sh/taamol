defmodule Taamol.Repo.Migrations.AddPrayerSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :prayer_settings, :map
    end
  end
end
