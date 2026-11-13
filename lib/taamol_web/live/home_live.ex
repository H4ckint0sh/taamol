defmodule TaamolWeb.HomeLive do
  @moduledoc """
  The start page: lead story, latest/most read lists and a news feed that can
  be filtered by category (`/?category=world`); the full, filterable list is
  the News page (`/news`).
  """
  use TaamolWeb, :live_view

  import TaamolWeb.NewsComponents

  alias Taamol.Tracking

  @feed_size 8

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :ok = Taamol.Events.subscribe()
    lead = Tracking.get_lead_article()

    {:ok,
     socket
     |> assign(page_title: gettext("Home"), lead: lead)
     |> assign(:upcoming, Taamol.Events.upcoming(limit: 5))
     |> assign(:gallery, Taamol.Gallery.list_images(limit: 4))
     |> assign(:highlights, highlights())
     |> assign(:highlight, 0)
     |> assign(:donations?, not is_nil(Taamol.Settings.swish()))
     |> stream(:latest, Tracking.list_public_articles(limit: 5, exclude: lead && lead.id))
     |> stream(:most_read, Tracking.list_most_read_articles(limit: 5))}
  end

  @impl true
  def handle_info(:events_changed, socket),
    do: {:noreply, assign(socket, :upcoming, Taamol.Events.upcoming(limit: 5))}

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(category: category_from_param(params["category"]), page: 0)
     |> load_feed(reset: true)}
  end

  # recent stories with a picture, shown in the hero card
  defp highlights do
    [limit: 12]
    |> Tracking.list_public_articles()
    |> Enum.filter(& &1.cover_image_url)
    |> Enum.take(4)
  end

  @impl true
  def handle_event("highlight", %{"step" => step}, socket) do
    count = max(length(socket.assigns.highlights), 1)
    step = if step == "next", do: 1, else: -1
    {:noreply, update(socket, :highlight, &Integer.mod(&1 + step, count))}
  end

  def handle_event("load-more", _params, socket) do
    {:noreply, socket |> update(:page, &(&1 + 1)) |> load_feed(reset: false)}
  end

  defp load_feed(socket, reset: reset) do
    %{category: category, page: page} = socket.assigns

    articles =
      Tracking.list_public_articles(
        category: category,
        limit: @feed_size + 1,
        offset: page * @feed_size
      )

    socket
    |> assign(more?: length(articles) > @feed_size)
    |> stream(:feed, Enum.take(articles, @feed_size), reset: reset)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={:home}>
      <.landing_hero
        image={hero_image(@gallery, @lead)}
        highlights={@highlights}
        highlight={@highlight}
        donations?={@donations?}
      />
      <div id="home" class="mx-auto max-w-7xl px-4 pt-8 sm:px-6 lg:px-8 lg:pt-12">
        <div class="grid gap-8 xl:grid-cols-[minmax(0,1fr)_18rem]">
          <div class="min-w-0 space-y-10">
            <div
              :if={is_nil(@lead)}
              id="home-empty"
              class="rounded-2xl border border-dashed border-base-300 p-10 text-center"
            >
              <.icon name="hero-newspaper" class="size-10 text-base-content/30" />
              <p class="mt-3 font-semibold">{gettext("No news yet")}</p>
              <p class="mt-1 text-sm text-base-content/60">
                {gettext("Published articles will appear here.")}
              </p>
            </div>

            <section
              :if={@lead}
              class="grid gap-6 md:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)]"
            >
              <.hero_card id="lead-article" article={@lead} />

              <div>
                <.segmented_control id="home-news-tabs" role="tablist" class="mb-2">
                  <button
                    id="tab-latest"
                    type="button"
                    role="tab"
                    aria-selected="true"
                    aria-controls="latest"
                    phx-click={
                      JS.set_attribute({"aria-selected", "true"})
                      |> JS.set_attribute({"aria-selected", "false"}, to: "#tab-most-read")
                      |> JS.show(to: "#latest")
                      |> JS.hide(to: "#most-read")
                    }
                    class={segmented_option_class()}
                  >
                    <.icon name="hero-newspaper-micro" class="size-4" />
                    {gettext("Latest news")}
                  </button>
                  <button
                    id="tab-most-read"
                    type="button"
                    role="tab"
                    aria-selected="false"
                    aria-controls="most-read"
                    phx-click={
                      JS.set_attribute({"aria-selected", "true"})
                      |> JS.set_attribute({"aria-selected", "false"}, to: "#tab-latest")
                      |> JS.show(to: "#most-read")
                      |> JS.hide(to: "#latest")
                    }
                    class={segmented_option_class()}
                  >
                    <.icon name="hero-chart-bar-micro" class="size-4" />
                    {gettext("Most read")}
                  </button>
                </.segmented_control>

                <div
                  id="latest"
                  role="tabpanel"
                  phx-update="stream"
                  class="divide-y divide-base-300/70"
                >
                  <p id="latest-empty" class="hidden py-6 text-sm text-base-content/55 only:block">
                    {gettext("No other articles yet.")}
                  </p>
                  <.compact_card
                    :for={{id, article} <- @streams.latest}
                    id={id}
                    article={article}
                  />
                </div>
                <div
                  id="most-read"
                  role="tabpanel"
                  phx-update="stream"
                  class="hidden divide-y divide-base-300/70"
                >
                  <.compact_card
                    :for={{id, article} <- @streams.most_read}
                    id={id}
                    article={article}
                    show_views
                  />
                </div>
              </div>
            </section>

            <TaamolWeb.CalendarComponents.upcoming_card
              id="home-upcoming"
              entries={Enum.take(@upcoming, 3)}
              class="xl:hidden"
            />

            <section :if={@lead} id="news" aria-labelledby="news-title">
              <div class="mb-2 flex items-center justify-between gap-3">
                <h2 id="news-title" class="text-xl font-bold tracking-tight">
                  {gettext("News")}
                </h2>
                <.link
                  id="all-news"
                  navigate={~p"/news"}
                  class="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
                >
                  {gettext("All news")}
                  <.icon name="hero-arrow-right-micro" class="size-4 rtl:rotate-180" />
                </.link>
              </div>

              <div id="feed" phx-update="stream" class="grid gap-x-8 md:grid-cols-2">
                <p
                  id="feed-empty"
                  class="hidden py-10 text-center text-sm text-base-content/55 only:block md:col-span-2"
                >
                  {gettext("No articles in this category yet.")}
                </p>
                <.feed_card
                  :for={{id, article} <- @streams.feed}
                  id={id}
                  article={article}
                  class="border-b border-base-300/70"
                />
              </div>

              <div :if={@more?} class="mt-6 text-center">
                <button
                  id="load-more"
                  type="button"
                  phx-click="load-more"
                  phx-disable-with={gettext("Loading…")}
                  class="rounded-xl border border-base-300 px-8 py-2.5 text-sm font-medium transition hover:border-primary/40 hover:bg-base-200"
                >
                  {gettext("Show more")}
                </button>
              </div>
            </section>

            <section :if={@gallery != []} id="home-gallery" aria-labelledby="home-gallery-title">
              <div class="mb-4 flex items-center justify-between gap-3">
                <h2 id="home-gallery-title" class="text-xl font-bold tracking-tight">
                  {gettext("From the gallery")}
                </h2>
                <.link
                  navigate={~p"/gallery"}
                  class="text-sm font-medium text-primary hover:underline"
                >
                  {gettext("View all")}
                </.link>
              </div>
              <div class="grid grid-cols-2 gap-3 sm:grid-cols-4 sm:gap-4">
                <.link
                  :for={image <- @gallery}
                  id={"home-gallery-#{image.id}"}
                  navigate={~p"/gallery?#{[photo: image.id]}"}
                  class="group overflow-hidden rounded-lg bg-base-200"
                >
                  <img
                    src={image.image_url}
                    alt={image.caption || ""}
                    loading="lazy"
                    class="aspect-[11/10] w-full object-cover transition duration-500 group-hover:scale-[1.04]"
                  />
                </.link>
              </div>
            </section>
          </div>

          <.rail upcoming={@upcoming} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp hero_image([%{image_url: url} | _], _lead), do: url
  defp hero_image(_gallery, %{cover_image_url: url}) when is_binary(url), do: url
  defp hero_image(_gallery, _lead), do: nil

  attr :image, :string, default: nil
  attr :highlights, :list, required: true
  attr :highlight, :integer, required: true
  attr :donations?, :boolean, default: false

  defp landing_hero(assigns) do
    assigns = assign(assigns, :current, Enum.at(assigns.highlights, assigns.highlight))

    ~H"""
    <section id="landing-hero" class="relative isolate overflow-hidden bg-zinc-950 text-white">
      <img
        :if={@image}
        src={@image}
        alt=""
        fetchpriority="high"
        class="absolute inset-0 -z-20 size-full object-cover motion-safe:animate-[hero-zoom_18s_ease-out_both]"
      />
      <%!-- darken the text side and the bottom so the copy always reads --%>
      <div
        aria-hidden="true"
        class="absolute inset-0 -z-10 from-black/90 via-black/60 to-black/10 ltr:bg-gradient-to-r rtl:bg-gradient-to-l"
      />
      <div
        aria-hidden="true"
        class="absolute inset-x-0 bottom-0 -z-10 h-1/3 bg-gradient-to-t from-black/70 to-transparent"
      />

      <div class="mx-auto grid min-h-[32rem] max-w-7xl items-end gap-10 px-4 py-14 sm:px-6 lg:min-h-[38rem] lg:grid-cols-[minmax(0,1fr)_22rem] lg:px-8 lg:py-20">
        <div class="max-w-2xl self-center">
          <p class="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-xs font-semibold tracking-wide text-white/85 ring-1 ring-white/15 backdrop-blur-sm">
            <span class="size-1.5 rounded-full bg-primary" />
            {gettext("Taamol · Shia community in Sweden")}
          </p>
          <h1 class="mt-5 text-4xl font-extrabold leading-[1.2] sm:text-5xl lg:text-6xl">
            {gettext("A community rooted in")}
            <span class="relative inline-block whitespace-nowrap text-primary">
              {gettext("faith and compassion")}
              <svg
                aria-hidden="true"
                viewBox="0 0 200 12"
                preserveAspectRatio="none"
                class="absolute inset-x-0 -bottom-2 h-2.5 w-full text-primary"
              >
                <path
                  d="M2 9 C 50 2, 150 2, 198 8"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="3"
                  stroke-linecap="round"
                />
              </svg>
            </span>
          </h1>
          <p class="mt-6 max-w-xl text-base leading-relaxed text-white/75 sm:text-lg">
            {gettext(
              "News, gatherings, prayer times and the Shia calendar: everything that brings our community together, in one place."
            )}
          </p>
          <div class="mt-8 flex flex-wrap items-center gap-3">
            <.link
              :if={@donations?}
              navigate={~p"/donate"}
              id="hero-donate"
              class="inline-flex h-12 items-center gap-2 rounded-xl bg-primary px-6 text-sm font-bold text-primary-content shadow-lg shadow-primary/30 transition hover:-translate-y-0.5 hover:shadow-xl active:scale-95"
            >
              {gettext("Donate")}
              <.icon name="hero-arrow-up-right-micro" class="size-4 rtl:-scale-x-100" />
            </.link>
            <.link
              navigate={~p"/calendar"}
              id="hero-calendar"
              class="group inline-flex h-12 items-center gap-2.5 rounded-xl px-4 text-sm font-semibold text-white transition hover:bg-white/10"
            >
              <span class="grid size-7 place-items-center rounded-full bg-primary text-primary-content transition group-hover:scale-110">
                <.icon name="hero-calendar-days-micro" class="size-4" />
              </span>
              {gettext("See what's coming up")}
            </.link>
          </div>
        </div>

        <div
          :if={@current}
          id="hero-highlight"
          class="hidden rounded-2xl bg-base-100 p-2 text-base-content shadow-2xl shadow-black/40 lg:block"
        >
          <.link navigate={~p"/articles/#{@current.id}"} class="group block">
            <div class="overflow-hidden rounded-xl">
              <img
                src={@current.cover_image_url}
                alt=""
                class="aspect-[16/10] w-full object-cover transition duration-500 group-hover:scale-105"
              />
            </div>
          </.link>
          <div class="px-3 pb-3 pt-3">
            <div class="flex items-center gap-2">
              <button
                type="button"
                id="hero-prev"
                phx-click="highlight"
                phx-value-step="prev"
                aria-label={gettext("Previous")}
                class="grid size-8 shrink-0 place-items-center rounded-full text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
              >
                <.icon name="hero-chevron-left-mini" class="size-5 rtl:rotate-180" />
              </button>
              <.link
                navigate={~p"/articles/#{@current.id}"}
                dir="auto"
                class="line-clamp-2 min-w-0 flex-1 text-center text-[15px] font-bold leading-snug transition-colors hover:text-primary"
              >
                {@current.title}
              </.link>
              <button
                type="button"
                id="hero-next"
                phx-click="highlight"
                phx-value-step="next"
                aria-label={gettext("Next")}
                class="grid size-8 shrink-0 place-items-center rounded-full text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
              >
                <.icon name="hero-chevron-right-mini" class="size-5 rtl:rotate-180" />
              </button>
            </div>
            <p
              :if={@current.summary}
              dir="auto"
              class="mt-1.5 line-clamp-2 text-center text-xs leading-relaxed text-base-content/60"
            >
              {@current.summary}
            </p>
            <div class="mt-3 flex justify-center gap-1.5">
              <span
                :for={i <- 0..(length(@highlights) - 1)//1}
                class={[
                  "h-1.5 rounded-full transition-all duration-300",
                  if(i == @highlight, do: "w-5 bg-primary", else: "w-1.5 bg-base-300")
                ]}
              />
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
