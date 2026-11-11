defmodule Taamol.Tracking.NewsLikesTest do
  use Taamol.DataCase, async: true

  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.Tracking
  alias Taamol.Tracking.{News, NewsLike}

  setup do
    creator = user_fixture()
    scope = Scope.for_user(creator)

    news =
      %News{creator_id: creator.id}
      |> News.changeset(%{title: "News", likes: 99})
      |> Repo.insert!()

    %{scope: scope, news: news}
  end

  test "tracks one like per user and removes only the current user's like", %{
    scope: scope,
    news: news
  } do
    other_scope = user_scope_fixture()
    assert Tracking.count_news_likes(scope, news) == 0
    assert {:ok, like} = Tracking.like_news(scope, news)
    assert like.user_id == scope.user.id
    assert Tracking.liked_news?(scope, news)
    refute Tracking.liked_news?(other_scope, news)
    assert {:error, changeset} = Tracking.like_news(scope, news)
    assert %{news_id: [_]} = errors_on(changeset)
    assert {:ok, _} = Tracking.like_news(other_scope, news)
    assert Tracking.count_news_likes(scope, news) == 2
    assert {:ok, 1} = Tracking.unlike_news(scope, news)
    assert {:ok, 0} = Tracking.unlike_news(scope, news)
    refute Tracking.liked_news?(scope, news)
    assert Tracking.liked_news?(other_scope, news)
    assert Tracking.count_news_likes(scope, news) == 1

    Repo.delete!(news)
    assert Repo.aggregate(NewsLike, :count, :id) == 0
  end

  test "cannot like a missing news item", %{scope: scope, news: news} do
    Repo.delete!(news)
    assert {:error, changeset} = Tracking.like_news(scope, news)
    assert %{news_id: [_]} = errors_on(changeset)
  end
end
