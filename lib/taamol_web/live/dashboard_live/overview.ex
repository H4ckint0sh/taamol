defmodule TaamolWeb.DashboardLive.Overview do
  @moduledoc """
  `/dashboard`: every logged-in user sees their own activity and upcoming
  events; administrators with dashboard access also see site statistics.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.DashboardComponents
  import TaamolWeb.NewsComponents, only: [category_name: 1, format_count: 1, month_short: 1]

  alias Taamol.{Accounts, Events, Tracking}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      :ok = Events.subscribe()

      if Accounts.can?(scope, :view_statistics) do
        Accounts.subscribe_users(scope)
      end
    end

    socket =
      socket
      |> assign(page_title: gettext("Dashboard"))
      |> assign(activity: Tracking.user_activity(scope))
      |> assign(upcoming: Events.upcoming(limit: 5))
      |> assign(can_manage_news?: Accounts.can?(scope, :manage_news))

    socket =
      with {:ok, users} <- Accounts.user_statistics(scope),
           {:ok, articles} <- Tracking.article_statistics(scope) do
        assign(socket,
          stats?: true,
          users: users,
          articles: articles,
          upcoming_30: length(Events.upcoming(limit: 1000, days: 30))
        )
      else
        {:error, :forbidden} -> assign(socket, stats?: false)
      end

    {:ok, socket}
  end

  @impl true
  def handle_info(:events_changed, socket) do
    socket = assign(socket, :upcoming, Events.upcoming(limit: 5))

    socket =
      if socket.assigns.stats?,
        do: assign(socket, :upcoming_30, length(Events.upcoming(limit: 1000, days: 30))),
        else: socket

    {:noreply, socket}
  end

  def handle_info(:users_changed, socket) do
    case Accounts.user_statistics(socket.assigns.current_scope) do
      {:ok, users} -> {:noreply, assign(socket, :users, users)}
      {:error, :forbidden} -> {:noreply, assign(socket, :stats?, false)}
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
      active={:overview}
      title={gettext("Overview")}
    >
      <Layouts.dashboard_heading
        title={gettext("Welcome, %{name}", name: @current_scope.user.name)}
        subtitle={gettext("Here is what is happening in the community.")}
      />

      <div :if={@stats?} id="statistics" class="space-y-6">
        <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_tile
            id="stat-users"
            icon="hero-users"
            value={format_count(@users.total)}
            label={gettext("Users")}
            note={gettext("+%{count} this week", count: @users.new_this_week)}
          />
          <.stat_tile
            id="stat-articles"
            icon="hero-newspaper"
            value={format_count(@articles.published)}
            label={gettext("Published articles")}
            note={gettext("%{count} drafts", count: @articles.drafts)}
          />
          <.stat_tile
            id="stat-views"
            icon="hero-eye"
            value={format_count(@articles.views)}
            label={gettext("Article views")}
            note={gettext("%{count} new articles this week", count: @articles.published_this_week)}
          />
          <.stat_tile
            id="stat-events"
            icon="hero-calendar-days"
            value={@upcoming_30}
            label={gettext("Coming up")}
            note={gettext("Holidays and events in the next 30 days")}
          />
        </div>

        <div class="grid gap-6 lg:grid-cols-2">
          <.card id="chart-signups" title={gettext("New accounts per week")}>
            <.column_chart
              id="signups-chart"
              value_label={gettext("new accounts")}
              points={
                for week <- @users.per_week,
                    do: %{
                      label: "#{week.week_start.day} #{month_short(week.week_start.month)}",
                      value: week.count
                    }
              }
            />
          </.card>
          <.card id="chart-views" title={gettext("Views by category")}>
            <p :if={@articles.views_by_category == []} class="text-sm text-base-content/55">
              {gettext("No published articles yet.")}
            </p>
            <.bar_list
              id="views-chart"
              format={&format_count/1}
              rows={
                for {category, views} <- @articles.views_by_category,
                    do: %{label: category_name(category), value: views}
              }
            />
          </.card>
        </div>

        <.card id="top-articles" title={gettext("Most read articles")} padded={false}>
          <:actions>
            <.link
              :if={@can_manage_news?}
              navigate={~p"/dashboard/news"}
              class="text-sm font-medium text-primary hover:underline"
            >
              {gettext("All news")}
            </.link>
          </:actions>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="border-y border-base-300 bg-base-200/50 text-xs text-base-content/60">
                <tr>
                  <th class="px-5 py-2.5 text-start font-medium">{gettext("Title")}</th>
                  <th class="px-5 py-2.5 text-start font-medium">{gettext("Category")}</th>
                  <th class="px-5 py-2.5 text-end font-medium">{gettext("Views")}</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-300/70">
                <tr :for={article <- @articles.top} id={"top-#{article.id}"}>
                  <td class="max-w-sm px-5 py-3">
                    <.link
                      navigate={~p"/articles/#{article.id}"}
                      dir="auto"
                      class="line-clamp-1 font-medium hover:text-primary"
                    >
                      {article.title}
                    </.link>
                  </td>
                  <td class="px-5 py-3 text-base-content/70">{category_name(article.category)}</td>
                  <td class="px-5 py-3 text-end tabular-nums">{format_count(article.view_count)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </.card>
      </div>

      <div class={["grid gap-6 lg:grid-cols-3", @stats? && "mt-6"]}>
        <.card id="my-activity" title={gettext("Your activity")}>
          <dl class="grid grid-cols-2 gap-3">
            <div class="rounded-xl bg-base-200/60 p-4">
              <dt class="text-xs text-base-content/60">{gettext("Liked articles")}</dt>
              <dd class="mt-1 text-2xl font-bold tabular-nums">{@activity.likes}</dd>
            </div>
            <div class="rounded-xl bg-base-200/60 p-4">
              <dt class="text-xs text-base-content/60">{gettext("Comments")}</dt>
              <dd class="mt-1 text-2xl font-bold tabular-nums">{@activity.comments}</dd>
            </div>
          </dl>
          <.link
            navigate={~p"/users/settings"}
            class="mt-4 inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline"
          >
            <.icon name="hero-user-circle" class="size-4" />{gettext("Account settings")}
          </.link>
        </.card>

        <TaamolWeb.CalendarComponents.upcoming_card
          id="dashboard-upcoming"
          entries={@upcoming}
          class="lg:col-span-2"
        />
      </div>
    </Layouts.dashboard>
    """
  end
end
