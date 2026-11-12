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
  `active` (`:home`, `:categories`, `:calendar`, `:menu` or a category atom) to highlight the
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
    categories = TaamolWeb.NewsComponents.categories()
    {nav_categories, more_categories} = Enum.split(categories, 4)

    assigns =
      assigns
      |> assign(:categories, categories)
      |> assign(:nav_categories, nav_categories)
      |> assign(:more_categories, more_categories)
      |> assign(:category_tabs?, assigns.active == :home or assigns.active in categories)

    ~H"""
    <header class="sticky top-0 z-40 border-b border-base-300/70 bg-base-100/90 backdrop-blur-md">
      <div class="mx-auto flex h-16 max-w-7xl items-center gap-6 px-4 sm:px-6 lg:h-20 lg:px-8">
        <.link navigate={~p"/"} id="site-logo" class="shrink-0 leading-none">
          <span class="block text-2xl font-black tracking-tight text-primary lg:text-[1.9rem]">
            Taamol
          </span>
          <span class="mt-1 hidden text-[11px] text-base-content/55 sm:block">
            {gettext("News for our community")}
          </span>
        </.link>

        <nav id="main-nav" aria-label={gettext("Categories")} class="hidden h-full min-w-0 lg:block">
          <ul class="flex h-full items-stretch gap-5 text-sm font-medium xl:gap-7">
            <li class="flex">
              <.nav_link to={~p"/"} active={@active == :home}>{gettext("Home")}</.nav_link>
            </li>
            <li class="flex">
              <.nav_link to={~p"/calendar"} active={@active == :calendar}>
                {gettext("Calendar")}
              </.nav_link>
            </li>
            <li :for={category <- @nav_categories} class="flex">
              <.nav_link to={~p"/categories/#{category}"} active={@active == category}>
                {TaamolWeb.NewsComponents.category_name(category)}
              </.nav_link>
            </li>
            <li class="group/more relative flex items-center">
              <button
                type="button"
                id="main-nav-more"
                aria-haspopup="true"
                class={[
                  "inline-flex items-center gap-1 transition-colors hover:text-primary",
                  @active in @more_categories && "text-primary"
                ]}
              >
                {gettext("More")}
                <.icon
                  name="hero-chevron-down-micro"
                  class="size-4 transition-transform group-hover/more:rotate-180 group-focus-within/more:rotate-180"
                />
              </button>
              <.dropdown group="more" class="start-0 w-52">
                <.link
                  :for={category <- @more_categories}
                  navigate={~p"/categories/#{category}"}
                  aria-current={if(@active == category, do: "page")}
                  class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm transition hover:bg-base-200 aria-[current=page]:text-primary"
                >
                  <.icon
                    name={TaamolWeb.NewsComponents.category_icon(category)}
                    class="size-4 text-base-content/50"
                  />
                  {TaamolWeb.NewsComponents.category_name(category)}
                </.link>
              </.dropdown>
            </li>
          </ul>
        </nav>

        <div class="ms-auto flex items-center gap-2 sm:gap-3">
          <.prayer_times />
          <div class="hidden lg:block"><.locale_switcher /></div>
          <.theme_button class="hidden lg:inline-grid" />
          <%= if @current_scope do %>
            <.user_menu current_scope={@current_scope} class="hidden lg:block" />
          <% else %>
            <.link
              href={~p"/users/log-in"}
              class="hidden text-sm font-medium transition-colors hover:text-primary lg:inline"
            >
              {gettext("Log in")}
            </.link>
            <.link
              href={~p"/users/register"}
              class="hidden rounded-full bg-primary px-4 py-2 text-sm font-medium text-primary-content transition hover:opacity-85 lg:inline"
            >
              {gettext("Register")}
            </.link>
          <% end %>
        </div>
      </div>

      <nav
        :if={@category_tabs?}
        id="mobile-category-tabs"
        aria-label={gettext("Categories")}
        class="overflow-x-auto border-t border-base-300/60 px-4 [scrollbar-width:none] sm:px-6 lg:hidden [&::-webkit-scrollbar]:hidden"
      >
        <ul class="flex min-w-max gap-5 text-sm">
          <li>
            <.tab_nav_link to={~p"/"} active={@active == :home}>{gettext("Home")}</.tab_nav_link>
          </li>
          <li :for={category <- @categories}>
            <.tab_nav_link to={~p"/categories/#{category}"} active={@active == category}>
              {TaamolWeb.NewsComponents.category_name(category)}
            </.tab_nav_link>
          </li>
        </ul>
      </nav>
    </header>

    <main class={[
      "pb-24 lg:pb-0",
      if(@wide, do: nil, else: "px-4 pt-10 sm:px-6 sm:pt-16 lg:px-8 lg:pb-20")
    ]}>
      <div class={if(@wide, do: nil, else: "mx-auto max-w-2xl space-y-4")}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <nav
      id="bottom-nav"
      aria-label={gettext("Main")}
      class="fixed inset-x-0 bottom-0 z-40 border-t border-base-300 bg-base-100/95 pb-[env(safe-area-inset-bottom)] backdrop-blur-md lg:hidden"
    >
      <ul class="mx-auto grid max-w-md grid-cols-4">
        <li>
          <.bottom_nav_link to={~p"/"} icon="hero-home" active={@active == :home}>
            {gettext("Home")}
          </.bottom_nav_link>
        </li>
        <li>
          <.bottom_nav_link
            to={~p"/categories"}
            icon="hero-squares-2x2"
            active={@active == :categories or @active in @categories}
          >
            {gettext("Categories")}
          </.bottom_nav_link>
        </li>
        <li>
          <.bottom_nav_link
            to={~p"/calendar"}
            icon="hero-calendar-days"
            active={@active == :calendar}
          >
            {gettext("Calendar")}
          </.bottom_nav_link>
        </li>
        <li>
          <.bottom_nav_link to={~p"/menu"} icon="hero-user-circle" active={@active == :menu}>
            {gettext("Profile")}
          </.bottom_nav_link>
        </li>
      </ul>
    </nav>

    <.flash_group flash={@flash} />
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
      class="-mb-px flex items-center whitespace-nowrap border-b-2 border-transparent transition-colors hover:text-primary aria-[current=page]:border-primary aria-[current=page]:text-primary"
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :to, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp tab_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@to}
      aria-current={if(@active, do: "page")}
      class="inline-block whitespace-nowrap border-b-2 border-transparent py-3 text-base-content/60 transition-colors aria-[current=page]:border-primary aria-[current=page]:font-semibold aria-[current=page]:text-primary"
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :to, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp bottom_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@to}
      aria-current={if(@active, do: "page")}
      class="flex flex-col items-center gap-1 py-2.5 text-[11px] text-base-content/55 transition-colors aria-[current=page]:text-primary"
    >
      <.icon name={if(@active, do: "#{@icon}-solid", else: @icon)} class="size-6" />
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
        class="flex items-center gap-3 rounded-full py-1 pe-2 ps-1 transition hover:bg-base-200"
      >
        <.avatar user={@current_scope.user} />
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
          :if={Taamol.Accounts.allowed?(@current_scope, :view_dashboard)}
          id="dashboard-link"
          navigate={~p"/dashboard"}
          class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm transition hover:bg-base-200"
        >
          <.icon name="hero-chart-bar-square" class="size-4 text-base-content/50" />
          {gettext("Dashboard")}
        </.link>
        <.link
          :if={Taamol.Accounts.admin?(@current_scope)}
          navigate={~p"/admin/access"}
          class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm transition hover:bg-base-200"
        >
          <.icon name="hero-shield-check" class="size-4 text-base-content/50" />
          {gettext("Access")}
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

  attr :class, :string, default: nil

  @doc "One-button light/dark switch (the full system/light/dark toggle is on /menu)."
  def theme_button(assigns) do
    ~H"""
    <span class={["size-9 place-items-center", @class]}>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label={gettext("Dark mode")}
        class="grid size-9 place-items-center rounded-full text-base-content/70 transition hover:bg-base-200 hover:text-base-content [[data-theme=dark]_&]:hidden"
      >
        <.icon name="hero-moon" class="size-5" />
      </button>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label={gettext("Light mode")}
        class="hidden size-9 place-items-center rounded-full text-base-content/70 transition hover:bg-base-200 hover:text-base-content [[data-theme=dark]_&]:grid"
      >
        <.icon name="hero-sun" class="size-5" />
      </button>
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

  @doc """
  Language picker: a pill showing the current language that opens a menu on
  hover/focus. Each option submits the form to `/locale`, so it works on both
  controller and LiveView pages without JavaScript.
  """
  attr :id, :string, default: "locale-switcher"

  def locale_switcher(assigns) do
    current = Gettext.get_locale(TaamolWeb.Gettext)

    languages = [
      %{code: "en", native: "English", name: gettext("English")},
      %{code: "fa", native: "فارسی", name: gettext("Persian")},
      %{code: "sv", native: "Svenska", name: gettext("Swedish")}
    ]

    assigns =
      assigns
      |> assign(:form, to_form(%{}))
      |> assign(:languages, languages)
      |> assign(:current, current)

    ~H"""
    <div class="group/locale relative">
      <button
        type="button"
        id={"#{@id}-trigger"}
        aria-haspopup="true"
        aria-controls={@id}
        class="inline-flex items-center gap-1.5 rounded-full border border-base-300 bg-base-100 px-3 py-1.5 text-xs transition hover:border-primary/40 hover:bg-base-200 focus-visible:outline-2 focus-visible:outline-primary"
      >
        <.icon name="hero-language-micro" class="size-4 text-base-content/60" />
        <span class="font-semibold uppercase tracking-wide">{@current}</span>
        <.icon
          name="hero-chevron-down-micro"
          class="size-3.5 text-base-content/50 transition-transform duration-200 group-hover/locale:rotate-180 group-focus-within/locale:rotate-180"
        />
        <span class="sr-only">{gettext("Language")}</span>
      </button>

      <div class="invisible absolute end-0 top-full z-50 w-52 translate-y-1 pt-2 opacity-0 transition duration-200 ease-out group-hover/locale:visible group-hover/locale:translate-y-0 group-hover/locale:opacity-100 group-focus-within/locale:visible group-focus-within/locale:translate-y-0 group-focus-within/locale:opacity-100">
        <.form
          for={@form}
          action={~p"/locale"}
          method="post"
          id={@id}
          aria-label={gettext("Language")}
          class="rounded-2xl border border-base-300 bg-base-100 p-1 shadow-xl shadow-base-content/10"
        >
          <p class="px-3 pb-1 pt-2 text-[11px] font-medium uppercase tracking-wider text-base-content/50">
            {gettext("Language")}
          </p>
          <button
            :for={lang <- @languages}
            type="submit"
            name="locale"
            value={lang.code}
            id={"#{@id}-option-#{lang.code}"}
            aria-current={if(@current == lang.code, do: "true")}
            class="group/option flex w-full items-center gap-3 rounded-xl px-3 py-2 text-start transition hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-none aria-[current=true]:bg-primary/10"
          >
            <span class="grid size-8 shrink-0 place-items-center rounded-lg bg-base-200 text-[11px] font-bold uppercase tracking-wide text-base-content/70 transition group-hover/option:bg-base-300 group-aria-[current=true]/option:bg-primary group-aria-[current=true]/option:text-primary-content">
              {lang.code}
            </span>
            <span class="min-w-0 flex-1">
              <span lang={lang.code} class="block text-sm font-semibold leading-tight">
                {lang.native}
              </span>
              <span class="block text-xs leading-tight text-base-content/55">{lang.name}</span>
            </span>
            <.icon
              name="hero-check-micro"
              class="size-4 text-primary opacity-0 group-aria-[current=true]/option:opacity-100"
            />
          </button>
        </.form>
      </div>
    </div>
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
          class="inline-flex items-center gap-2 rounded-full border border-base-300 bg-base-100 px-3 py-1.5 text-xs transition hover:border-primary/40 hover:bg-base-200 focus-visible:outline-2 focus-visible:outline-primary"
        >
          <span class="relative grid size-5 place-items-center rounded-full bg-primary/10 text-primary">
            <.icon name="hero-moon-micro" class="size-3.5" />
            <span class="absolute -end-0.5 -top-0.5 hidden size-2 rounded-full bg-primary group-data-[state=ready]/prayer:block group-data-[state=ready]/prayer:motion-safe:animate-pulse" />
          </span>
          <span data-role="next-label" class="text-base-content/70">
            {gettext("Prayer times")}
          </span>
          <span
            data-role="next-time"
            class="font-semibold tabular-nums group-data-[state=loading]/prayer:hidden"
          />
          <span class="hidden h-3 w-10 rounded bg-base-300 motion-safe:animate-pulse group-data-[state=loading]/prayer:inline-block" />
        </button>

        <div
          id={"#{@id}-popover"}
          role="tooltip"
          class="invisible absolute end-0 top-full z-50 w-[18rem] max-w-[calc(100vw-2rem)] translate-y-1 pt-2 opacity-0 transition duration-200 ease-out group-hover/prayer:visible group-hover/prayer:translate-y-0 group-hover/prayer:opacity-100 group-focus-within/prayer:visible group-focus-within/prayer:translate-y-0 group-focus-within/prayer:opacity-100"
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
              <dd data-role="suhoor" class="text-sm font-semibold tabular-nums" />
            </div>
            <div>
              <dt class="text-[10px] opacity-75">{gettext("Iftar")}</dt>
              <dd data-role="iftar" class="text-sm font-semibold tabular-nums" />
            </div>
          </dl>
          <div class="rounded-lg bg-primary-content/15 px-3 py-1.5 text-end">
            <p
              data-role="fast-label"
              data-suhoor={gettext("Until suhoor ends")}
              data-iftar={gettext("Until iftar")}
              class="text-[10px] opacity-80"
            />
            <p data-role="fast-countdown" class="text-base font-semibold tabular-nums" />
          </div>
        </div>
      </section>

      <section class="p-2">
        <div class="flex flex-wrap items-center justify-center gap-1.5 text-[11px] text-base-content/70">
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
              class="text-primary transition-[stroke-dasharray] duration-700"
            />
            <circle
              :for={{key, _label, _icon} <- @prayers}
              data-marker={key}
              r="2.5"
              cx="12"
              cy="104"
              stroke-width="1.5"
              class="fill-base-100 stroke-base-content/30"
            />
          </svg>
          <span
            data-role="sun"
            class="absolute grid size-6 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-base-100 shadow-md ring-1 ring-base-300 transition-[left,top] duration-700"
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
            <p data-role="countdown" class="text-3xl font-semibold tracking-tight tabular-nums">
              --:--:--
            </p>
            <p
              data-role="until"
              data-template={gettext("until %{prayer}", prayer: "%{prayer}")}
              class="text-[11px] text-base-content/60"
            />
            <p data-role="next-at" class="text-xs tabular-nums text-base-content/60" />
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
              class="text-sm font-medium tracking-tight tabular-nums text-base-content group-data-[next]/cell:text-primary"
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

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
