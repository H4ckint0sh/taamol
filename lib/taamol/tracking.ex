defmodule Taamol.Tracking do
  @moduledoc """
  Operations for articles, comments, replies, and likes.
  """

  import Ecto.Query

  alias Taamol.Accounts.{Scope, User, Helpers}
  alias Taamol.Repo
  alias Taamol.Tracking.{Article, ArticleLike, Comment, CommentLike}

  @doc """
  Lists published articles.
  """
  def list_public_articles(opts \\ []) do
    today = Date.utc_today()

    Repo.all(
      from n in Article,
        where: not is_nil(n.published) and n.published <= ^today,
        order_by: [desc: n.published, desc: n.inserted_at, desc: n.id],
        preload: [:creator],
        limit: ^Keyword.get(opts, :limit, 10),
        offset: ^Keyword.get(opts, :offset, 0)
    )
  end

  @doc """
  Gets a single article.
  """
  def get_article_by_id!(id) do
    Repo.get!(Article, id)
  end

  @doc """
  Creates an article for the current administrator.

  Returns `{:error, :forbidden}` if the user is not an administrator.
  """
  def create_article(%Scope{user: %User{id: user_id}}, attrs) do
    Repo.transact(fn ->
      admin =
        Repo.one(
          from u in User,
            where: u.id == ^user_id and u.role == :admin,
            lock: "FOR SHARE"
        )

      if admin do
        %Article{creator_id: admin.id}
        |> Article.changeset(attrs)
        |> Repo.insert()
      else
        {:error, :forbidden}
      end
    end)
  end

  def create_article(_scope, _attrs), do: {:error, :forbidden}

  def change_article(%Scope{user: %User{id: user_id}}, %Article{} = article, attrs \\ %{}) do
    if Helpers.find_admin_with_lock(user_id) do
      Article.changeset(article, attrs)
    else
      {:error, :forbidden}
    end
  end

  @doc "Likes an article once per user."
  def like_article(%Scope{user: %User{id: user_id}}, %Article{id: article_id}) do
    %ArticleLike{article_id: article_id, user_id: user_id}
    |> ArticleLike.changeset()
    |> Repo.insert()
  end

  @doc "Removes the current user's article like, if present."
  def unlike_article(%Scope{user: %User{id: user_id}}, %Article{id: article_id}) do
    {count, _} =
      Repo.delete_all(
        from l in ArticleLike, where: l.article_id == ^article_id and l.user_id == ^user_id
      )

    {:ok, count}
  end

  @doc "Counts the user-attributed likes on an article."
  def count_article_likes(%Scope{user: %User{}}, %Article{id: article_id}) do
    Repo.aggregate(from(l in ArticleLike, where: l.article_id == ^article_id), :count, :id)
  end

  @doc "Checks whether the current user liked an article."
  def liked_article?(%Scope{user: %User{id: user_id}}, %Article{id: article_id}) do
    Repo.exists?(
      from l in ArticleLike, where: l.article_id == ^article_id and l.user_id == ^user_id
    )
  end

  @doc "Creates a comment on an article for the current user."
  def create_comment(%Scope{user: %User{id: user_id}}, %Article{id: article_id}, attrs) do
    %Comment{article_id: article_id, creator_id: user_id}
    |> Comment.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists the top-level comments on an article with their creators."
  def list_comments(%Scope{user: %User{}}, %Article{id: article_id}) do
    Repo.all(
      from c in Comment,
        where: c.article_id == ^article_id and is_nil(c.parent_id),
        order_by: [asc: c.inserted_at, asc: c.id],
        preload: [:creator]
    )
  end

  @doc "Creates a reply on the same article as its parent."
  def reply_to_comment(%Scope{user: %User{id: user_id}}, %Comment{id: parent_id}, attrs) do
    case Repo.get(Comment, parent_id) do
      nil ->
        {:error, :not_found}

      parent ->
        %Comment{article_id: parent.article_id, parent_id: parent.id, creator_id: user_id}
        |> Comment.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc "Lists a comment's direct replies with their creators."
  def list_replies(%Scope{user: %User{}}, %Comment{id: parent_id}) do
    Repo.all(
      from c in Comment,
        where: c.parent_id == ^parent_id,
        order_by: [asc: c.inserted_at, asc: c.id],
        preload: [:creator]
    )
  end

  @doc "Likes a comment once per user."
  def like_comment(%Scope{user: %User{id: user_id}}, %Comment{id: comment_id}) do
    %CommentLike{comment_id: comment_id, user_id: user_id}
    |> CommentLike.changeset()
    |> Repo.insert()
  end

  @doc "Removes the current user's like, if present."
  def unlike_comment(%Scope{user: %User{id: user_id}}, %Comment{id: comment_id}) do
    {count, _} =
      Repo.delete_all(
        from l in CommentLike, where: l.comment_id == ^comment_id and l.user_id == ^user_id
      )

    {:ok, count}
  end

  @doc "Counts the likes on a comment."
  def count_comment_likes(%Scope{user: %User{}}, %Comment{id: comment_id}) do
    Repo.aggregate(from(l in CommentLike, where: l.comment_id == ^comment_id), :count, :id)
  end

  @doc "Checks whether the current user liked a comment."
  def liked_comment?(%Scope{user: %User{id: user_id}}, %Comment{id: comment_id}) do
    Repo.exists?(
      from l in CommentLike, where: l.comment_id == ^comment_id and l.user_id == ^user_id
    )
  end
end
