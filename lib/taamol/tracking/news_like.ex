defmodule Taamol.Tracking.NewsLike do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "news_likes" do
    belongs_to :news, Taamol.Tracking.News
    belongs_to :user, Taamol.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(like) do
    like
    |> change()
    |> validate_required([:news_id, :user_id])
    |> foreign_key_constraint(:news_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:news_id, :user_id])
  end
end
