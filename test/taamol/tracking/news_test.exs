defmodule Taamol.Tracking.NewsTest do
  use Taamol.DataCase, async: true

  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.Tracking
  alias Taamol.Tracking.{Comment, News}

  test "an administrator creates news with their own identity" do
    admin = user_fixture()
    admin = admin |> Ecto.Changeset.change(role: :admin) |> Repo.update!()
    scope = Scope.for_user(admin)

    assert {:ok, news} =
             Tracking.create_news(scope, %{
               title: "News",
               body: "# Heading\n\nA story",
               creator_id: Ecto.UUID.generate()
             })

    assert news.creator_id == admin.id
    assert news.body == "# Heading\n\nA story"
    assert Repo.get!(News, news.id).title == "News"
  end

  test "validates news submitted by an administrator" do
    admin = user_fixture()
    admin = admin |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

    assert {:error, changeset} = Tracking.create_news(Scope.for_user(admin), %{title: ""})
    assert %{title: ["can't be blank"]} = errors_on(changeset)
  end

  test "rejects unauthenticated, non-admin, and demoted users" do
    user = user_fixture()
    assert {:error, :forbidden} = Tracking.create_news(nil, %{title: "News"})
    assert {:error, :forbidden} = Tracking.create_news(Scope.for_user(user), %{title: "News"})

    stale_scope = Scope.for_user(%{user | role: :admin})
    assert {:error, :forbidden} = Tracking.create_news(stale_scope, %{title: "News"})
    assert Repo.aggregate(News, :count, :id) == 0
  end

  test "uses the assigned creator instead of accepting a creator id from attributes" do
    creator_id = Ecto.UUID.generate()
    other_id = Ecto.UUID.generate()

    changeset =
      News.changeset(%News{creator_id: creator_id}, %{
        title: "News",
        creator_id: other_id
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :creator_id) == creator_id
    assert News.__schema__(:association, :creator).related == Taamol.Accounts.User
  end

  test "requires a creator and title" do
    changeset = News.changeset(%News{}, %{})
    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :creator_id)
    assert Keyword.has_key?(changeset.errors, :title)
  end

  test "persists comments with their news and creators" do
    creator = user_fixture()

    news =
      %News{creator_id: creator.id}
      |> News.changeset(%{title: "News", body: "A story"})
      |> Repo.insert!()

    comment =
      %Comment{news_id: news.id, creator_id: creator.id}
      |> Comment.changeset(%{body: "A comment", creator_id: Ecto.UUID.generate()})
      |> Repo.insert!()

    assert comment.creator_id == creator.id
    assert [%Comment{id: id, body: "A comment"}] = Repo.preload(news, :comments).comments
    assert id == comment.id

    Repo.delete!(news)
    refute Repo.get(Comment, comment.id)
  end

  test "requires a body and assigned news and creator for comments" do
    changeset = Comment.changeset(%Comment{}, %{})
    assert %{body: [_], news_id: [_], creator_id: [_]} = errors_on(changeset)
  end
end
