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
      # categories are only on the News page, not in the site navigation
      refute has_element?(view, "header a[href^='/categories'], header a[href^='/news?category']")
      refute has_element?(view, "#site-footer a[href*='category']")
      refute has_element?(view, "#mobile-drawer a[href*='category']")
      assert has_element?(view, "#main-nav a[href='/news']")
      assert has_element?(view, "#bottom-nav a[href='/news']")
      assert has_element?(view, "#mobile-menu-open")
      assert has_element?(view, "#mobile-drawer a[href='/calendar']")
      assert has_element?(view, "#mobile-drawer a[href='/news']")
      assert has_element?(view, "#drawer-locale-button")
    end

    test "shows the lead story, latest list and feed", %{conn: conn, creator: creator} do
      lead = article_fixture(creator, featured: true, title: "Lead story")
      other = article_fixture(creator, category: :world)

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#lead-article", "Lead story")
      assert has_element?(view, "#home-news-tabs.rounded-full #tab-latest[aria-selected=true]")
      assert has_element?(view, "#home-news-tabs-indicator[phx-hook=SegmentedIndicator]")
      assert has_element?(view, "#home-news-tabs #tab-most-read[aria-selected=false]")
      assert has_element?(view, "#latest-#{other.id}")
      assert has_element?(view, "#feed-#{lead.id}")
      assert has_element?(view, "#feed-#{other.id}")
      assert has_element?(view, "#rail-prayer-times")

      assert has_element?(
               view,
               "#rail-prayer-times[data-latitude='56.879'][data-longitude='14.8059'][data-timezone='Europe/Stockholm'][data-city='Växjö']"
             )

      assert has_element?(view, "#rail-prayer-card .hero-moon")
      assert has_element?(view, "#rail-prayer-card h2", "Prayer times")

      assert has_element?(
               view,
               "#rail-prayer-card p",
               "Today's prayer times and the next prayer."
             )

      for id <- ["home-upcoming", "rail-upcoming"] do
        assert has_element?(view, "##{id} .hero-calendar-days")
        assert has_element?(view, "##{id} h2", "Upcoming")
        assert has_element?(view, "##{id} p", "Community events and important dates ahead.")
        assert has_element?(view, "##{id} a[href='/calendar']")
      end
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

  describe "news page" do
    test "public pages use compact headings without decorative boxes", %{conn: conn} do
      for {path, id} <- [
            {~p"/news", "news-hero"},
            {~p"/gallery", "gallery-hero"},
            {~p"/calendar", "calendar-hero"},
            {~p"/contact", "contact-hero"},
            {~p"/donate", "donate-hero"},
            {~p"/menu", "menu-hero"},
            {~p"/prayer-times", "prayer-times-hero"},
            {~p"/articles", "articles-hero"}
          ] do
        {:ok, view, _} = live(conn, path)
        assert has_element?(view, "##{id} h1")
        refute has_element?(view, "##{id}.border")
        refute has_element?(view, "##{id}.bg-gradient-to-br")
      end
    end

    test "lists all news with the category filter", %{conn: conn, creator: creator} do
      lead = article_fixture(creator, featured: true)
      other = article_fixture(creator, category: :world)

      {:ok, view, _html} = live(conn, ~p"/news")
      assert has_element?(view, "#news-categories a[href='/news?category=religion']")
      assert has_element?(view, "#news-lead")
      assert has_element?(view, "#feed-#{other.id}")
      # the lead story is not repeated in the feed
      refute has_element?(view, "#feed-#{lead.id}")
    end

    test "filters by category with the chips", %{conn: conn, creator: creator} do
      sport_lead = article_fixture(creator, category: :sport, featured: true)
      sport = article_fixture(creator, category: :sport)
      world = article_fixture(creator, category: :world)

      {:ok, view, _html} = live(conn, ~p"/news")
      view |> element("#news-categories a[href='/news?category=sport']") |> render_click()
      assert_patch(view, ~p"/news?category=sport")

      assert has_element?(view, "#news-categories a[aria-current=page]", "Sport")
      assert has_element?(view, "#news-hero h1", "Sport")
      assert has_element?(view, "#news-lead a[href='/articles/#{sport_lead.id}']")
      assert has_element?(view, "#feed-#{sport.id}")
      refute has_element?(view, "#feed-#{world.id}")
    end

    test "unknown categories show all news", %{conn: conn, creator: creator} do
      article = article_fixture(creator)
      {:ok, view, _html} = live(conn, ~p"/news?category=nope")
      assert has_element?(view, "#news-lead a[href='/articles/#{article.id}']")
    end

    test "old category links redirect to the News page", %{conn: conn} do
      assert redirected_to(get(conn, "/categories/sport"), 301) == "/news?category=sport"
      assert redirected_to(get(build_conn(), "/categories"), 301) == "/news"
    end
  end

  describe "article page" do
    test "shows the article and counts a view", %{conn: conn, creator: creator} do
      article = article_fixture(creator, title: "Hello world", view_count: 4)

      {:ok, view, _html} = live(conn, ~p"/articles/#{article.id}")
      assert has_element?(view, "#article-hero h1", "Hello world")
      assert has_element?(view, "#article-hero", "Community")
      refute has_element?(view, "#article-hero.border")
      assert has_element?(view, "#article-body p", "Second paragraph.")
      assert has_element?(view, "#article-views", "5")
      assert has_element?(view, "#share-article")

      assert has_element?(
               view,
               "#share-article[phx-hook='ShareArticle'][data-title='Hello world']"
             )
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
      assert has_element?(view, "#menu-locale-button")
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
