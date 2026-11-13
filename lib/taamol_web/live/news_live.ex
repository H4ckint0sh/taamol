defmodule TaamolWeb.NewsLive do
  @moduledoc """
  `/news`: all published news, filtered by category with the chips at the top
  (`/news?category=religion`). This is the only place categories are listed;
  the site navigation just links to News.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.NewsComponents

  alias Taamol.Tracking

  @feed_size 10

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, :upcoming, Taamol.Events.upcoming(limit: 5))}

  @impl true
  def handle_params(params, _uri, socket) do
    category = category_from_param(params["category"])
    lead = Tracking.get_lead_article(category: category)

    {:noreply,
     socket
     |> assign(
       page_title: if(category, do: category_name(category), else: gettext("News")),
       category: category,
       lead: lead,
       page: 0
     )
     |> load_feed(reset: true)}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    {:noreply, socket |> update(:page, &(&1 + 1)) |> load_feed(reset: false)}
  end

  defp load_feed(socket, reset: reset) do
    %{category: category, lead: lead, page: page} = socket.assigns

    articles =
      Tracking.list_public_articles(
        category: category,
        exclude: lead && lead.id,
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
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={:news}>
      <div id="news-page" class="mx-auto max-w-7xl px-4 pt-5 sm:px-6 lg:px-8 lg:pt-8">
        <div class="grid gap-8 xl:grid-cols-[minmax(0,1fr)_18rem]">
          <div class="min-w-0">
            <h1 class="text-2xl font-bold tracking-tight sm:text-3xl">
              {if(@category, do: category_name(@category), else: gettext("News"))}
            </h1>

            <div class="mt-4">
              <.category_tabs
                id="news-categories"
                active={@category}
                all_path={~p"/news"}
                path={fn category -> ~p"/news?#{[category: category]}" end}
              />
            </div>

            <div
              :if={is_nil(@lead)}
              id="news-empty"
              class="mt-6 rounded-2xl border border-dashed border-base-300 p-10 text-center"
            >
              <.icon
                name={if(@category, do: category_icon(@category), else: "hero-newspaper")}
                class="size-10 text-base-content/30"
              />
              <p class="mt-3 text-sm text-base-content/60">
                {gettext("No articles in this category yet.")}
              </p>
            </div>

            <div :if={@lead} class="mt-6">
              <.hero_card id="news-lead" article={@lead} />
            </div>

            <div id="news-feed" phx-update="stream" class="mt-4 grid gap-x-8 md:grid-cols-2">
              <.feed_card
                :for={{id, article} <- @streams.feed}
                id={id}
                article={article}
                class="border-b border-base-300/70"
              />
            </div>

            <div :if={@more?} class="mt-6 text-center">
              <button
                id="news-load-more"
                type="button"
                phx-click="load-more"
                phx-disable-with={gettext("Loading…")}
                class="rounded-xl border border-base-300 px-8 py-2.5 text-sm font-medium transition hover:border-primary/40 hover:bg-base-200"
              >
                {gettext("Show more")}
              </button>
            </div>
          </div>

          <.rail upcoming={@upcoming} />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
