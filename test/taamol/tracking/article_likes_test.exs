defmodule Taamol.Tracking.ArticleLikesTest do
  use Taamol.DataCase, async: true

  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.Tracking
  alias Taamol.Tracking.{Article, ArticleLike}

  setup do
    creator = user_fixture()
    scope = Scope.for_user(creator)

    article =
      %Article{creator_id: creator.id}
      |> Article.changeset(%{title: "Article", likes: 99})
      |> Repo.insert!()

    %{scope: scope, article: article}
  end

  test "tracks one like per user and removes only the current user's like", %{
    scope: scope,
    article: article
  } do
    other_scope = user_scope_fixture()
    assert Tracking.count_article_likes(scope, article) == 0
    assert {:ok, like} = Tracking.like_article(scope, article)
    assert like.user_id == scope.user.id
    assert Tracking.liked_article?(scope, article)
    refute Tracking.liked_article?(other_scope, article)
    assert {:error, changeset} = Tracking.like_article(scope, article)
    assert %{article_id: [_]} = errors_on(changeset)
    assert {:ok, _} = Tracking.like_article(other_scope, article)
    assert Tracking.count_article_likes(scope, article) == 2
    assert {:ok, 1} = Tracking.unlike_article(scope, article)
    assert {:ok, 0} = Tracking.unlike_article(scope, article)
    refute Tracking.liked_article?(scope, article)
    assert Tracking.liked_article?(other_scope, article)
    assert Tracking.count_article_likes(scope, article) == 1

    Repo.delete!(article)
    assert Repo.aggregate(ArticleLike, :count, :id) == 0
  end

  test "cannot like a missing article item", %{scope: scope, article: article} do
    Repo.delete!(article)
    assert {:error, changeset} = Tracking.like_article(scope, article)
    assert %{article_id: [_]} = errors_on(changeset)
  end
end
