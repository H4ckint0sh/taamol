defmodule Taamol.Tracking.CommentsTest do
  use Taamol.DataCase, async: true

  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.Tracking
  alias Taamol.Tracking.{Comment, CommentLike, Article}

  setup do
    creator = user_fixture()
    scope = Scope.for_user(creator)

    article =
      %Article{creator_id: creator.id}
      |> Article.changeset(%{title: "Article"})
      |> Repo.insert!()

    {:ok, comment} = Tracking.create_comment(scope, article, %{body: "First comment"})
    %{scope: scope, article: article, comment: comment}
  end

  test "creates nested replies using the parent article and current user", %{
    scope: scope,
    article: article,
    comment: comment
  } do
    other_scope = user_scope_fixture()

    assert {:ok, reply} =
             Tracking.reply_to_comment(other_scope, comment, %{
               body: "Reply",
               article_id: Ecto.UUID.generate(),
               creator_id: scope.user.id,
               parent_id: Ecto.UUID.generate()
             })

    assert reply.article_id == article.id
    assert reply.parent_id == comment.id
    assert reply.creator_id == other_scope.user.id
    assert {:ok, nested} = Tracking.reply_to_comment(scope, reply, %{body: "Nested"})
    assert nested.parent_id == reply.id
    assert [%Comment{id: top_id}] = Tracking.list_comments(scope, article)
    assert top_id == comment.id
    assert [%Comment{id: id, creator: creator}] = Tracking.list_replies(scope, comment)
    assert id == reply.id
    assert creator.id == other_scope.user.id

    Repo.delete!(comment)
    refute Repo.get(Comment, reply.id)
    refute Repo.get(Comment, nested.id)
  end

  test "rejects a reply associated with a different article item", %{
    scope: scope,
    comment: comment
  } do
    other_article =
      %Article{creator_id: scope.user.id}
      |> Article.changeset(%{title: "Other"})
      |> Repo.insert!()

    assert {:error, changeset} =
             %Comment{
               parent_id: comment.id,
               article_id: other_article.id,
               creator_id: scope.user.id
             }
             |> Comment.changeset(%{body: "Reply"})
             |> Repo.insert()

    assert %{parent_id: [_]} = errors_on(changeset)
  end

  test "returns an error when replying to a deleted parent", %{scope: scope, comment: comment} do
    Repo.delete!(comment)
    assert {:error, :not_found} = Tracking.reply_to_comment(scope, comment, %{body: "Reply"})
  end

  test "likes are unique per user and can be removed only by their owner", %{
    scope: scope,
    comment: comment
  } do
    other_scope = user_scope_fixture()
    assert {:ok, like} = Tracking.like_comment(scope, comment)
    assert like.user_id == scope.user.id
    assert Tracking.liked_comment?(scope, comment)
    refute Tracking.liked_comment?(other_scope, comment)
    assert {:error, changeset} = Tracking.like_comment(scope, comment)
    assert %{comment_id: [_]} = errors_on(changeset)
    assert {:ok, _} = Tracking.like_comment(other_scope, comment)
    assert Tracking.count_comment_likes(scope, comment) == 2
    assert {:ok, 1} = Tracking.unlike_comment(scope, comment)
    refute Tracking.liked_comment?(scope, comment)
    assert {:ok, 0} = Tracking.unlike_comment(scope, comment)
    assert Tracking.count_comment_likes(scope, comment) == 1

    Repo.delete!(comment)
    assert Repo.aggregate(CommentLike, :count, :id) == 0
  end

  test "cannot like a missing comment", %{scope: scope, comment: comment} do
    Repo.delete!(comment)
    assert {:error, changeset} = Tracking.like_comment(scope, comment)
    assert %{comment_id: [_]} = errors_on(changeset)
  end
end
