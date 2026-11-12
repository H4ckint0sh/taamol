defmodule TaamolWeb.NewsLiveTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures
  import Taamol.TrackingFixtures

  setup do
    %{creator: user_fixture()}
  end

  describe "home" do
    test "shows an empty state without articles", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#home-empty")
      assert has_element?(view, "#bottom-nav")
      assert has_element?(view, "#site-footer a[href='/categories/world']")
      refute has_element?(view, "#sidebar-categories")
    end

    test "shows the lead story, latest list and feed", %{conn: conn, creator: creator} do
      lead = article_fixture(creator, featured: true, title: "Lead story")
      other = article_fixture(creator, category: :world)

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#lead-article", "Lead story")
      assert has_element?(view, "#latest-#{other.id}")
      assert has_element?(view, "#feed-#{lead.id}")
      assert has_element?(view, "#feed-#{other.id}")
      assert has_element?(view, "#rail-prayer-times")
    end

    test "filters the feed by category", %{conn: conn, creator: creator} do
      article_fixture(creator, featured: true)
      world = article_fixture(creator, category: :world)
      sport = article_fixture(creator, category: :sport)

      {:ok, view, _html} = live(conn, ~p"/?category=world")
      assert has_element?(view, "#feed-#{world.id}")
      refute has_element?(view, "#feed-#{sport.id}")
    end

    test "loads more articles", %{conn: conn, creator: creator} do
      for i <- 1..9 do
        article_fixture(creator, published: DateTime.add(DateTime.utc_now(:second), -60 * i))
      end

      oldest =
        article_fixture(creator, published: DateTime.add(DateTime.utc_now(:second), -3600))

      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#feed-#{oldest.id}")

      view |> element("#load-more") |> render_click()
      assert has_element?(view, "#feed-#{oldest.id}")
      refute has_element?(view, "#load-more")
    end
  end

  describe "categories" do
    test "lists categories with counts", %{conn: conn, creator: creator} do
      article_fixture(creator, category: :culture)

      {:ok, view, _html} = live(conn, ~p"/categories")
      assert has_element?(view, "#category-culture")
      assert has_element?(view, "#category-sport")
    end

    test "shows a category's articles", %{conn: conn, creator: creator} do
      lead = article_fixture(creator, category: :sport, featured: true)
      other = article_fixture(creator, category: :sport)
      world = article_fixture(creator, category: :world)

      {:ok, view, _html} = live(conn, ~p"/categories/sport")
      assert has_element?(view, "#category-lead")
      assert has_element?(view, "#feed-#{other.id}")
      refute has_element?(view, "#feed-#{world.id}")
      # the lead story is not repeated in the feed
      refute has_element?(view, "#feed-#{lead.id}")
    end

    test "unknown categories are not found", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/categories/nope") end
    end
  end

  describe "article page" do
    test "shows the article and counts a view", %{conn: conn, creator: creator} do
      article = article_fixture(creator, title: "Hello world", view_count: 4)

      {:ok, view, _html} = live(conn, ~p"/articles/#{article.id}")
      assert has_element?(view, "#article-#{article.id} h1", "Hello world")
      assert has_element?(view, "#article-body p", "Second paragraph.")
      assert has_element?(view, "#article-views", "5")
      assert has_element?(view, "#share-article")
    end

    test "drafts are not found", %{conn: conn, creator: creator} do
      draft = article_fixture(creator, published: nil)
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/articles/#{draft.id}") end
    end
  end

  describe "menu" do
    test "guests see log in and register", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/menu")
      assert has_element?(view, "#menu-log-in")
      assert has_element?(view, "#menu-locale-sv")
      refute has_element?(view, "#menu-log-out")
    end

    test "users see their account links", %{conn: conn, creator: user} do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/menu")
      assert has_element?(view, "#menu-account", user.name)
      assert has_element?(view, "#menu-settings")
      assert has_element?(view, "#menu-log-out")
    end
  end
end
