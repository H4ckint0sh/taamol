defmodule Taamol.Tracking do
  @moduledoc """
  Operations for news, comments, replies, and likes.
  """

  import Ecto.Query

  alias Taamol.Accounts.{Scope, User}
  alias Taamol.Repo
  alias Taamol.Tracking.{Comment, CommentLike, News, NewsLike}

  @doc """
  Creates a news item for the current administrator.

  Returns `{:error, :forbidden}` if the user is not an administrator.
  """
  def create_news(%Scope{user: %User{id: user_id}}, attrs) do
    Repo.transact(fn ->
      admin =
        Repo.one(
          from u in User,
            where: u.id == ^user_id and u.role == :admin,
            lock: "FOR SHARE"
        )

      if admin do
        %News{creator_id: admin.id}
        |> News.changeset(attrs)
        |> Repo.insert()
      else
        {:error, :forbidden}
      end
    end)
  end

  def create_news(_scope, _attrs), do: {:error, :forbidden}

  @doc "Likes a news item once per user."
  def like_news(%Scope{user: %User{id: user_id}}, %News{id: news_id}) do
    %NewsLike{news_id: news_id, user_id: user_id}
    |> NewsLike.changeset()
    |> Repo.insert()
  end

  @doc "Removes the current user's news like, if present."
  def unlike_news(%Scope{user: %User{id: user_id}}, %News{id: news_id}) do
    {count, _} =
      Repo.delete_all(from l in NewsLike, where: l.news_id == ^news_id and l.user_id == ^user_id)

    {:ok, count}
  end

  @doc "Counts the user-attributed likes on a news item."
  def count_news_likes(%Scope{user: %User{}}, %News{id: news_id}) do
    Repo.aggregate(from(l in NewsLike, where: l.news_id == ^news_id), :count, :id)
  end

  @doc "Checks whether the current user liked a news item."
  def liked_news?(%Scope{user: %User{id: user_id}}, %News{id: news_id}) do
    Repo.exists?(from l in NewsLike, where: l.news_id == ^news_id and l.user_id == ^user_id)
  end

  @doc "Creates a comment on a news item for the current user."
  def create_comment(%Scope{user: %User{id: user_id}}, %News{id: news_id}, attrs) do
    %Comment{news_id: news_id, creator_id: user_id}
    |> Comment.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists the top-level comments on a news item with their creators."
  def list_comments(%Scope{user: %User{}}, %News{id: news_id}) do
    Repo.all(
      from c in Comment,
        where: c.news_id == ^news_id and is_nil(c.parent_id),
        order_by: [asc: c.inserted_at, asc: c.id],
        preload: [:creator]
    )
  end

  @doc "Creates a reply on the same news item as its parent."
  def reply_to_comment(%Scope{user: %User{id: user_id}}, %Comment{id: parent_id}, attrs) do
    case Repo.get(Comment, parent_id) do
      nil ->
        {:error, :not_found}

      parent ->
        %Comment{news_id: parent.news_id, parent_id: parent.id, creator_id: user_id}
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
