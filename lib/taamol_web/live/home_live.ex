defmodule TaamolWeb.HomeLive do
  @moduledoc """
  The start page: lead story, latest/most read lists and a news feed that can
  be filtered by category (`/?category=world`).
  """
  use TaamolWeb, :live_view

  import TaamolWeb.NewsComponents

  alias Taamol.Tracking

  @feed_size 8

  @impl true
  def mount(_params, _session, socket) do
    lead = Tracking.get_lead_article()

    {:ok,
     socket
     |> assign(page_title: gettext("Home"), lead: lead)
     |> assign(:upcoming, Taamol.Events.upcoming(limit: 5))
     |> assign(:gallery, Taamol.Gallery.list_images(limit: 4))
     |> stream(:latest, Tracking.list_public_articles(limit: 5, exclude: lead && lead.id))
     |> stream(:most_read, Tracking.list_most_read_articles(limit: 5))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(category: category_from_param(params["category"]), page: 0)
     |> load_feed(reset: true)}
  end

  @impl true
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
      <div id="home" class="mx-auto max-w-7xl px-4 pt-5 sm:px-6 lg:px-8 lg:pt-8">
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
                <div role="tablist" class="flex gap-6 border-b border-base-300 text-sm">
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
                    class="-mb-px border-b-2 border-transparent pb-3 text-base-content/60 transition-colors hover:text-base-content aria-selected:border-primary aria-selected:font-semibold aria-selected:text-primary"
                  >
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
                    class="-mb-px border-b-2 border-transparent pb-3 text-base-content/60 transition-colors hover:text-base-content aria-selected:border-primary aria-selected:font-semibold aria-selected:text-primary"
                  >
                    {gettext("Most read")}
                  </button>
                </div>

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
              <h2 id="news-title" class="mb-4 text-xl font-bold tracking-tight">
                {gettext("News")}
              </h2>
              <.category_tabs
                id="news-tabs"
                active={@category}
                all_path={~p"/"}
                path={fn category -> ~p"/?#{[category: category]}" end}
              />

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
end
