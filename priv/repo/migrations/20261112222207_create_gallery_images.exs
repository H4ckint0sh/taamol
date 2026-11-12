defmodule Taamol.Repo.Migrations.CreateGalleryImages do
  use Ecto.Migration

  def change do
    create table(:gallery_images, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :image_url, :string, null: false, size: 2048
      add :caption, :string
      add :creator_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:gallery_images, [:inserted_at])
  end
end
