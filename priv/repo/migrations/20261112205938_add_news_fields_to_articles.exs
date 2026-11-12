defmodule Taamol.Repo.Migrations.AddNewsFieldsToArticles do
  use Ecto.Migration

  def change do
    alter table(:articles) do
      # a publish time (not just a date) so the site can show "2 hours ago"
      modify :published, :utc_datetime, from: :date
      add :category, :string, null: false, default: "community"
      add :summary, :text
      add :cover_image_url, :string, size: 2048
      add :featured, :boolean, null: false, default: false
      add :view_count, :integer, null: false, default: 0
    end

    create index(:articles, [:published])
    create index(:articles, [:category, :published])
    create index(:articles, [:view_count])
  end
end
