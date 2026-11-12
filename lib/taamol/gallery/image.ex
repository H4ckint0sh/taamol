defmodule Taamol.Gallery.Image do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "gallery_images" do
    field :image_url, :string
    field :caption, :string
    belongs_to :creator, Taamol.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for the caption (the image itself is set when uploading)."
  def changeset(image, attrs) do
    image
    |> cast(attrs, [:caption])
    |> validate_required([:image_url])
    |> validate_length(:caption, max: 255)
    |> validate_format(:image_url, ~r{^(https?://|/uploads/)[^\s]+$})
  end
end
