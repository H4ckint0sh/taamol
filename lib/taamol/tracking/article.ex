defmodule Taamol.Tracking.Article do
  use Ecto.Schema
  import Ecto.Changeset

  @categories [
    :community,
    :religion,
    :sweden,
    :world,
    :society,
    :culture,
    :education,
    :youth,
    :health,
    :sport
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "articles" do
    field :title, :string
    field :summary, :string
    field :body, :string
    field :published, :utc_datetime
    field :author, :string
    field :category, Ecto.Enum, values: @categories, default: :community
    field :cover_image_url, :string
    field :featured, :boolean, default: false
    field :view_count, :integer, default: 0
    belongs_to :creator, Taamol.Accounts.User
    has_many :comments, Taamol.Tracking.Comment
    has_many :likes, Taamol.Tracking.ArticleLike

    timestamps(type: :utc_datetime)
  end

  @doc "All article categories, in navigation order."
  def categories, do: @categories

  @doc false
  def changeset(article, attrs) do
    article
    |> cast(attrs, [
      :title,
      :summary,
      :body,
      :published,
      :author,
      :category,
      :cover_image_url,
      :featured
    ])
    |> validate_required([:title, :category, :creator_id])
    |> validate_length(:title, max: 100)
    |> validate_length(:summary, max: 300)
    |> validate_length(:cover_image_url, max: 2048)
    |> validate_format(:cover_image_url, ~r{^(https?://|/uploads/)[^\s]+$},
      message: "must be an http(s) URL or an uploaded image"
    )
    |> foreign_key_constraint(:creator_id)
  end
end
