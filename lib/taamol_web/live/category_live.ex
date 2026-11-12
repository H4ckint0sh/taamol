defmodule TaamolWeb.CategoryLive do
  @moduledoc """
  `/categories` lists all categories; `/categories/:category` shows a category's lead
  story and its news feed.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.NewsComponents

  alias Taamol.Tracking

  @feed_size 10

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(page_title: gettext("Categories"), category: nil)
    |> assign(:counts, Tracking.count_public_articles_by_category())
  end

  defp apply_action(socket, :show, %{"category" => param}) do
    category =
      category_from_param(param) || raise Ecto.NoResultsError, queryable: Taamol.Tracking.Article

    lead = Tracking.get_lead_article(category: category)

    socket
    |> assign(page_title: category_name(category), category: category, lead: lead, page: 0)
    |> load_feed(reset: true)
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
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={:categories}>
      <div id="categories" class="mx-auto max-w-7xl px-4 pt-6 sm:px-6 lg:px-8 lg:pb-16 lg:pt-10">
        <h1 class="text-2xl font-bold tracking-tight sm:text-3xl">{gettext("Categories")}</h1>
        <p class="mt-1 text-sm text-base-content/60">
          {gettext("Browse the news by topic.")}
        </p>

        <ul class="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <li :for={category <- categories()}>
            <.link
              id={"category-#{category}"}
              navigate={~p"/categories/#{category}"}
              class="group flex items-center gap-4 rounded-2xl border border-base-300 bg-base-100 p-4 transition hover:border-primary/40 hover:shadow-md hover:shadow-base-content/5"
            >
              <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary transition group-hover:bg-primary group-hover:text-primary-content">
                <.icon name={category_icon(category)} class="size-5" />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block font-semibold">{category_name(category)}</span>
                <span class="block text-xs text-base-content/55">
                  {ngettext("%{count} article", "%{count} articles", Map.get(@counts, category, 0))}
                </span>
              </span>
              <.icon
                name="hero-chevron-right"
                class="size-5 text-base-content/30 transition group-hover:translate-x-0.5 group-hover:text-primary rtl:rotate-180"
              />
            </.link>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={@category}>
      <div
        id={"category-page-#{@category}"}
        class="mx-auto max-w-7xl px-4 pt-5 sm:px-6 lg:px-8 lg:pb-16 lg:pt-8"
      >
        <div class="grid gap-8 lg:grid-cols-[12.5rem_minmax(0,1fr)] xl:grid-cols-[12.5rem_minmax(0,1fr)_18rem]">
          <.categories_sidebar active={@category} current_scope={@current_scope} />

          <div class="min-w-0">
            <h1 class="flex items-center gap-3 text-2xl font-bold tracking-tight sm:text-3xl">
              <span class="grid size-10 place-items-center rounded-xl bg-primary/10 text-primary">
                <.icon name={category_icon(@category)} class="size-5" />
              </span>
              {category_name(@category)}
            </h1>

            <div
              :if={is_nil(@lead)}
              id="category-empty"
              class="mt-6 rounded-2xl border border-dashed border-base-300 p-10 text-center"
            >
              <.icon name={category_icon(@category)} class="size-10 text-base-content/30" />
              <p class="mt-3 text-sm text-base-content/60">
                {gettext("No articles in this category yet.")}
              </p>
            </div>

            <div :if={@lead} class="mt-6">
              <.hero_card id="category-lead" article={@lead} />
            </div>

            <div
              id="category-feed"
              phx-update="stream"
              class="mt-4 grid gap-x-8 md:grid-cols-2"
            >
              <.feed_card
                :for={{id, article} <- @streams.feed}
                id={id}
                article={article}
                class="border-b border-base-300/70"
              />
            </div>

            <div :if={@more?} class="mt-6 text-center">
              <button
                id="category-load-more"
                type="button"
                phx-click="load-more"
                phx-disable-with={gettext("Loading…")}
                class="rounded-xl border border-base-300 px-8 py-2.5 text-sm font-medium transition hover:border-primary/40 hover:bg-base-200"
              >
                {gettext("Show more")}
              </button>
            </div>
          </div>

          <.rail />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
