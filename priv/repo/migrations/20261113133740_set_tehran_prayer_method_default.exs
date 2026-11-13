defmodule Taamol.Repo.Migrations.SetTehranPrayerMethodDefault do
  use Ecto.Migration

  def up do
    alter table(:site_settings) do
      modify :prayer_method, :string, null: false, default: "Tehran"
    end

    execute "UPDATE site_settings SET prayer_method = 'Tehran' WHERE prayer_method <> 'Tehran'"
  end

  def down do
    alter table(:site_settings) do
      modify :prayer_method, :string, null: false, default: "MWL"
    end
  end
end
