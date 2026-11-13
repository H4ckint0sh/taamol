defmodule TaamolWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TaamolWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the app layout: the site header (category navigation, prayer times,
  language, theme and account menu), the mobile category tabs and bottom tab
  bar, and the page content.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <h1>Content</h1>
      </Layouts.app>

  Pass `wide` for full-width pages that manage their own container, and
  `active` (`:home`, `:news`, `:calendar`, `:gallery`, `:contact`, `:donate` or `:menu`) to highlight the
  current navigation item. Category tabs show on mobile for `:home` and
  category pages.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :wide, :boolean, default: false
  attr :active, :atom, default: nil, doc: "the current navigation item"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :donations?, Taamol.Settings.swish() != nil)

    ~H"""
    <header class="sticky top-0 z-40 border-b border-base-300/70 bg-base-100/90 backdrop-blur-md">
      <div class="mx-auto flex h-16 max-w-7xl items-center gap-3 px-4 sm:gap-6 sm:px-6 lg:h-20 lg:px-8">
        <button
          type="button"
          id="mobile-menu-open"
          aria-label={gettext("Open menu")}
          aria-controls="mobile-drawer"
          phx-click={open_drawer()}
          class="-ms-2 grid size-10 shrink-0 place-items-center rounded-xl text-base-content/80 transition hover:bg-base-200 active:scale-95 lg:hidden"
        >
          <.icon name="hero-bars-3" class="size-6" />
        </button>
        <.link navigate={~p"/"} id="site-logo" class="shrink-0 leading-none">
          <span class="block text-2xl font-black tracking-tight text-primary lg:text-[1.9rem]">
            Taamol
          </span>
          <span class="mt-1 hidden text-[11px] text-base-content/55 sm:block">
            {gettext("News for our community")}
          </span>
        </.link>

        <nav id="main-nav" aria-label={gettext("Categories")} class="hidden h-full min-w-0 lg:block">
          <ul
            id="main-nav-items"
            phx-hook=".NavIndicator"
            class="relative flex h-full items-center gap-0.5 text-sm font-bold xl:gap-1"
          >
            <%!-- the pill behind the active item; positioned by the hook below --%>
            <span
              id="main-nav-indicator"
              phx-update="ignore"
              data-role="nav-indicator"
              aria-hidden="true"
              class="pointer-events-none absolute top-1/2 h-9 -translate-y-1/2 rounded-full bg-primary/10 opacity-0 ring-1 ring-primary/15 transition-[left,width,opacity,background-color] duration-300 ease-out data-[preview]:bg-base-content/[0.06] data-[preview]:ring-transparent"
            />
            <li class="flex">
              <.nav_link to={~p"/"} active={@active == :home}>{gettext("Home")}</.nav_link>
            </li>
            <li class="flex">
              <.nav_link to={~p"/news"} active={@active == :news}>{gettext("News")}</.nav_link>
            </li>
            <li class="flex">
              <.nav_link to={~p"/calendar"} active={@active == :calendar}>
                {gettext("Calendar")}
              </.nav_link>
            </li>
            <li class="flex">
              <.nav_link to={~p"/gallery"} active={@active == :gallery}>
                {gettext("Gallery")}
              </.nav_link>
            </li>
            <li class="flex">
              <.nav_link to={~p"/contact"} active={@active == :contact}>
                {gettext("Contact")}
              </.nav_link>
            </li>
          </ul>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".NavIndicator">
            // Slides the pill to the active item. LiveView rebuilds the header on
            // every page, so the pill's last position is kept on `window` and the
            // new page animates from there. Hovering previews other items.
            const reduceMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches

            export default {
              mounted() {
                this.indicator = this.el.querySelector("[data-role=nav-indicator]")
                const previous = window.__taamolNavIndicator
                const active = this.activeItem()

                if (active && previous && !reduceMotion()) {
                  this.place(previous, false)
                  requestAnimationFrame(() => requestAnimationFrame(() => this.reset(true)))
                } else {
                  this.reset(false)
                }

                this.el.addEventListener("mouseover", (e) => {
                  const item = e.target.closest("[data-nav-item]")
                  if (item && this.el.contains(item)) {
                    this.place(this.rect(item), true, item !== this.activeItem())
                  }
                })
                this.el.addEventListener("mouseleave", () => this.reset(true))
                // start moving right away; the next page picks up from here
                this.el.addEventListener("click", (e) => {
                  const link = e.target.closest("a[data-nav-item]")
                  if (!link) return
                  window.__taamolNavIndicator = this.rect(link)
                  this.place(window.__taamolNavIndicator, true)
                })
                this.onResize = () => this.reset(false)
                window.addEventListener("resize", this.onResize)
              },
              updated() { this.reset(true) },
              destroyed() { window.removeEventListener("resize", this.onResize) },

              activeItem() { return this.el.querySelector("[data-nav-item][data-active]") },
              rect(item) {
                const a = item.getBoundingClientRect(), b = this.el.getBoundingClientRect()
                return {left: a.left - b.left, width: a.width}
              },
              place({left, width}, animate, preview = false) {
                const style = this.indicator.style
                style.transition = animate && !reduceMotion() ? "" : "none"
                style.left = `${left}px`
                style.width = `${width}px`
                style.opacity = "1"
                this.indicator.toggleAttribute("data-preview", preview)
              },
              reset(animate) {
                const active = this.activeItem()
                if (active) {
                  window.__taamolNavIndicator = this.rect(active)
                  this.place(window.__taamolNavIndicator, animate)
                } else {
                  window.__taamolNavIndicator = null
                  this.indicator.style.opacity = "0"
                }
              },
            }
          </script>
        </nav>

        <div class="ms-auto flex items-center gap-2 sm:gap-3">
          <.prayer_times />
          <.locale_toggle id="header-locale" />
          <div class="hidden lg:block">
            <.theme_switch id="header-theme" compact />
          </div>
          <.link
            :if={@donations?}
            id="header-donate"
            navigate={~p"/donate"}
            title={gettext("Donate")}
            aria-label={gettext("Donate")}
            class="hidden h-8 items-center gap-1.5 rounded-full bg-rose-500/10 px-2.5 text-[13px] font-semibold text-rose-600 ring-1 ring-rose-500/20 transition hover:bg-rose-500/15 active:scale-95 lg:inline-flex 2xl:px-3.5 dark:text-rose-400"
          >
            <.donate_icon class="size-4" />
            <span class="hidden 2xl:inline">{gettext("Donate")}</span>
          </.link>
          <%= if @current_scope do %>
            <.user_menu current_scope={@current_scope} class="hidden lg:block" />
          <% else %>
            <.link
              href={~p"/users/log-in"}
              class="hidden whitespace-nowrap text-sm font-medium transition-colors hover:text-primary lg:inline"
            >
              {gettext("Log in")}
            </.link>
            <.link
              href={~p"/users/register"}
              class="hidden h-8 items-center whitespace-nowrap rounded-full bg-primary px-4 text-[13px] font-semibold text-primary-content transition hover:opacity-85 lg:inline-flex"
            >
              {gettext("Register")}
            </.link>
          <% end %>
        </div>
      </div>
    </header>

    <main class={[
      "pb-12 lg:pb-16",
      if(@wide, do: nil, else: "px-4 pt-10 sm:px-6 sm:pt-16 lg:px-8")
    ]}>
      <div class={if(@wide, do: nil, else: "mx-auto max-w-2xl space-y-4")}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.site_footer current_scope={@current_scope} />

    <.mobile_drawer current_scope={@current_scope} active={@active} />

    <nav
      id="bottom-nav"
      aria-label={gettext("Main")}
      class="fixed inset-x-0 bottom-0 z-40 border-t border-base-300 bg-base-100/95 pb-[env(safe-area-inset-bottom)] backdrop-blur-md lg:hidden"
    >
      <ul class="mx-auto grid max-w-md grid-cols-4">
        <li>
          <.bottom_nav_link
            to={~p"/"}
            icon="hero-home"
            active_icon="hero-home-solid"
            active={@active == :home}
          >
            {gettext("Home")}
          </.bottom_nav_link>
        </li>
        <li>
          <.bottom_nav_link
            to={~p"/news"}
            icon="hero-newspaper"
            active_icon="hero-newspaper-solid"
            active={@active == :news}
          >
            {gettext("News")}
          </.bottom_nav_link>
        </li>
        <li>
          <.bottom_nav_link
            to={~p"/calendar"}
            icon="hero-calendar-days"
            active_icon="hero-calendar-days-solid"
            active={@active == :calendar}
          >
            {gettext("Calendar")}
          </.bottom_nav_link>
        </li>
        <li>
          <.bottom_nav_link
            to={~p"/menu"}
            icon="hero-user-circle"
            active_icon="hero-user-circle-solid"
            active={@active == :menu}
          >
            {gettext("Profile")}
          </.bottom_nav_link>
        </li>
      </ul>
    </nav>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The dashboard shell: a sidebar with the sections the user may use, a top
  bar with breadcrumbs, theme, language and account menu, and the page.

      <Layouts.dashboard flash={@flash} current_scope={@current_scope} active={:news} title="News">
        ...
      </Layouts.dashboard>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :active, :atom, default: nil, doc: "the current sidebar item"
  attr :title, :string, required: true, doc: "shown in the breadcrumb"
  slot :inner_block, required: true

  def dashboard(assigns) do
    scope = assigns.current_scope

    groups =
      [
        {gettext("General"),
         [
           {:overview, gettext("Overview"), "hero-squares-2x2", ~p"/dashboard", true},
           {:bookings, gettext("Bookings"), "hero-bookmark-square", ~p"/dashboard/bookings", true}
         ]},
        {gettext("Content"),
         [
           {:news, gettext("News"), "hero-newspaper", ~p"/dashboard/news",
            Taamol.Accounts.can?(scope, :manage_news)},
           {:events, gettext("Calendar events"), "hero-calendar-days", ~p"/dashboard/events",
            Taamol.Accounts.can?(scope, :manage_events)},
           {:gallery, gettext("Gallery"), "hero-photo", ~p"/dashboard/gallery",
            Taamol.Accounts.can?(scope, :manage_gallery)},
           {:booking_services, gettext("Booking services"), "hero-building-library",
            ~p"/dashboard/booking-services", Taamol.Accounts.can?(scope, :manage_bookings)}
         ]},
        {gettext("People"),
         [
           {:users, gettext("Users"), "hero-users", ~p"/dashboard/users",
            Taamol.Accounts.can?(scope, :manage_users)},
           {:messages, gettext("Messages"), "hero-inbox", ~p"/dashboard/messages",
            Taamol.Accounts.can?(scope, :manage_messages)}
         ]},
        {gettext("Settings"),
         [
           {:site_settings, gettext("Site settings"), "hero-adjustments-horizontal",
            ~p"/dashboard/settings", Taamol.Accounts.can?(scope, :manage_settings)},
           {:account, gettext("Account settings"), "hero-user-circle", ~p"/users/settings", true}
         ]}
      ]
      |> Enum.map(fn {label, items} -> {label, Enum.filter(items, &elem(&1, 4))} end)
      |> Enum.reject(fn {_label, items} -> items == [] end)

    assigns =
      assigns
      |> assign(:groups, groups)
      |> assign(:unread_messages, Taamol.Contact.unread_count(scope))
      |> assign(:pending_bookings, Taamol.Bookings.pending_count(scope))

    ~H"""
    <div id="dashboard-shell" class="group/shell min-h-screen bg-base-200/40">
      <%!-- mobile backdrop --%>
      <div
        class="fixed inset-0 z-40 hidden bg-black/40 group-[.sidebar-open]/shell:block lg:!hidden"
        phx-click={JS.remove_class("sidebar-open", to: "#dashboard-shell")}
      />

      <aside
        id="dashboard-sidebar"
        class="fixed inset-y-0 start-0 z-50 flex w-64 flex-col border-e border-base-300 bg-base-100 transition-transform duration-200 max-lg:-translate-x-full max-lg:rtl:translate-x-full group-[.sidebar-open]/shell:translate-x-0"
      >
        <div class="flex h-16 items-center gap-3 px-5">
          <.link navigate={~p"/"} class="leading-none">
            <span class="block text-xl font-black tracking-tight text-primary">Taamol</span>
            <span class="text-[11px] text-base-content/55">{gettext("Dashboard")}</span>
          </.link>
        </div>

        <nav aria-label={gettext("Dashboard")} class="flex-1 overflow-y-auto px-3 pb-6">
          <div :for={{label, items} <- @groups} class="mt-4 first:mt-1">
            <p class="px-3 pb-1.5 text-[11px] font-semibold uppercase tracking-wider text-base-content/45">
              {label}
            </p>
            <ul class="space-y-0.5">
              <li :for={{key, name, icon, path, _allowed} <- items}>
                <.link
                  navigate={path}
                  id={"dashboard-nav-#{key}"}
                  aria-current={if(@active == key, do: "page")}
                  class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm text-base-content/75 transition hover:bg-base-200 hover:text-base-content aria-[current=page]:bg-primary/10 aria-[current=page]:font-semibold aria-[current=page]:text-primary"
                >
                  <.icon name={icon} class="size-5 shrink-0" />
                  {name}
                  <span
                    :if={key == :bookings and @pending_bookings > 0}
                    id="pending-bookings"
                    class="ms-auto min-w-5 rounded-full bg-primary px-1.5 text-center text-[11px] font-semibold leading-5 text-primary-content"
                  >
                    {@pending_bookings}
                  </span>
                  <span
                    :if={key == :messages and @unread_messages > 0}
                    id="unread-messages"
                    class="ms-auto min-w-5 rounded-full bg-primary px-1.5 text-center text-[11px] font-semibold leading-5 text-primary-content"
                  >
                    {@unread_messages}
                  </span>
                </.link>
              </li>
            </ul>
          </div>
        </nav>

        <div class="border-t border-base-300 p-3">
          <.link
            navigate={~p"/"}
            class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm text-base-content/70 transition hover:bg-base-200"
          >
            <.icon name="hero-arrow-left" class="size-5 rtl:rotate-180" />
            {gettext("Back to the site")}
          </.link>
        </div>
      </aside>

      <div class="lg:ps-64">
        <header class="sticky top-0 z-30 flex h-16 items-center gap-3 border-b border-base-300 bg-base-100/90 px-4 backdrop-blur-md sm:px-6">
          <button
            type="button"
            id="dashboard-sidebar-toggle"
            aria-label={gettext("Menu")}
            phx-click={JS.toggle_class("sidebar-open", to: "#dashboard-shell")}
            class="grid size-9 place-items-center rounded-lg transition hover:bg-base-200 lg:hidden"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <nav aria-label={gettext("Breadcrumb")} class="flex min-w-0 items-center gap-2 text-sm">
            <.link
              navigate={~p"/dashboard"}
              class="text-base-content/55 transition-colors hover:text-base-content"
            >
              {gettext("Dashboard")}
            </.link>
            <.icon
              name="hero-chevron-right-micro"
              class="size-4 shrink-0 text-base-content/35 rtl:rotate-180"
            />
            <span class="truncate font-medium">{@title}</span>
          </nav>
          <div class="ms-auto flex items-center gap-2">
            <.theme_switch id="dashboard-theme" />
            <.locale_toggle id="dashboard-locale" />
            <.user_menu current_scope={@current_scope} />
          </div>
        </header>

        <main class="mx-auto max-w-7xl p-4 sm:p-6 lg:p-8">
          {render_slot(@inner_block)}
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  @doc "Page heading with optional action buttons, used inside the dashboard."
  def dashboard_heading(assigns) do
    ~H"""
    <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold tracking-tight">{@title}</h1>
        <p :if={@subtitle} class="mt-1 text-sm text-base-content/60">{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="flex flex-wrap items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  # opens/closes the mobile drawer; scrolling the page is locked while open
  defp open_drawer do
    JS.add_class("drawer-open", to: "#mobile-drawer")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus(to: "#mobile-menu-close")
  end

  defp close_drawer(js \\ %JS{}) do
    js
    |> JS.remove_class("drawer-open", to: "#mobile-drawer")
    |> JS.remove_class("overflow-hidden", to: "body")
  end

  attr :current_scope, :map, default: nil
  attr :active, :atom, default: nil

  # Slide-in navigation for phones and tablets. It enters from the reading
  # start side (left in English/Swedish, right in Persian).
  defp mobile_drawer(assigns) do
    assigns =
      assigns
      |> assign(:social_links, Taamol.Settings.social_links())

    ~H"""
    <div
      id="mobile-drawer"
      class="group/drawer pointer-events-none fixed inset-0 z-50 lg:hidden [&.drawer-open]:pointer-events-auto"
      phx-window-keydown={close_drawer()}
      phx-key="Escape"
    >
      <div
        class="absolute inset-0 bg-black/40 opacity-0 backdrop-blur-[2px] transition-opacity duration-300 group-[.drawer-open]/drawer:opacity-100"
        phx-click={close_drawer()}
      />

      <nav
        role="dialog"
        aria-modal="true"
        aria-label={gettext("Menu")}
        class="absolute inset-y-0 start-0 flex w-[min(21rem,88vw)] -translate-x-full flex-col bg-base-100 shadow-2xl transition-transform duration-300 ease-out rtl:translate-x-full group-[.drawer-open]/drawer:translate-x-0"
      >
        <div class="flex h-16 shrink-0 items-center justify-between border-b border-base-300/70 px-4">
          <.link navigate={~p"/"} phx-click={close_drawer()} class="leading-none">
            <span class="block text-2xl font-black tracking-tight text-primary">Taamol</span>
            <span class="mt-1 block text-[11px] text-base-content/55">
              {gettext("News for our community")}
            </span>
          </.link>
          <button
            type="button"
            id="mobile-menu-close"
            aria-label={gettext("Close menu")}
            phx-click={close_drawer()}
            class="grid size-10 place-items-center rounded-xl text-base-content/70 transition hover:bg-base-200 active:scale-95"
          >
            <.icon name="hero-x-mark" class="size-6" />
          </button>
        </div>

        <div class="flex-1 space-y-6 overflow-y-auto overscroll-contain px-4 py-5">
          <%!-- account --%>
          <%= if @current_scope do %>
            <.link
              navigate={~p"/dashboard"}
              phx-click={close_drawer()}
              class="flex items-center gap-3 rounded-2xl bg-base-200/70 p-3 transition hover:bg-base-200"
            >
              <.avatar user={@current_scope.user} class="size-11 text-base" />
              <span class="min-w-0 flex-1">
                <span dir="auto" class="block truncate font-semibold">{@current_scope.user.name}</span>
                <span class="block truncate text-xs text-base-content/55">
                  {@current_scope.user.email}
                </span>
              </span>
              <.icon name="hero-chevron-right" class="size-4 text-base-content/40 rtl:rotate-180" />
            </.link>
          <% else %>
            <div class="grid grid-cols-2 gap-2">
              <.link
                navigate={~p"/users/log-in"}
                phx-click={close_drawer()}
                class="rounded-xl border border-base-300 py-2.5 text-center text-sm font-semibold transition hover:bg-base-200"
              >
                {gettext("Log in")}
              </.link>
              <.link
                navigate={~p"/users/register"}
                phx-click={close_drawer()}
                class="rounded-xl bg-primary py-2.5 text-center text-sm font-semibold text-primary-content transition hover:opacity-85"
              >
                {gettext("Register")}
              </.link>
            </div>
          <% end %>

          <%!-- main pages --%>
          <div class="grid grid-cols-2 gap-2">
            <.drawer_tile to={~p"/"} icon="hero-home" active={@active == :home}>
              {gettext("Home")}
            </.drawer_tile>
            <.drawer_tile to={~p"/calendar"} icon="hero-calendar-days" active={@active == :calendar}>
              {gettext("Calendar")}
            </.drawer_tile>
            <.drawer_tile to={~p"/gallery"} icon="hero-photo" active={@active == :gallery}>
              {gettext("Gallery")}
            </.drawer_tile>
            <.drawer_tile to={~p"/news"} icon="hero-newspaper" active={@active == :news}>
              {gettext("News")}
            </.drawer_tile>
          </div>

          <div class="grid grid-cols-2 gap-2">
            <.link
              navigate={~p"/donate"}
              phx-click={close_drawer()}
              class="flex items-center justify-center gap-2 rounded-2xl bg-rose-500/10 py-3 text-sm font-semibold text-rose-600 ring-1 ring-rose-500/20 transition hover:bg-rose-500/15 dark:text-rose-400"
            >
              <.donate_icon class="size-[18px]" />{gettext("Donate")}
            </.link>
            <.link
              navigate={~p"/contact"}
              phx-click={close_drawer()}
              aria-current={if(@active == :contact, do: "page")}
              class="flex items-center justify-center gap-2 rounded-2xl border border-base-300 py-3 text-sm font-medium transition hover:bg-base-200/60 aria-[current=page]:border-primary/50 aria-[current=page]:text-primary"
            >
              <.icon name="hero-chat-bubble-left-ellipsis" class="size-4" />{gettext("Contact")}
            </.link>
          </div>

          <%!-- preferences --%>
          <section class="space-y-3">
            <h2 class="px-1 text-[11px] font-semibold uppercase tracking-wider text-base-content/50">
              {gettext("Preferences")}
            </h2>
            <div class="flex items-center justify-between rounded-xl bg-base-200/70 px-3 py-2">
              <span class="flex items-center gap-2 text-sm text-base-content/75">
                <.icon name="hero-language" class="size-4" />{gettext("Language")}
              </span>
              <.locale_toggle id="drawer-locale" />
            </div>
            <div class="flex items-center justify-between rounded-xl bg-base-200/70 px-3 py-2">
              <span class="flex items-center gap-2 text-sm text-base-content/75">
                <.icon name="hero-swatch" class="size-4" />{gettext("Theme")}
              </span>
              <.theme_switch id="drawer-theme" />
            </div>
          </section>

          <%!-- account links --%>
          <ul :if={@current_scope} class="space-y-1">
            <li>
              <.link
                navigate={~p"/users/settings"}
                phx-click={close_drawer()}
                class="flex items-center gap-3 rounded-xl px-2.5 py-2.5 text-sm transition hover:bg-base-200"
              >
                <.icon name="hero-cog-6-tooth" class="size-5 text-base-content/50" />
                {gettext("Account settings")}
              </.link>
            </li>
            <li>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="flex items-center gap-3 rounded-xl px-2.5 py-2.5 text-sm text-error transition hover:bg-error/10"
              >
                <.icon name="hero-arrow-right-start-on-rectangle" class="size-5 rtl:rotate-180" />
                {gettext("Log out")}
              </.link>
            </li>
          </ul>
        </div>

        <div
          :if={@social_links != []}
          class="flex shrink-0 flex-wrap justify-center gap-2 border-t border-base-300/70 px-4 py-4 pb-[calc(1rem+env(safe-area-inset-bottom))]"
        >
          <a
            :for={{network, url} <- @social_links}
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            aria-label={TaamolWeb.SocialIcons.name(network)}
            class="grid size-9 place-items-center rounded-full border border-base-300 text-base-content/65 transition hover:border-primary hover:bg-primary hover:text-primary-content"
          >
            <TaamolWeb.SocialIcons.social_icon network={network} class="size-4" />
          </a>
        </div>
      </nav>
    </div>
    """
  end

  attr :to, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp drawer_tile(assigns) do
    ~H"""
    <.link
      navigate={@to}
      phx-click={close_drawer()}
      aria-current={if(@active, do: "page")}
      class="flex flex-col gap-2 rounded-2xl border border-base-300 p-3 text-sm font-medium transition hover:border-primary/40 hover:bg-base-200/60 active:scale-[0.98] aria-[current=page]:border-primary/50 aria-[current=page]:bg-primary/10 aria-[current=page]:text-primary"
    >
      <.icon name={@icon} class="size-5" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :current_scope, :map, default: nil

  # Site footer: brand, category and site links, and the copyright line.
  # Extra bottom padding on phones keeps it clear of the bottom tab bar.
  defp site_footer(assigns) do
    assigns =
      assigns
      |> assign(:year, Date.utc_today().year)
      |> assign(:social_links, Taamol.Settings.social_links())

    ~H"""
    <footer
      id="site-footer"
      class="border-t border-base-300/70 bg-base-100 pb-[calc(4.5rem+env(safe-area-inset-bottom))] lg:pb-0"
    >
      <div class="mx-auto max-w-7xl px-4 pt-12 sm:px-6 lg:px-8">
        <div class="grid gap-10 sm:grid-cols-3 lg:grid-cols-[2fr_1fr_1fr]">
          <div class="max-w-xs">
            <.link navigate={~p"/"} class="inline-block leading-none">
              <span class="block text-2xl font-black tracking-tight text-primary">Taamol</span>
              <span class="mt-1 block text-[11px] text-base-content/55">
                {gettext("News for our community")}
              </span>
            </.link>
            <p class="mt-4 text-sm font-medium leading-relaxed text-base-content/70">
              {gettext(
                "News, the Shia calendar, prayer times and community activities, in one place."
              )}
            </p>
            <ul :if={@social_links != []} id="social-links" class="mt-5 flex flex-wrap gap-2.5">
              <li :for={{network, url} <- @social_links}>
                <a
                  href={url}
                  target="_blank"
                  rel="noopener noreferrer"
                  id={"social-#{network}"}
                  aria-label={TaamolWeb.SocialIcons.name(network)}
                  title={TaamolWeb.SocialIcons.name(network)}
                  class="grid size-11 place-items-center rounded-full bg-primary/10 text-primary ring-1 ring-primary/20 transition hover:-translate-y-0.5 hover:bg-primary hover:text-primary-content hover:shadow-md hover:shadow-primary/30"
                >
                  <TaamolWeb.SocialIcons.social_icon network={network} class="size-5" />
                </a>
              </li>
            </ul>
            <.link
              :if={is_nil(@current_scope)}
              navigate={~p"/users/register"}
              class="mt-5 inline-flex items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-medium text-primary-content transition hover:opacity-85"
            >
              {gettext("Join the community")}
              <.icon name="hero-arrow-right-micro" class="size-4 rtl:rotate-180" />
            </.link>
          </div>

          <nav aria-labelledby="footer-explore">
            <h2
              id="footer-explore"
              class="text-xs font-bold uppercase tracking-wider text-base-content/60"
            >
              {gettext("Explore")}
            </h2>
            <ul class="mt-4 space-y-2.5 text-sm font-semibold">
              <li>
                <.footer_link to={~p"/news"}>{gettext("News")}</.footer_link>
              </li>
              <li>
                <.footer_link to={~p"/calendar"}>{gettext("Calendar")}</.footer_link>
              </li>
              <li>
                <.footer_link to={~p"/gallery"}>{gettext("Gallery")}</.footer_link>
              </li>
              <li>
                <.footer_link to={~p"/contact"}>{gettext("Contact")}</.footer_link>
              </li>
              <li>
                <.footer_link to={~p"/donate"}>{gettext("Donate")}</.footer_link>
              </li>
            </ul>
          </nav>

          <nav aria-labelledby="footer-account">
            <h2
              id="footer-account"
              class="text-xs font-bold uppercase tracking-wider text-base-content/60"
            >
              {gettext("Account")}
            </h2>
            <ul class="mt-4 space-y-2.5 text-sm font-semibold">
              <%= if @current_scope do %>
                <li><.footer_link to={~p"/dashboard"}>{gettext("Dashboard")}</.footer_link></li>
                <li>
                  <.footer_link to={~p"/users/settings"}>{gettext("Account settings")}</.footer_link>
                </li>
                <li>
                  <.link
                    href={~p"/users/log-out"}
                    method="delete"
                    class="text-base-content/80 transition-colors hover:text-primary"
                  >
                    {gettext("Log out")}
                  </.link>
                </li>
              <% else %>
                <li><.footer_link to={~p"/users/log-in"}>{gettext("Log in")}</.footer_link></li>
                <li>
                  <.footer_link to={~p"/users/register"}>{gettext("Register")}</.footer_link>
                </li>
              <% end %>
            </ul>
          </nav>
        </div>

        <div class="mt-12 flex flex-col gap-2 border-t border-base-300/70 py-6 text-xs text-base-content/55 sm:flex-row sm:items-center sm:justify-between">
          <p>{gettext("© %{year} Taamol. All rights reserved.", year: @year)}</p>
          <p class="inline-flex items-center gap-1.5">
            <.icon name="hero-heart-micro" class="size-3.5 text-primary" />
            {gettext("Made with care for our community")}
          </p>
        </div>
      </div>
    </footer>
    """
  end

  attr :to, :string, required: true
  slot :inner_block, required: true

  defp footer_link(assigns) do
    ~H"""
    <.link navigate={@to} class="text-base-content/80 transition-colors hover:text-primary">
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :to, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@to}
      aria-current={if(@active, do: "page")}
      data-nav-item
      data-active={@active}
      class="relative z-10 flex h-9 items-center whitespace-nowrap rounded-full px-3.5 transition-colors duration-300 hover:text-primary aria-[current=page]:text-primary"
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :to, :string, required: true
  attr :icon, :string, required: true
  # written out in full (not built from :icon) so Tailwind generates its CSS
  attr :active_icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp bottom_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@to}
      aria-current={if(@active, do: "page")}
      class="flex flex-col items-center gap-1 py-2.5 text-[11px] text-base-content/55 transition-colors aria-[current=page]:text-primary"
    >
      <.icon name={if(@active, do: @active_icon, else: @icon)} class="size-6" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :group, :string,
    required: true,
    values: ~w(more user),
    doc: "the Tailwind group name of the trigger's parent"

  attr :class, :string, default: nil
  slot :inner_block, required: true

  # Hover/focus dropdown panel, positioned under its `group/<name>` parent.
  # Class names are spelled out in full so Tailwind can find them.
  defp dropdown(assigns) do
    assigns =
      assign(
        assigns,
        :open_classes,
        case assigns.group do
          "more" ->
            "group-hover/more:visible group-hover/more:translate-y-0 group-hover/more:opacity-100 group-focus-within/more:visible group-focus-within/more:translate-y-0 group-focus-within/more:opacity-100"

          "user" ->
            "group-hover/user:visible group-hover/user:translate-y-0 group-hover/user:opacity-100 group-focus-within/user:visible group-focus-within/user:translate-y-0 group-focus-within/user:opacity-100"
        end
      )

    ~H"""
    <div class={[
      "invisible absolute top-full z-50 translate-y-1 pt-2 opacity-0 transition duration-200 ease-out",
      @open_classes,
      @class
    ]}>
      <div class="rounded-2xl border border-base-300 bg-base-100 p-1 shadow-xl shadow-base-content/10">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :current_scope, :map, required: true
  attr :class, :string, default: nil

  @doc "Avatar, name and email with a dropdown of account links."
  def user_menu(assigns) do
    ~H"""
    <div id="user-menu" class={["group/user relative", @class]}>
      <button
        type="button"
        id="user-menu-trigger"
        aria-haspopup="true"
        class="flex items-center gap-3 rounded-full pe-2 transition hover:bg-base-200"
      >
        <.avatar user={@current_scope.user} class="size-8 text-xs" />
        <span class="hidden text-start leading-tight xl:block">
          <span class="block max-w-40 truncate text-sm font-semibold" dir="auto">
            {@current_scope.user.name}
          </span>
          <span class="block max-w-40 truncate text-xs text-base-content/55">
            {@current_scope.user.email}
          </span>
        </span>
        <.icon
          name="hero-chevron-down-micro"
          class="size-4 text-base-content/50 transition-transform group-hover/user:rotate-180 group-focus-within/user:rotate-180"
        />
      </button>
      <.dropdown group="user" class="end-0 w-56">
        <.link
          id="dashboard-link"
          navigate={~p"/dashboard"}
          class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm transition hover:bg-base-200"
        >
          <.icon name="hero-chart-bar-square" class="size-4 text-base-content/50" />
          {gettext("Dashboard")}
        </.link>
        <.link
          :if={Taamol.Accounts.can?(@current_scope, :manage_users)}
          navigate={~p"/dashboard/users"}
          class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm transition hover:bg-base-200"
        >
          <.icon name="hero-users" class="size-4 text-base-content/50" />
          {gettext("Users")}
        </.link>
        <.link
          navigate={~p"/dashboard/bookings"}
          class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm transition hover:bg-base-200"
        >
          <.icon name="hero-bookmark-square" class="size-4 text-base-content/50" />
          {gettext("My bookings")}
        </.link>
        <.link
          navigate={~p"/users/settings"}
          class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm transition hover:bg-base-200"
        >
          <.icon name="hero-cog-6-tooth" class="size-4 text-base-content/50" />
          {gettext("Settings")}
        </.link>
        <div class="my-1 border-t border-base-300" />
        <.link
          href={~p"/users/log-out"}
          method="delete"
          class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm text-error transition hover:bg-error/10"
        >
          <.icon name="hero-arrow-right-start-on-rectangle" class="size-4 rtl:rotate-180" />
          {gettext("Log out")}
        </.link>
      </.dropdown>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :class, :string, default: "size-9 text-sm"

  @doc "Round avatar with the user's initials."
  def avatar(assigns) do
    initials =
      (assigns.user.name || assigns.user.email || "?")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.take(2)
      |> Enum.map_join(&String.first/1)
      |> String.upcase()

    assigns = assign(assigns, :initials, initials)

    ~H"""
    <span
      aria-hidden="true"
      class={[
        "grid shrink-0 place-items-center rounded-full bg-primary/15 font-semibold text-primary",
        @class
      ]}
    >
      {@initials}
    </span>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  attr :class, :string, default: "size-5"

  @doc """
  A hand holding a heart, for donations (Heroicons has no such icon). From
  Lucide (lucide.dev, "hand-heart", ISC license), drawn in `currentColor`.
  """
  def donate_icon(assigns) do
    ~H"""
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["shrink-0", @class]}
    >
      <path d="M11 14h2a2 2 0 0 0 0-4h-3c-.6 0-1.1.2-1.4.6L3 16" />
      <path d="m14.45 13.39 5.05-4.694C20.196 8 21 6.85 21 5.75a2.75 2.75 0 0 0-4.797-1.837.276.276 0 0 1-.406 0A2.75 2.75 0 0 0 11 5.75c0 1.2.802 2.248 1.5 2.946L16 11.95" />
      <path d="m2 15 6 6" />
      <path d="m7 20 1.6-1.4c.3-.4.8-.6 1.4-.6h4c1.1 0 2.1-.4 2.8-1.2l4.6-4.4a1 1 0 0 0-2.75-2.91" />
    </svg>
    """
  end

  attr :id, :string, default: "locale-toggle"

  @doc """
  Language switch, styled like the day/night switch: a pill with a globe
  knob and the language it switches to ("SV" on Persian pages, "فا" on
  Swedish ones). It posts that
  language to `/locale`, which saves it and returns to the same page.
  """
  def locale_toggle(assigns) do
    current = Gettext.get_locale(TaamolWeb.Gettext)

    current =
      if current in TaamolWeb.Locale.locales(), do: current, else: TaamolWeb.Locale.default()

    {target, code, label} =
      if current == "sv",
        do: {"fa", "فا", gettext("Switch to Persian")},
        else: {"sv", "SV", gettext("Switch to Swedish")}

    assigns = assign(assigns, form: to_form(%{}), target: target, code: code, label: label)

    ~H"""
    <.form for={@form} id={@id} action={~p"/locale"} method="post" class="inline-flex">
      <button
        type="submit"
        name="locale"
        value={@target}
        id={"#{@id}-button"}
        aria-label={@label}
        title={@label}
        dir="ltr"
        class="inline-flex h-8 shrink-0 items-center gap-2 rounded-full bg-neutral-200 p-1 pe-3 text-neutral-800 shadow-inner ring-1 ring-black/5 transition-colors duration-300 hover:bg-neutral-300/80 active:scale-95 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary [[data-theme=dark]_&]:bg-neutral-800 [[data-theme=dark]_&]:text-white [[data-theme=dark]_&]:ring-white/10 [[data-theme=dark]_&]:hover:bg-neutral-700"
      >
        <%!-- white knob with the globe, like the day/night switch --%>
        <span class="grid size-6 place-items-center rounded-full bg-white shadow-md">
          <.icon name="hero-globe-alt" class="size-3.5 text-neutral-800" />
        </span>
        <span lang={@target} class="text-xs font-bold tracking-wider">{@code}</span>
      </button>
    </.form>
    """
  end

  attr :id, :string, default: "theme-switch"
  attr :class, :string, default: nil
  attr :compact, :boolean, default: false, doc: "show the labels only on very wide screens"

  @doc """
  Day/night switch: a light pill reading "Day mode" with a sun knob on the
  right, or a dark pill with a moon knob on the left reading "Night mode".
  Styled from `[data-theme]` on <html>, so it is right before any JavaScript
  runs; the toggle itself lives in root.html.heex.
  """
  def theme_switch(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-click={JS.dispatch("phx:toggle-theme")}
      aria-label={gettext("Dark mode")}
      title={gettext("Dark mode")}
      dir="ltr"
      class={[
        "inline-flex h-8 shrink-0 items-center rounded-full bg-neutral-200 p-1 text-neutral-800 shadow-inner ring-1 ring-black/5 transition-colors duration-300 hover:bg-neutral-300/80 active:scale-95 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
        "[[data-theme=dark]_&]:bg-neutral-800 [[data-theme=dark]_&]:text-white [[data-theme=dark]_&]:ring-white/10 [[data-theme=dark]_&]:hover:bg-neutral-700",
        @class
      ]}
    >
      <%!-- day: label (or a faint moon when compact), then the sun knob on the right --%>
      <span class="flex items-center gap-2 [[data-theme=dark]_&]:hidden">
        <span class={[
          "whitespace-nowrap ps-2.5 text-[10px] font-semibold uppercase tracking-wider",
          @compact && "hidden 2xl:inline"
        ]}>
          {gettext("Day mode")}
        </span>
        <.icon
          :if={@compact}
          name="hero-moon-micro"
          class="ms-1.5 size-3.5 text-neutral-400 2xl:hidden"
        />
        <span class="grid size-6 place-items-center rounded-full bg-white shadow-md">
          <.icon name="hero-sun-solid" class="size-3.5 text-neutral-800" />
        </span>
      </span>
      <%!-- night: the moon knob on the left, then the label --%>
      <span class="hidden items-center gap-2 [[data-theme=dark]_&]:flex">
        <span class="grid size-6 place-items-center rounded-full bg-white shadow-md">
          <.icon name="hero-moon-solid" class="size-3.5 text-neutral-800" />
        </span>
        <span class={[
          "whitespace-nowrap pe-2.5 text-[10px] font-semibold uppercase tracking-wider",
          @compact && "hidden 2xl:inline"
        ]}>
          {gettext("Night mode")}
        </span>
        <.icon
          :if={@compact}
          name="hero-sun-micro"
          class="me-1.5 size-3.5 text-neutral-500 2xl:hidden"
        />
      </span>
    </button>
    """
  end

  @doc """
  Shows the next prayer time in the header, with a popover on hover/focus
  containing a countdown on a sun-path arc, the day's prayer times and, during
  Ramadan, a suhoor/iftar banner.

  The `<prayer-times>` custom element (see `assets/js/prayer_times.js`) asks
  the browser for the visitor's location, fetches the times computed by
  `Taamol.PrayTime` from `/api/prayer-times`, and fills in this markup.
  `phx-update="ignore"` keeps LiveView patches from wiping what it renders.
  The state attributes (`data-state`, `data-night`, `data-ramadan`) live on
  the inner `data-role="root"` element because LiveView still patches the
  attributes of the ignored container itself.
  """
  attr :id, :string, default: "prayer-times"

  attr :variant, :atom,
    default: :popover,
    values: [:popover, :card],
    doc: "a header chip with a hover popover, or an inline card (for sidebars)"

  def prayer_times(assigns) do
    assigns =
      assign(assigns, :prayers, [
        {"fajr", gettext("Fajr"), :cloud},
        {"sunrise", gettext("Sunrise"), :cloud_sun},
        {"dhuhr", gettext("Dhuhr"), :sun},
        {"asr", gettext("Asr"), :sun_soft},
        {"maghrib", gettext("Maghrib"), :cloud_sun},
        {"isha", gettext("Isha"), :moon}
      ])

    ~H"""
    <prayer-times :if={@variant == :popover} id={@id} phx-update="ignore" class="block">
      <div data-role="root" data-state="loading" class="group/prayer relative">
        <button
          type="button"
          id={"#{@id}-trigger"}
          data-role="trigger"
          aria-describedby={"#{@id}-popover"}
          class="inline-flex h-8 items-center gap-2 rounded-full border border-base-300 bg-base-100 pe-3 ps-1 text-xs transition hover:border-primary/40 hover:bg-base-200 focus-visible:outline-2 focus-visible:outline-primary"
        >
          <span class="relative grid size-6 place-items-center rounded-full bg-primary/10 text-primary">
            <.icon name="hero-moon-micro" class="size-4" />
            <span class="absolute -end-0.5 -top-0.5 hidden size-2 rounded-full bg-primary group-data-[state=ready]/prayer:block group-data-[state=ready]/prayer:motion-safe:animate-pulse" />
          </span>
          <span data-role="next-label" class="text-base-content/70">
            {gettext("Prayer times")}
          </span>
          <span
            data-role="next-time"
            class="font-bold tabular-nums group-data-[state=loading]/prayer:hidden"
          />
          <span class="hidden h-3 w-10 rounded bg-base-300 motion-safe:animate-pulse group-data-[state=loading]/prayer:inline-block" />
        </button>

        <div
          id={"#{@id}-popover"}
          role="tooltip"
          class="invisible fixed inset-x-3 top-16 z-50 translate-y-1 pt-2 opacity-0 sm:inset-x-auto sm:end-4 sm:w-[18rem] lg:absolute lg:end-0 lg:top-full transition duration-200 ease-out group-hover/prayer:visible group-hover/prayer:translate-y-0 group-hover/prayer:opacity-100 group-focus-within/prayer:visible group-focus-within/prayer:translate-y-0 group-focus-within/prayer:opacity-100"
        >
          <.prayer_panel
            id={@id}
            prayers={@prayers}
            class="rounded-2xl border border-base-300 bg-base-100 p-1 shadow-xl shadow-base-content/10"
          />
        </div>
      </div>
    </prayer-times>

    <prayer-times :if={@variant == :card} id={@id} phx-update="ignore" class="block">
      <div data-role="root" data-state="loading" class="group/prayer cursor-default">
        <.prayer_panel id={@id} prayers={@prayers} />
      </div>
    </prayer-times>
    """
  end

  attr :id, :string, required: true
  attr :prayers, :list, required: true
  attr :class, :string, default: nil

  # The countdown, arc and prayer grid shared by the popover and the card.
  defp prayer_panel(assigns) do
    ~H"""
    <div class={["space-y-1 text-base-content", @class]}>
      <%!-- Ramadan banner, shown only during Ramadan --%>
      <section
        id={"#{@id}-ramadan"}
        class="hidden rounded-xl bg-primary p-3 text-primary-content group-data-[ramadan]/prayer:block"
      >
        <p class="flex items-center gap-1.5 text-sm font-semibold">
          <.icon name="hero-moon-solid" class="size-4" />
          {gettext("Ramadan Mubarak")}
        </p>
        <p
          data-role="ramadan-day"
          data-template={gettext("Day %{day} of %{total}", day: "%{day}", total: "%{total}")}
          class="mt-0.5 text-[11px] opacity-80"
        />
        <div class="mt-2 h-1 overflow-hidden rounded-full bg-primary-content/25">
          <div
            data-role="ramadan-progress"
            class="h-full w-0 rounded-full bg-primary-content transition-[width] duration-700"
          />
        </div>
        <div class="mt-3 flex items-end justify-between gap-2">
          <dl class="flex gap-4">
            <div>
              <dt class="text-[10px] opacity-75">{gettext("Suhoor")}</dt>
              <dd data-role="suhoor" class="text-sm font-bold tabular-nums" />
            </div>
            <div>
              <dt class="text-[10px] opacity-75">{gettext("Iftar")}</dt>
              <dd data-role="iftar" class="text-sm font-bold tabular-nums" />
            </div>
          </dl>
          <div class="rounded-lg bg-primary-content/15 px-3 py-1.5 text-end">
            <p
              data-role="fast-label"
              data-suhoor={gettext("Until suhoor ends")}
              data-iftar={gettext("Until iftar")}
              class="text-[10px] opacity-80"
            />
            <p data-role="fast-countdown" class="text-base font-bold tabular-nums" />
          </div>
        </div>
      </section>

      <section class="p-2">
        <div class="flex flex-wrap items-center gap-1.5 text-[11px] text-base-content/70">
          <span class="inline-flex items-center gap-1 rounded-full bg-base-200 px-2 py-0.5">
            <.icon name="hero-map-pin-micro" class="size-3 text-primary" />
            <span data-role="place" />
          </span>
          <span class="inline-flex items-center gap-1 rounded-full bg-base-200 px-2 py-0.5 has-[[data-role=hijri]:empty]:hidden">
            <.icon name="hero-moon-micro" class="size-3 text-primary" />
            <span data-role="hijri" />
          </span>
        </div>

        <%!-- sun path from Fajr (left) to Isha (right) --%>
        <div dir="ltr" class="relative mt-2 aspect-[200/112] w-full">
          <svg
            viewBox="0 0 200 112"
            class="absolute inset-0 size-full overflow-visible"
            aria-hidden="true"
          >
            <path
              d="M 12 104 A 88 88 0 0 1 188 104"
              pathLength="1"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              class="text-base-300"
            />
            <path
              data-role="arc-progress"
              d="M 12 104 A 88 88 0 0 1 188 104"
              pathLength="1"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-dasharray="0 1"
              class="text-primary"
            />
            <circle
              :for={{key, _label, _icon} <- @prayers}
              data-marker={key}
              r="2.5"
              cx="12"
              cy="104"
              stroke-width="1.5"
              class="fill-base-100 stroke-base-content/30 transition-colors duration-500 data-[past]:fill-base-content/25 data-[past]:stroke-transparent data-[active]:fill-primary data-[active]:stroke-primary"
            />
          </svg>
          <%!-- each prayer's icon, just inside the arc by its point; they rise
               into place when the panel appears (prayer_times.js) --%>
          <span
            :for={{key, _label, icon} <- @prayers}
            data-marker-icon={key}
            class="group/mark pointer-events-none absolute -translate-x-1/2 -translate-y-1/2"
            style="left: 6%; top: 93%"
          >
            <span class="block translate-y-2 scale-[0.7] text-base-content/45 opacity-0 transition duration-500 ease-out group-data-[shown]/mark:translate-y-0 group-data-[shown]/mark:opacity-100 group-data-[past]/mark:text-base-content/25 group-data-[active]/mark:scale-[0.85] group-data-[active]/mark:text-primary">
              <.prayer_icon type={icon} />
            </span>
          </span>
          <span
            data-role="sun"
            class="absolute z-10 grid size-6 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-base-100 shadow-md ring-1 ring-base-300"
            style="left: 6%; top: 93%"
          >
            <.icon
              name="hero-sun-solid"
              class="size-4 text-primary group-data-[night]/prayer:hidden"
            />
            <.icon
              name="hero-moon-solid"
              class="hidden size-3.5 text-base-content/70 group-data-[night]/prayer:block"
            />
          </span>
          <div class="absolute inset-x-0 bottom-0 text-center">
            <p data-role="countdown" class="text-3xl font-bold tracking-tight tabular-nums">
              --:--:--
            </p>
            <p
              data-role="until"
              data-template={gettext("until %{prayer}", prayer: "%{prayer}")}
              class="text-[11px] text-base-content/60"
            />
            <p data-role="next-at" class="text-xs font-semibold tabular-nums text-base-content/60" />
          </div>
        </div>

        <ul
          id={"#{@id}-grid"}
          class="mt-3 grid grid-cols-3 gap-1 group-data-[state=denied]/prayer:hidden group-data-[state=error]/prayer:hidden"
        >
          <li
            :for={{key, label, icon} <- @prayers}
            id={"#{@id}-time-#{key}"}
            data-prayer={key}
            data-label={label}
            class="group/cell flex flex-col items-center gap-0.5 rounded-xl px-1 py-2 text-base-content/70 transition duration-300 hover:bg-base-200 data-[next]:bg-primary/10 data-[next]:text-primary data-[past]:opacity-45"
          >
            <.prayer_icon type={icon} />
            <span class="mt-0.5 text-[11px] text-base-content/60 group-data-[next]/cell:text-primary">
              {label}
            </span>
            <span
              data-role="time"
              class="text-base font-extrabold tracking-tight tabular-nums text-base-content group-data-[next]/cell:text-primary"
            >
              <span class="inline-block h-3.5 w-10 rounded bg-base-300 align-middle motion-safe:animate-pulse" />
            </span>
          </li>
        </ul>

        <p class="mt-3 hidden rounded-xl bg-base-200 px-3 py-2 text-center text-xs text-base-content/70 group-data-[state=denied]/prayer:block">
          {gettext("Allow location access in your browser to see prayer times for where you are.")}
        </p>
        <p class="mt-3 hidden rounded-xl bg-base-200 px-3 py-2 text-center text-xs text-base-content/70 group-data-[state=error]/prayer:block">
          {gettext("Prayer times could not be loaded. Click to try again.")}
        </p>
      </section>
    </div>
    """
  end

  attr :type, :atom, required: true, values: [:cloud, :cloud_sun, :sun, :sun_soft, :moon]

  defp prayer_icon(%{type: :cloud_sun} = assigns) do
    ~H"""
    <span aria-hidden="true" class="relative block size-5">
      <.icon name="hero-sun" class="absolute -top-0.5 end-0 size-3.5" />
      <.icon name="hero-cloud-solid" class="absolute bottom-0 start-0 size-4" />
    </span>
    """
  end

  defp prayer_icon(assigns) do
    assigns =
      assign(
        assigns,
        :name,
        case assigns.type do
          :cloud -> "hero-cloud"
          :sun -> "hero-sun-solid"
          :sun_soft -> "hero-sun"
          :moon -> "hero-moon-solid"
        end
      )

    ~H"""
    <.icon name={@name} class="size-5" />
    """
  end
end
