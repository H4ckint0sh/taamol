defmodule Taamol.Repo.Migrations.CreateNewsAndComments do
  use Ecto.Migration

  def change do
    create table(:news, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false, size: 100
      add :body, :text
      add :published, :date
      add :author, :string
      add :creator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:news, [:creator_id])

    create table(:comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false
      add :news_id, references(:news, type: :binary_id, on_delete: :delete_all), null: false
      add :creator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:comments, [:news_id])
    create index(:comments, [:creator_id])
    create unique_index(:comments, [:id, :news_id])

    alter table(:comments) do
      add :parent_id,
          references(:comments,
            type: :binary_id,
            with: [news_id: :news_id],
            on_delete: :delete_all
          )
    end

    create index(:comments, [:parent_id])

    create constraint(:comments, :comments_not_own_parent,
             check: "parent_id IS NULL OR parent_id <> id"
           )

    create table(:news_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :news_id, references(:news, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:news_likes, [:news_id, :user_id])
    create index(:news_likes, [:user_id])

    create table(:comment_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :comment_id, references(:comments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:comment_likes, [:comment_id, :user_id])
    create index(:comment_likes, [:user_id])
  end
end
