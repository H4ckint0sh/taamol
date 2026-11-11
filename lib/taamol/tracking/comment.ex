defmodule Taamol.Tracking.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "comments" do
    field :body, :string
    belongs_to :news, Taamol.Tracking.News
    belongs_to :creator, Taamol.Accounts.User
    belongs_to :parent, Taamol.Tracking.Comment
    has_many :replies, Taamol.Tracking.Comment, foreign_key: :parent_id
    has_many :likes, Taamol.Tracking.CommentLike

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> validate_required([:body, :news_id, :creator_id])
    |> foreign_key_constraint(:news_id)
    |> foreign_key_constraint(:creator_id)
    |> foreign_key_constraint(:parent_id)
    |> check_constraint(:parent_id, name: :comments_not_own_parent)
  end
end
