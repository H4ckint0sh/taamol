defmodule Taamol.Tracking.ArticleLike do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "article_likes" do
    belongs_to :article, Taamol.Tracking.Article
    belongs_to :user, Taamol.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(like) do
    like
    |> change()
    |> validate_required([:article_id, :user_id])
    |> foreign_key_constraint(:article_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:article_id, :user_id])
  end
end
