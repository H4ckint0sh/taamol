defmodule TaamolWeb.DashboardLiveTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures
  import Taamol.TrackingFixtures

  alias Taamol.{Accounts, Events, Repo}
  alias Taamol.Accounts.Scope

  @cover Path.expand("../../support/fixtures/cover.png", __DIR__)

  defp admin_fixture(opts \\ []) do
    user_fixture()
    |> Ecto.Changeset.change(
      role: :admin,
      can_view_dashboard: Keyword.get(opts, :statistics, true)
    )
    |> Repo.update!()
  end

  describe "permissions" do
    test "guests must log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
    end

    test "regular users only see their own overview and settings", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#my-activity")
      assert has_element?(view, "#dashboard-nav-account")
      refute has_element?(view, "#statistics")
      refute has_element?(view, "#dashboard-nav-news")
      refute has_element?(view, "#dashboard-nav-users")
      refute has_element?(view, "#dashboard-nav-site_settings")

      for path <- [
            ~p"/dashboard/news",
            ~p"/dashboard/news/new",
            ~p"/dashboard/users",
            ~p"/dashboard/events",
            ~p"/dashboard/settings"
          ] do
        assert {:error, {:redirect, %{to: "/"}}} = live(conn, path)
      end

      {:ok, settings, _html} = live(conn, ~p"/users/settings")
      assert has_element?(settings, "#dashboard-nav-account[aria-current=page]")
    end

    test "admins see statistics and every section", %{conn: conn} do
      admin = admin_fixture()
      article_fixture(admin, category: :world, view_count: 40)

      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/dashboard")
      assert has_element?(view, "#statistics")
      assert has_element?(view, "#stat-views [data-value]", "40")
      assert has_element?(view, "#views-chart", "World")
      assert has_element?(view, "#signups-chart")

      for item <- ~w(news events users site_settings account) do
        assert has_element?(view, "#dashboard-nav-#{item}")
      end
    end

    test "admins without statistics access can still manage content", %{conn: conn} do
      {:ok, view, _html} =
        conn |> log_in_user(admin_fixture(statistics: false)) |> live(~p"/dashboard")

      refute has_element?(view, "#statistics")
      assert has_element?(view, "#dashboard-nav-news")
    end
  end

  describe "users" do
    setup %{conn: conn} do
      admin = admin_fixture()
      %{admin: admin, conn: log_in_user(conn, admin)}
    end

    test "lists, searches and filters users", %{conn: conn} do
      alice = user_fixture(%{name: "Alice Example"})
      bob = user_fixture(%{name: "Bob Other"})

      {:ok, view, _html} = live(conn, ~p"/dashboard/users?search=alice")
      assert has_element?(view, "#users-#{alice.id}")
      refute has_element?(view, "#users-#{bob.id}")

      {:ok, view, _html} = live(conn, ~p"/dashboard/users?role=admin")
      refute has_element?(view, "#users-#{alice.id}")
    end

    test "changes roles and statistics access", %{conn: conn} do
      target = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/dashboard/users")

      view |> element("#promote-#{target.id}") |> render_click()
      assert %{role: :admin, can_view_dashboard: true} = Accounts.get_user!(target.id)

      view |> element("#dashboard-#{target.id}") |> render_click()
      assert %{can_view_dashboard: false} = Accounts.get_user!(target.id)

      view |> element("#demote-#{target.id}") |> render_click()
      assert %{role: :user} = Accounts.get_user!(target.id)
    end

    test "creates a user and emails a sign-in link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/users/new")

      {:ok, _view, html} =
        view
        |> form("#user-form", user: %{name: "New Person", email: "new.person@example.com"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "new.person@example.com"
      assert Accounts.get_user_by_email("new.person@example.com")
      # fixtures send their own emails first, so match this one specifically
      assert_received {:email, %{to: [{"", "new.person@example.com"}]}}
    end

    test "edits a user", %{conn: conn} do
      target = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/dashboard/users/#{target.id}/edit")

      view
      |> form("#user-form", user: %{name: "Renamed", email: target.email})
      |> render_submit()

      assert Accounts.get_user!(target.id).name == "Renamed"
    end

    test "deletes users, but not yourself or authors", %{conn: conn, admin: admin} do
      target = user_fixture()
      author = user_fixture()
      article_fixture(author)

      {:ok, view, _html} = live(conn, ~p"/dashboard/users")
      refute has_element?(view, "#delete-#{admin.id}")

      view |> element("#delete-#{target.id}") |> render_click()
      refute Repo.get(Taamol.Accounts.User, target.id)

      view |> element("#delete-#{author.id}") |> render_click()
      assert Repo.get(Taamol.Accounts.User, author.id)

      assert {:error, :cannot_delete_self} =
               Accounts.delete_user_as_admin(Scope.for_user(admin), admin.id)
    end
  end

  describe "news" do
    setup %{conn: conn} do
      admin = admin_fixture()
      %{admin: admin, conn: log_in_user(conn, admin)}
    end

    test "lists articles with status filters", %{conn: conn, admin: admin} do
      published = article_fixture(admin, title: "Live one")
      draft = article_fixture(admin, title: "Draft one", published: nil)

      {:ok, view, _html} = live(conn, ~p"/dashboard/news")
      assert has_element?(view, "#articles-#{published.id}")
      assert has_element?(view, "#articles-#{draft.id}")

      {:ok, view, _html} = live(conn, ~p"/dashboard/news?status=draft")
      refute has_element?(view, "#articles-#{published.id}")
      assert has_element?(view, "#articles-#{draft.id}")
    end

    test "writes an article with a live Markdown preview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/news/new")

      view
      |> form("#article-form",
        article: %{title: "Hello", body: "## Intro\n\n**Bold** <script>x()</script>"}
      )
      |> render_change()

      assert has_element?(view, "#markdown-preview h2", "Intro")
      assert has_element?(view, "#markdown-preview strong", "Bold")
      refute has_element?(view, "#markdown-preview script")

      {:ok, _edit, _html} =
        view
        |> form("#article-form",
          article: %{title: "Hello", body: "## Intro", category: "religion"},
          status: "published"
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert [article] = Repo.all(Taamol.Tracking.Article)

      assert article.title == "Hello"
      assert article.category == :religion
      assert article.published
    end

    test "uploads a cover image and inserts inline images", %{conn: conn, admin: admin} do
      article = article_fixture(admin, published: nil)
      {:ok, view, _html} = live(conn, ~p"/dashboard/news/#{article.id}/edit")

      inline =
        file_input(view, "#article-form", :inline_image, [
          %{name: "photo.png", content: File.read!(@cover), type: "image/png"}
        ])

      render_upload(inline, "photo.png")
      assert_push_event(view, "markdown:insert", %{text: "![photo](/uploads/" <> _})

      cover =
        file_input(view, "#article-form", :cover, [
          %{name: "cover.png", content: File.read!(@cover), type: "image/png"}
        ])

      render_upload(cover, "cover.png")
      view |> form("#article-form") |> render_submit()

      assert "/uploads/" <> _ = Repo.reload!(article).cover_image_url
    end

    test "deletes an article", %{conn: conn, admin: admin} do
      article = article_fixture(admin)
      {:ok, view, _html} = live(conn, ~p"/dashboard/news")
      view |> element("#delete-#{article.id}") |> render_click()
      refute Repo.get(Taamol.Tracking.Article, article.id)
    end
  end

  describe "events and settings" do
    setup %{conn: conn} do
      admin = admin_fixture()
      %{admin: admin, conn: log_in_user(conn, admin)}
    end

    test "lists and deletes upcoming events", %{conn: conn, admin: admin} do
      starts =
        NaiveDateTime.utc_now() |> NaiveDateTime.add(86_400) |> NaiveDateTime.truncate(:second)

      {:ok, event} =
        Events.create_event(Scope.for_user(admin), %{"title" => "Majlis", "starts_at" => starts})

      {:ok, view, _html} = live(conn, ~p"/dashboard/events")
      assert has_element?(view, "#events-#{event.id}", "Majlis")

      view |> element("#delete-#{event.id}") |> render_click()
      refute has_element?(view, "#events-#{event.id}")
    end
  end
end
