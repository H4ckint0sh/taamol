defmodule TaamolWeb.Router do
  use TaamolWeb, :router

  import TaamolWeb.UserAuth
  import TaamolWeb.Locale, only: [set_locale: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :set_locale
    plug :fetch_live_flash
    plug :put_root_layout, html: {TaamolWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :local_mailbox do
    plug :require_local_mailbox
  end

  defp require_local_mailbox(%{remote_ip: ip, host: host} = conn, _opts) do
    local_ip? = match?({127, _, _, _}, ip) or ip == {0, 0, 0, 0, 0, 0, 0, 1}

    if local_ip? and host in ["localhost", "127.0.0.1", "::1"] do
      conn
    else
      conn |> send_resp(:forbidden, "Local access only") |> halt()
    end
  end

  scope "/", TaamolWeb do
    pipe_through :browser

    post "/locale", LocaleController, :update

    # category pages moved to /news?category=… (kept for old links)
    get "/categories", RedirectController, :categories
    get "/categories/:category", RedirectController, :categories
  end

  # The Swish QR image for donations. No :browser pipeline: it is an image,
  # needs no session, and browsers ask for it with an image Accept header.
  scope "/", TaamolWeb do
    get "/donate/qr.png", DonationQrController, :show
  end

  # Public JSON API. Prayer times only depend on a location and date, so no
  # session, CSRF token or login is needed.
  scope "/api", TaamolWeb do
    pipe_through :api

    get "/prayer-times", PrayerTimeController, :index
  end

  # Enable the mailbox preview in development.
  if Application.compile_env(:taamol, :dev_routes) do
    scope "/dev" do
      pipe_through [:browser, :local_mailbox]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", TaamolWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TaamolWeb.Locale, :default}, {TaamolWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      # Dashboard: every logged-in user gets their overview and account
      # settings. The other pages are for administrators: each of those
      # LiveViews also runs `on_mount {UserAuth, :require_admin}` itself.
      live "/dashboard", DashboardLive.Overview, :index
      live "/dashboard/news", DashboardLive.Articles, :index
      live "/dashboard/news/new", DashboardLive.ArticleForm, :new
      live "/dashboard/news/:id/edit", DashboardLive.ArticleForm, :edit
      live "/dashboard/users", DashboardLive.Users, :index
      live "/dashboard/users/new", DashboardLive.UserForm, :new
      live "/dashboard/users/:id/edit", DashboardLive.UserForm, :edit
      live "/dashboard/events", DashboardLive.Events, :index
      live "/dashboard/events/new", DashboardLive.EventForm, :new
      live "/dashboard/events/:id/edit", DashboardLive.EventForm, :edit
      live "/dashboard/gallery", DashboardLive.Gallery, :index
      live "/dashboard/messages", DashboardLive.Messages, :index
      # members see their own bookings here; administrators see all of them
      live "/dashboard/bookings", DashboardLive.Bookings, :index
      live "/dashboard/booking-services", DashboardLive.BookingServices, :index
      live "/dashboard/settings", DashboardLive.SiteSettings, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
    post "/users/update-name", UserSessionController, :update_name
  end

  scope "/", TaamolWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{TaamolWeb.Locale, :default}, {TaamolWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/articles", ArticleLive.ArticleListLive, :new
      # public news pages: work for visitors and logged-in users alike
      live "/", HomeLive, :index
      live "/news", NewsLive, :index
      live "/articles/:id", ArticleLive.Show, :show
      live "/menu", MenuLive, :index
      live "/calendar", CalendarLive, :index
      live "/gallery", GalleryLive, :index
      live "/contact", ContactLive, :index
      live "/donate", DonateLive, :index
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
