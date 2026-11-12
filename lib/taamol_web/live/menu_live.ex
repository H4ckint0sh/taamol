defmodule TaamolWeb.MenuLive do
  @moduledoc """
  The "Profile" tab of the mobile bottom bar: account links, theme and
  language (which live in the header on desktop).
  """
  use TaamolWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Profile"),
       locale_form: to_form(%{}),
       current_locale: Gettext.get_locale(TaamolWeb.Gettext),
       languages: [{"en", "English"}, {"fa", "فارسی"}, {"sv", "Svenska"}]
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:menu}>
      <div id="menu" class="space-y-6">
        <%= if @current_scope do %>
          <div id="menu-account" class="flex items-center gap-4">
            <Layouts.avatar user={@current_scope.user} class="size-14 text-lg" />
            <div class="min-w-0">
              <p dir="auto" class="truncate text-lg font-semibold">{@current_scope.user.name}</p>
              <p class="truncate text-sm text-base-content/55">{@current_scope.user.email}</p>
            </div>
          </div>

          <ul class="divide-y divide-base-300/70 rounded-2xl border border-base-300 bg-base-100">
            <.menu_item
              id="menu-dashboard"
              to={~p"/dashboard"}
              icon="hero-chart-bar-square"
            >
              {gettext("Dashboard")}
            </.menu_item>
            <.menu_item
              :if={Taamol.Accounts.can?(@current_scope, :manage_users)}
              id="menu-users"
              to={~p"/dashboard/users"}
              icon="hero-users"
            >
              {gettext("Users")}
            </.menu_item>
            <.menu_item id="menu-settings" to={~p"/users/settings"} icon="hero-cog-6-tooth">
              {gettext("Settings")}
            </.menu_item>
          </ul>
        <% else %>
          <div id="menu-guest" class="rounded-2xl border border-base-300 bg-base-100 p-5">
            <p class="font-semibold">{gettext("Join the community")}</p>
            <p class="mt-1 text-sm text-base-content/60">
              {gettext(
                "Create an account to comment, like articles and take part in community activities."
              )}
            </p>
            <div class="mt-4 grid grid-cols-2 gap-3">
              <.link
                id="menu-log-in"
                navigate={~p"/users/log-in"}
                class="rounded-xl border border-base-300 py-2.5 text-center text-sm font-semibold transition hover:bg-base-200"
              >
                {gettext("Log in")}
              </.link>
              <.link
                id="menu-register"
                navigate={~p"/users/register"}
                class="rounded-xl bg-primary py-2.5 text-center text-sm font-semibold text-primary-content transition hover:opacity-85"
              >
                {gettext("Register")}
              </.link>
            </div>
          </div>
        <% end %>

        <section>
          <h2 class="mb-2 px-1 text-[11px] font-semibold uppercase tracking-wider text-base-content/50">
            {gettext("Preferences")}
          </h2>
          <div class="divide-y divide-base-300/70 rounded-2xl border border-base-300 bg-base-100">
            <div class="flex items-center justify-between gap-4 px-4 py-3">
              <span class="flex items-center gap-3 text-sm">
                <.icon name="hero-swatch" class="size-5 text-base-content/50" />
                {gettext("Theme")}
              </span>
              <Layouts.theme_toggle />
            </div>
            <.form
              for={@locale_form}
              id="menu-locale"
              action={~p"/locale"}
              method="post"
              class="px-4 py-3"
            >
              <p class="flex items-center gap-3 text-sm">
                <.icon name="hero-language" class="size-5 text-base-content/50" />
                {gettext("Language")}
              </p>
              <div class="mt-3 grid grid-cols-3 gap-2">
                <button
                  :for={{code, label} <- @languages}
                  type="submit"
                  name="locale"
                  value={code}
                  lang={code}
                  id={"menu-locale-#{code}"}
                  aria-current={if(@current_locale == code, do: "true")}
                  class="rounded-xl border border-base-300 py-2 text-sm transition hover:bg-base-200 aria-[current=true]:border-primary aria-[current=true]:bg-primary/10 aria-[current=true]:font-semibold aria-[current=true]:text-primary"
                >
                  {label}
                </button>
              </div>
            </.form>
          </div>
        </section>

        <.link
          :if={@current_scope}
          id="menu-log-out"
          href={~p"/users/log-out"}
          method="delete"
          class="flex items-center justify-center gap-2 rounded-2xl border border-base-300 bg-base-100 py-3 text-sm font-semibold text-error transition hover:bg-error/10"
        >
          <.icon name="hero-arrow-right-start-on-rectangle" class="size-5 rtl:rotate-180" />
          {gettext("Log out")}
        </.link>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :to, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp menu_item(assigns) do
    ~H"""
    <li>
      <.link
        id={@id}
        navigate={@to}
        class="flex items-center gap-3 px-4 py-3.5 text-sm transition first:rounded-t-2xl last:rounded-b-2xl hover:bg-base-200"
      >
        <.icon name={@icon} class="size-5 text-base-content/50" />
        <span class="flex-1">{render_slot(@inner_block)}</span>
        <.icon name="hero-chevron-right" class="size-4 text-base-content/30 rtl:rotate-180" />
      </.link>
    </li>
    """
  end
end
