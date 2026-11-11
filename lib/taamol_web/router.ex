defmodule TaamolWeb.Router do
  use TaamolWeb, :router

  import TaamolWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TaamolWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TaamolWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", TaamolWeb do
  #   pipe_through :api
  # end

  # Enable the mailbox preview in development.
  if Application.compile_env(:taamol, :dev_routes) do
    scope "/dev" do
      pipe_through [:browser, :require_authenticated_user, :require_admin]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", TaamolWeb do
    pipe_through [:browser, :require_authenticated_user, :require_dashboard_access]

    live_session :dashboard,
      on_mount: [{TaamolWeb.UserAuth, :require_dashboard_access}] do
      live "/dashboard", DashboardLive, :index
    end
  end

  scope "/admin", TaamolWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    live_session :admin, on_mount: [{TaamolWeb.UserAuth, :require_admin}] do
      live "/access", AdminAccessLive, :index
    end
  end

  scope "/", TaamolWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TaamolWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
    post "/users/update-name", UserSessionController, :update_name
  end

  scope "/", TaamolWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{TaamolWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
