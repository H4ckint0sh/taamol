defmodule Taamol.Gallery do
  @moduledoc """
  The photo gallery: images uploaded by administrators, newest first.
  """

  import Ecto.Query

  alias Taamol.Accounts
  alias Taamol.Accounts.{Scope, User}
  alias Taamol.Gallery.Image
  alias Taamol.Repo

  @doc "Lists images, newest first (`:limit`, default 14, and `:offset`)."
  def list_images(opts \\ []) do
    Image
    |> order_by([i], desc: i.inserted_at, desc: i.id)
    |> limit(^Keyword.get(opts, :limit, 14))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> Repo.all()
  end

  @doc "How many images there are."
  def count_images, do: Repo.aggregate(Image, :count)

  @doc "Gets an image, or nil (also for malformed ids)."
  def get_image(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Image, uuid)
      :error -> nil
    end
  end

  @doc "The newer and older neighbours of an image: `{previous, next}` (nil at the ends)."
  def neighbours(%Image{inserted_at: at, id: id}) do
    newer =
      from(i in Image,
        where: i.inserted_at > ^at or (i.inserted_at == ^at and i.id > ^id),
        order_by: [asc: i.inserted_at, asc: i.id],
        limit: 1
      )

    older =
      from(i in Image,
        where: i.inserted_at < ^at or (i.inserted_at == ^at and i.id < ^id),
        order_by: [desc: i.inserted_at, desc: i.id],
        limit: 1
      )

    {Repo.one(newer), Repo.one(older)}
  end

  @doc "Adds an uploaded image. Administrators only."
  def create_image(scope, image_url, attrs \\ %{}) do
    with_admin(scope, fn admin ->
      %Image{image_url: image_url, creator_id: admin.id}
      |> Image.changeset(attrs)
      |> Repo.insert()
    end)
  end

  @doc "Updates an image's caption. Administrators only."
  def update_image(scope, %Image{} = image, attrs) do
    with_admin(scope, fn _admin -> image |> Image.changeset(attrs) |> Repo.update() end)
  end

  @doc "Deletes an image. Administrators only. The caller removes the file."
  def delete_image(scope, %Image{} = image) do
    with_admin(scope, fn _admin -> Repo.delete(image) end)
  end

  defp with_admin(%Scope{user: %User{id: id}}, fun) do
    admin = Repo.get(User, id)

    if admin && Accounts.can?(Scope.for_user(admin), :manage_gallery),
      do: fun.(admin),
      else: {:error, :forbidden}
  end

  defp with_admin(_scope, _fun), do: {:error, :forbidden}
end
