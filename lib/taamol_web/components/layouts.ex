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
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :wide, :boolean, default: false

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="relative z-10 border-b border-base-300/70 bg-base-100">
      <nav class="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4 px-4 py-4 sm:px-6 lg:px-8">
        <.link href={~p"/"} class="inline-flex items-center gap-3 font-semibold tracking-tight">
          <span class="grid size-9 place-items-center rounded-xl bg-primary text-lg font-bold text-primary-content">T</span>
          <span class="text-lg">Taamol</span>
        </.link>
        <ul class="flex flex-wrap items-center gap-x-4 gap-y-3 text-sm font-medium sm:gap-x-6">
          <li>
            <.prayer_times />
          </li>
          <li>
            <.locale_switcher />
          </li>
          <li>
            <.theme_toggle />
          </li>
          <%= if @current_scope do %>
            <li class="hidden text-base-content/60 sm:block">
              {@current_scope.user.name}
            </li>
            <li :if={Taamol.Accounts.allowed?(@current_scope, :view_dashboard)}>
              <.link
                id="dashboard-link"
                href={~p"/dashboard"}
                class="hover:text-primary transition-colors"
              >
                {gettext("Dashboard")}
              </.link>
            </li>
            <li :if={Taamol.Accounts.admin?(@current_scope)}>
              <.link href={~p"/admin/access"} class="hover:text-primary transition-colors">{gettext(
                "Access"
              )}</.link>
            </li>
            <li>
              <.link href={~p"/users/settings"} class="hover:text-primary transition-colors">{gettext(
                "Settings"
              )}</.link>
            </li>
            <li>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="hover:text-primary transition-colors"
              >{gettext("Log out")}</.link>
            </li>
          <% else %>
            <li>
              <.link href={~p"/users/log-in"} class="hover:text-primary transition-colors">{gettext(
                "Log in"
              )}</.link>
            </li>
            <li>
              <.link
                href={~p"/users/register"}
                class="rounded-full bg-primary px-4 py-2 text-primary-content transition hover:opacity-85"
              >{gettext("Register")}</.link>
            </li>
          <% end %>
        </ul>
      </nav>
    </header>

    <main class={if(@wide, do: nil, else: "px-4 py-20 sm:px-6 lg:px-8")}>
      <div class={if(@wide, do: nil, else: "mx-auto max-w-2xl space-y-4")}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
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
        id="locale-switcher-trigger"
        aria-haspopup="true"
        aria-controls="locale-switcher"
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
          id="locale-switcher"
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
            id={"locale-option-#{lang.code}"}
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
    <prayer-times id="prayer-times" phx-update="ignore" class="block">
      <div data-role="root" data-state="loading" class="group/prayer relative">
        <button
          type="button"
          id="prayer-times-trigger"
          data-role="trigger"
          aria-describedby="prayer-times-popover"
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
          id="prayer-times-popover"
          role="tooltip"
          class="invisible absolute end-0 top-full z-50 w-[18rem] max-w-[calc(100vw-2rem)] translate-y-1 pt-2 opacity-0 transition duration-200 ease-out group-hover/prayer:visible group-hover/prayer:translate-y-0 group-hover/prayer:opacity-100 group-focus-within/prayer:visible group-focus-within/prayer:translate-y-0 group-focus-within/prayer:opacity-100"
        >
          <div class="space-y-1 rounded-2xl border border-base-300 bg-base-100 p-1 text-base-content shadow-xl shadow-base-content/10">
            <%!-- Ramadan banner, shown only during Ramadan --%>
            <section
              id="prayer-times-ramadan"
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
                id="prayer-times-grid"
                class="mt-3 grid grid-cols-3 gap-1 group-data-[state=denied]/prayer:hidden group-data-[state=error]/prayer:hidden"
              >
                <li
                  :for={{key, label, icon} <- @prayers}
                  id={"prayer-time-#{key}"}
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
                {gettext(
                  "Allow location access in your browser to see prayer times for where you are."
                )}
              </p>
              <p class="mt-3 hidden rounded-xl bg-base-200 px-3 py-2 text-center text-xs text-base-content/70 group-data-[state=error]/prayer:block">
                {gettext("Prayer times could not be loaded. Click to try again.")}
              </p>
            </section>
          </div>
        </div>
      </div>
    </prayer-times>
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
