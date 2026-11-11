defmodule Taamol.Repo.Migrations.CreateArticlesAndComments do
  use Ecto.Migration

  def change do
    create table(:articles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false, size: 100
      add :body, :text
      add :published, :date
      add :author, :string
      add :creator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:articles, [:creator_id])

    create table(:comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false

      add :article_id, references(:articles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :creator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:comments, [:article_id])
    create index(:comments, [:creator_id])
    create unique_index(:comments, [:id, :article_id])

    alter table(:comments) do
      add :parent_id,
          references(:comments,
            type: :binary_id,
            with: [article_id: :article_id],
            on_delete: :delete_all
          )
    end

    create index(:comments, [:parent_id])

    create constraint(:comments, :comments_not_own_parent,
             check: "parent_id IS NULL OR parent_id <> id"
           )

    create table(:article_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :article_id, references(:articles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:article_likes, [:article_id, :user_id])
    create index(:article_likes, [:user_id])

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
