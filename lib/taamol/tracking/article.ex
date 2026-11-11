defmodule Taamol.Tracking.Article do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "articles" do
    field :title, :string
    field :body, :string
    field :published, :date
    field :author, :string
    belongs_to :creator, Taamol.Accounts.User
    has_many :comments, Taamol.Tracking.Comment
    has_many :likes, Taamol.Tracking.ArticleLike

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(article, attrs) do
    article
    |> cast(attrs, [:title, :body, :published, :author])
    |> validate_required([:title, :creator_id])
    |> validate_length(:title, max: 100)
    |> foreign_key_constraint(:creator_id)
  end
end
