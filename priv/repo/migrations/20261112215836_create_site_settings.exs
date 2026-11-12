defmodule Taamol.Repo.Migrations.CreateSiteSettings do
  use Ecto.Migration

  def change do
    # a single row (id = 1) of site-wide settings managed by administrators
    create table(:site_settings) do
      add :hijri_adjustment_days, :integer, null: false, default: 0
      add :prayer_method, :string, null: false, default: "MWL"

      timestamps(type: :utc_datetime)
    end

    create constraint(:site_settings, :single_row, check: "id = 1")
  end
end
