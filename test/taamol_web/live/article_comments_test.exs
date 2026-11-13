defmodule TaamolWeb.ArticleCommentsTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures
  import Taamol.TrackingFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.Tracking

  setup do
    author = user_fixture()
    %{article: article_fixture(author), author: author}
  end

  test "guests can read comments but must log in to take part", %{conn: conn, article: article} do
    commenter = user_fixture(%{name: "Zahra"})
    {:ok, _} = Tracking.create_comment(Scope.for_user(commenter), article, %{body: "Salam!"})

    {:ok, view, _html} = live(conn, ~p"/articles/#{article.id}")
    assert has_element?(view, "#threads", "Salam!")
    assert has_element?(view, "#comments-login")
    refute has_element?(view, "#comment-form")

    assert {:error, {:live_redirect, %{to: "/users/log-in"}}} =
             view |> element("#like-article") |> render_click()
  end

  test "users like and unlike an article", %{conn: conn, article: article} do
    {:ok, view, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/articles/#{article.id}")

    view |> element("#like-article") |> render_click()
    assert has_element?(view, "#like-article[aria-pressed=true]", "1")
    assert Tracking.article_like_count(article) == 1

    view |> element("#like-article") |> render_click()
    assert has_element?(view, "#like-article[aria-pressed=false]", "0")
  end

  test "users comment, reply and like comments", %{conn: conn, article: article} do
    user = user_fixture(%{name: "Ali"})
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/articles/#{article.id}")

    view |> form("#comment-form", comment: %{body: "  Great news  "}) |> render_submit()
    [%{id: root_id} = thread] = Tracking.comment_threads(nil, article)
    assert thread.comment.body == "Great news"
    assert has_element?(view, "#comment-#{root_id}", "Great news")

    view |> element("#reply-to-#{root_id}") |> render_click()
    assert has_element?(view, "#reply-form-#{root_id}")

    view
    |> form("#reply-form-#{root_id}", reply: %{body: "Agreed"})
    |> render_submit(%{"parent_id" => root_id, "root" => root_id})

    [%{replies: [reply]}] = Tracking.comment_threads(nil, article)
    assert has_element?(view, "#comment-#{root_id} #comment-#{reply.id}", "Agreed")
    refute has_element?(view, "#reply-form-#{root_id}")

    view |> element("#like-comment-#{reply.id}") |> render_click()
    assert has_element?(view, "#like-comment-#{reply.id}[aria-pressed=true]", "1")
  end

  test "empty comments are rejected", %{conn: conn, article: article} do
    {:ok, view, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/articles/#{article.id}")
    view |> form("#comment-form", comment: %{body: "   "}) |> render_submit()
    assert Tracking.comment_count(article) == 0
  end

  test "authors and admins can delete comments, others can't", %{conn: conn, article: article} do
    writer = user_fixture()
    other = user_fixture()
    {:ok, comment} = Tracking.create_comment(Scope.for_user(writer), article, %{body: "Mine"})

    {:ok, view, _html} = conn |> log_in_user(other) |> live(~p"/articles/#{article.id}")
    refute has_element?(view, "#delete-comment-#{comment.id}")
    assert {:error, :forbidden} = Tracking.delete_comment(Scope.for_user(other), comment)

    admin = user_fixture() |> Ecto.Changeset.change(role: :admin) |> Taamol.Repo.update!()
    assert Tracking.can_delete_comment?(Scope.for_user(admin), comment)

    {:ok, view, _html} = build_conn() |> log_in_user(writer) |> live(~p"/articles/#{article.id}")
    view |> element("#delete-comment-#{comment.id}") |> render_click()
    refute has_element?(view, "#comment-#{comment.id}")
    assert Tracking.comment_count(article) == 0
  end

  test "other readers see new comments and likes live", %{conn: conn, article: article} do
    {:ok, reader, _html} =
      conn |> log_in_user(user_fixture()) |> live(~p"/articles/#{article.id}")

    {:ok, writer, _html} =
      build_conn() |> log_in_user(user_fixture()) |> live(~p"/articles/#{article.id}")

    writer |> form("#comment-form", comment: %{body: "Live hello"}) |> render_submit()
    writer |> element("#like-article") |> render_click()

    assert render(reader) =~ "Live hello"
    assert has_element?(reader, "#like-article", "1")
  end
end
