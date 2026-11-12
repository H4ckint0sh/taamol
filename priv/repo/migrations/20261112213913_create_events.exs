defmodule Taamol.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false, size: 150
      add :description, :text
      add :location, :string
      add :kind, :string, null: false, default: "community"
      add :all_day, :boolean, null: false, default: false
      # local (community) time: the community is in one place, so no time zone
      add :starts_at, :naive_datetime, null: false
      add :ends_at, :naive_datetime
      add :creator_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:starts_at])
    create index(:events, [:creator_id])
  end
end
