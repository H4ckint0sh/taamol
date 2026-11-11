defmodule Taamol.Tracking.ArticleTest do
  use Taamol.DataCase, async: true

  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.Tracking
  alias Taamol.Tracking.{Comment, Article}

  test "an administrator creates article with their own identity" do
    admin = user_fixture()
    admin = admin |> Ecto.Changeset.change(role: :admin) |> Repo.update!()
    scope = Scope.for_user(admin)

    assert {:ok, article} =
             Tracking.create_article(scope, %{
               title: "Article",
               body: "# Heading\n\nA story",
               creator_id: Ecto.UUID.generate()
             })

    assert article.creator_id == admin.id
    assert article.body == "# Heading\n\nA story"
    assert Repo.get!(Article, article.id).title == "Article"
  end

  test "validates article submitted by an administrator" do
    admin = user_fixture()
    admin = admin |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

    assert {:error, changeset} = Tracking.create_article(Scope.for_user(admin), %{title: ""})
    assert %{title: ["can't be blank"]} = errors_on(changeset)
  end

  test "rejects unauthenticated, non-admin, and demoted users" do
    user = user_fixture()
    assert {:error, :forbidden} = Tracking.create_article(nil, %{title: "Article"})

    assert {:error, :forbidden} =
             Tracking.create_article(Scope.for_user(user), %{title: "Article"})

    stale_scope = Scope.for_user(%{user | role: :admin})
    assert {:error, :forbidden} = Tracking.create_article(stale_scope, %{title: "Article"})
    assert Repo.aggregate(Article, :count, :id) == 0
  end

  test "uses the assigned creator instead of accepting a creator id from attributes" do
    creator_id = Ecto.UUID.generate()
    other_id = Ecto.UUID.generate()

    changeset =
      Article.changeset(%Article{creator_id: creator_id}, %{
        title: "Article",
        creator_id: other_id
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :creator_id) == creator_id
    assert Article.__schema__(:association, :creator).related == Taamol.Accounts.User
  end

  test "requires a creator and title" do
    changeset = Article.changeset(%Article{}, %{})
    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :creator_id)
    assert Keyword.has_key?(changeset.errors, :title)
  end

  test "persists comments with their article and creators" do
    creator = user_fixture()

    article =
      %Article{creator_id: creator.id}
      |> Article.changeset(%{title: "Article", body: "A story"})
      |> Repo.insert!()

    comment =
      %Comment{article_id: article.id, creator_id: creator.id}
      |> Comment.changeset(%{body: "A comment", creator_id: Ecto.UUID.generate()})
      |> Repo.insert!()

    assert comment.creator_id == creator.id
    assert [%Comment{id: id, body: "A comment"}] = Repo.preload(article, :comments).comments
    assert id == comment.id

    Repo.delete!(article)
    refute Repo.get(Comment, comment.id)
  end

  test "requires a body and assigned article and creator for comments" do
    changeset = Comment.changeset(%Comment{}, %{})
    assert %{body: [_], article_id: [_], creator_id: [_]} = errors_on(changeset)
  end
end
