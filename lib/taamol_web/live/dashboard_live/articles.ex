defmodule TaamolWeb.DashboardLive.Articles do
  @moduledoc """
  `/dashboard/news`: all articles (drafts included) for administrators.
  `?search=…&status=draft&category=world&page=2` drive the table.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.DashboardComponents

  import TaamolWeb.NewsComponents,
    only: [category_name: 1, categories: 0, format_count: 1, format_date: 1, cover: 1]

  alias Taamol.Tracking

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @per_page 20
  @statuses ~w(published scheduled draft)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("News"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      "search" => params["search"] || "",
      "status" => if(params["status"] in @statuses, do: params["status"], else: ""),
      "category" =>
        if(TaamolWeb.NewsComponents.category_from_param(params["category"]),
          do: params["category"],
          else: ""
        )
    }

    page = page_param(params)

    opts = [
      search: filters["search"],
      status: status_atom(filters["status"]),
      category: TaamolWeb.NewsComponents.category_from_param(filters["category"]),
      limit: @per_page,
      offset: (page - 1) * @per_page
    ]

    case Tracking.list_articles_page(socket.assigns.current_scope, opts) do
      {:ok, %{entries: articles, total: total}} ->
        {:noreply,
         socket
         |> assign(filters: filters, filter_form: to_form(filters), page: page, total: total)
         |> stream(:articles, articles, reset: true)}

      {:error, :forbidden} ->
        {:noreply, push_navigate(socket, to: ~p"/dashboard")}
    end
  end

  defp status_atom("published"), do: :published
  defp status_atom("scheduled"), do: :scheduled
  defp status_atom("draft"), do: :draft
  defp status_atom(_), do: nil

  defp list_path(filters, page) do
    query =
      filters
      |> Map.put("page", page)
      |> Enum.reject(fn {_k, v} -> v in ["", 1, nil] end)

    ~p"/dashboard/news?#{query}"
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     push_patch(socket, to: list_path(Map.take(params, ["search", "status", "category"]), 1))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, article} <- Tracking.get_article_for_admin(scope, id),
         {:ok, article} <- Tracking.delete_article(scope, article) do
      {:noreply,
       socket
       |> stream_delete(:articles, article)
       |> update(:total, &(&1 - 1))
       |> put_flash(:info, gettext("Article deleted."))}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("The article could not be deleted."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      unread_messages={@unread_messages}
      pending_bookings={@pending_bookings}
      active={:news}
      title={gettext("News")}
    >
      <Layouts.dashboard_heading
        title={gettext("News")}
        subtitle={ngettext("%{count} article", "%{count} articles", @total)}
      >
        <:actions>
          <.link
            id="new-article"
            navigate={~p"/dashboard/news/new"}
            class="inline-flex items-center gap-1.5 rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-primary-content transition hover:opacity-85"
          >
            <.icon name="hero-plus" class="size-4" />{gettext("New article")}
          </.link>
        </:actions>
      </Layouts.dashboard_heading>

      <.card padded={false}>
        <.form
          for={@filter_form}
          id="articles-filter"
          phx-change="filter"
          phx-submit="filter"
          class="flex flex-wrap items-center gap-3 px-5 py-4"
        >
          <.input
            id="articles-search"
            type="search"
            name="search"
            value={@filters["search"]}
            phx-debounce="300"
            placeholder={gettext("Search titles")}
            aria-label={gettext("Search titles")}
            wrapper_class="mb-0 min-w-56 flex-1"
          />
          <.input
            id="articles-status"
            type="select"
            name="status"
            value={@filters["status"]}
            aria-label={gettext("All statuses")}
            options={[
              {gettext("All statuses"), ""}
              | Enum.map([:published, :scheduled, :draft], &{status_name(&1), &1})
            ]}
            wrapper_class="mb-0"
          />
          <.input
            id="articles-category"
            type="select"
            name="category"
            value={@filters["category"]}
            aria-label={gettext("All categories")}
            options={[
              {gettext("All categories"), ""} | Enum.map(categories(), &{category_name(&1), &1})
            ]}
            wrapper_class="mb-0"
          />
        </.form>

        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="border-y border-base-300 bg-base-200/50 text-xs text-base-content/60">
              <tr>
                <th class="px-5 py-2.5 text-start font-medium">{gettext("Article")}</th>
                <th class="hidden px-5 py-2.5 text-start font-medium md:table-cell">
                  {gettext("Category")}
                </th>
                <th class="px-5 py-2.5 text-start font-medium">{gettext("Status")}</th>
                <th class="hidden px-5 py-2.5 text-end font-medium sm:table-cell">
                  {gettext("Views")}
                </th>
                <th class="hidden px-5 py-2.5 text-start font-medium lg:table-cell">
                  {gettext("Updated")}
                </th>
                <th class="px-5 py-2.5 text-end font-medium">{gettext("Actions")}</th>
              </tr>
            </thead>
            <tbody id="articles" phx-update="stream" class="divide-y divide-base-300/70">
              <tr id="articles-empty" class="hidden only:table-row">
                <td colspan="6" class="px-5 py-10 text-center text-base-content/55">
                  {gettext("No articles found.")}
                </td>
              </tr>
              <tr
                :for={{id, article} <- @streams.articles}
                id={id}
                class="transition hover:bg-base-200/40"
              >
                <td class="px-5 py-3">
                  <div class="flex items-center gap-3">
                    <.cover
                      article={article}
                      class="aspect-[4/3] w-14 shrink-0 rounded-lg"
                      sizes="56px"
                    />
                    <div class="min-w-0">
                      <.link
                        navigate={~p"/dashboard/news/#{article.id}/edit"}
                        dir="auto"
                        class="line-clamp-1 font-medium hover:text-primary"
                      >
                        {article.title}
                      </.link>
                      <p dir="auto" class="truncate text-xs text-base-content/55">
                        {article.author || article.creator.name}
                        <span :if={article.featured} class="text-primary">· {gettext("Top story")}</span>
                      </p>
                    </div>
                  </div>
                </td>
                <td class="hidden px-5 py-3 text-base-content/70 md:table-cell">
                  {category_name(article.category)}
                </td>
                <td class="px-5 py-3">
                  <.status_badge status={Tracking.article_status(article)} />
                </td>
                <td class="hidden px-5 py-3 text-end tabular-nums sm:table-cell">
                  {format_count(article.view_count)}
                </td>
                <td class="hidden px-5 py-3 text-base-content/60 lg:table-cell">
                  {format_date(article.updated_at)}
                </td>
                <td class="px-5 py-3">
                  <div class="flex items-center justify-end gap-1">
                    <.link
                      :if={Tracking.article_status(article) == :published}
                      navigate={~p"/articles/#{article.id}"}
                      aria-label={gettext("View")}
                      class="grid size-8 place-items-center rounded-lg text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
                    >
                      <.icon name="hero-eye" class="size-4" />
                    </.link>
                    <.link
                      id={"edit-#{article.id}"}
                      navigate={~p"/dashboard/news/#{article.id}/edit"}
                      aria-label={gettext("Edit")}
                      class="grid size-8 place-items-center rounded-lg text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                    </.link>
                    <button
                      type="button"
                      id={"delete-#{article.id}"}
                      phx-click="delete"
                      phx-value-id={article.id}
                      data-confirm={gettext("Delete this article and its comments?")}
                      aria-label={gettext("Delete")}
                      class="grid size-8 place-items-center rounded-lg text-error/80 transition hover:bg-error/10 hover:text-error"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.pagination
          page={@page}
          per_page={20}
          total={@total}
          path={fn page -> list_path(@filters, page) end}
        />
      </.card>
    </Layouts.dashboard>
    """
  end
end
