defmodule TaamolWeb.ArticleLive.ArticleListLiveTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures

  alias Taamol.Repo
  alias Taamol.Tracking.Article

  test "public articles show the creator and exclude drafts and future articles", %{conn: conn} do
    creator = user_fixture()

    published =
      %Article{creator_id: creator.id}
      |> Article.changeset(%{
        title: "Published",
        body: "A story",
        published: DateTime.add(DateTime.utc_now(:second), -60)
      })
      |> Repo.insert!()

    draft =
      %Article{creator_id: creator.id}
      |> Article.changeset(%{title: "Draft"})
      |> Repo.insert!()

    future =
      %Article{creator_id: creator.id}
      |> Article.changeset(%{
        title: "Future",
        published: DateTime.add(DateTime.utc_now(:second), 86_400)
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/articles")
    assert has_element?(view, "#articles-#{published.id}", "Published")
    assert has_element?(view, "#articles-#{published.id}", creator.name)
    refute has_element?(view, "#articles-#{draft.id}")
    refute has_element?(view, "#articles-#{future.id}")
  end
end
