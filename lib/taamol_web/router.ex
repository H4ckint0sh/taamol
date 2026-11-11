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

    get "/", PageController, :home
    post "/locale", LocaleController, :update
  end

  # Other scopes may use custom stacks.
  # scope "/api", TaamolWeb do
  #   pipe_through :api
  # end

  # Enable the mailbox preview in development.
  if Application.compile_env(:taamol, :dev_routes) do
    scope "/dev" do
      pipe_through [:browser, :local_mailbox]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", TaamolWeb do
    pipe_through [:browser, :require_authenticated_user, :require_dashboard_access]

    live_session :dashboard,
      on_mount: [{TaamolWeb.Locale, :default}, {TaamolWeb.UserAuth, :require_dashboard_access}] do
      live "/dashboard", DashboardLive.DashboardStartLive, :index
      live "/dashboard/create/article", DashboardLive.DashboardCreateArticleLive, :index
    end
  end

  scope "/admin", TaamolWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    live_session :admin,
      on_mount: [{TaamolWeb.Locale, :default}, {TaamolWeb.UserAuth, :require_admin}] do
      live "/access", AdminAccessLive, :index
    end
  end

  scope "/", TaamolWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TaamolWeb.Locale, :default}, {TaamolWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
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
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
