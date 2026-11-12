defmodule TaamolWeb.DashboardLive.Events do
  @moduledoc """
  `/dashboard/events`: Taamol community events (administrators).
  `?when=past&page=2` switch between upcoming and past events.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.DashboardComponents
  import TaamolWeb.CalendarComponents, only: [kind_name: 1, kind_chip: 1, kind_dot_badge: 1]

  alias Taamol.Events

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Calendar events"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    period = if params["when"] == "past", do: :past, else: :upcoming
    page = page_param(params)

    %{entries: events, total: total} =
      Events.list_events_page(when: period, limit: @per_page, offset: (page - 1) * @per_page)

    {:noreply,
     socket
     |> assign(period: period, page: page, total: total)
     |> stream(:events, events, reset: true)}
  end

  defp list_path(period, page) do
    query =
      Enum.reject([when: if(period == :past, do: "past"), page: page], fn {_, v} ->
        v in [nil, 1]
      end)

    ~p"/dashboard/events?#{query}"
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    event = Events.get_event!(id)

    case Events.delete_event(socket.assigns.current_scope, event) do
      {:ok, event} ->
        {:noreply,
         socket
         |> stream_delete(:events, event)
         |> update(:total, &(&1 - 1))
         |> put_flash(:info, gettext("Event deleted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("The event could not be deleted."))}
    end
  end

  defp when_text(event) do
    date = TaamolWeb.NewsComponents.format_date(DateTime.from_naive!(event.starts_at, "Etc/UTC"))

    case TaamolWeb.CalendarComponents.entry_time(%{
           all_day: event.all_day,
           starts_at: event.starts_at,
           ends_at: event.ends_at
         }) do
      nil -> date
      time -> "#{date}, #{time}"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      active={:events}
      title={gettext("Calendar events")}
    >
      <Layouts.dashboard_heading
        title={gettext("Calendar events")}
        subtitle={gettext("Holidays are added automatically. Add Taamol community events here.")}
      >
        <:actions>
          <.link
            navigate={~p"/calendar"}
            class="rounded-xl border border-base-300 bg-base-100 px-4 py-2 text-sm font-medium transition hover:bg-base-200"
          >
            {gettext("Open calendar")}
          </.link>
          <.link
            id="new-event"
            navigate={~p"/dashboard/events/new"}
            class="inline-flex items-center gap-1.5 rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-primary-content transition hover:opacity-85"
          >
            <.icon name="hero-plus" class="size-4" />{gettext("Add event")}
          </.link>
        </:actions>
      </Layouts.dashboard_heading>

      <.card padded={false}>
        <div class="flex gap-6 px-5 pt-4 text-sm">
          <.link
            :for={{period, label} <- [upcoming: gettext("Upcoming"), past: gettext("Past")]}
            patch={list_path(period, 1)}
            aria-current={if(@period == period, do: "page")}
            class="-mb-px border-b-2 border-transparent pb-3 text-base-content/60 transition-colors hover:text-base-content aria-[current=page]:border-primary aria-[current=page]:font-semibold aria-[current=page]:text-primary"
          >
            {label}
          </.link>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="border-y border-base-300 bg-base-200/50 text-xs text-base-content/60">
              <tr>
                <th class="px-5 py-2.5 text-start font-medium">{gettext("Event")}</th>
                <th class="px-5 py-2.5 text-start font-medium">{gettext("When")}</th>
                <th class="hidden px-5 py-2.5 text-start font-medium md:table-cell">
                  {gettext("Type")}
                </th>
                <th class="px-5 py-2.5 text-end font-medium">{gettext("Actions")}</th>
              </tr>
            </thead>
            <tbody id="events" phx-update="stream" class="divide-y divide-base-300/70">
              <tr id="events-empty" class="hidden only:table-row">
                <td colspan="4" class="px-5 py-10 text-center text-base-content/55">
                  {gettext("No events.")}
                </td>
              </tr>
              <tr
                :for={{id, event} <- @streams.events}
                id={id}
                class="transition hover:bg-base-200/40"
              >
                <td class="px-5 py-3">
                  <p dir="auto" class="font-medium">{event.title}</p>
                  <p :if={event.location} dir="auto" class="text-xs text-base-content/55">
                    {event.location}
                  </p>
                </td>
                <td class="whitespace-nowrap px-5 py-3 text-base-content/70">{when_text(event)}</td>
                <td class="hidden px-5 py-3 md:table-cell">
                  <span class={[
                    "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium",
                    kind_chip(event.kind)
                  ]}>
                    <.kind_dot_badge kind={event.kind} class="size-1.5" />{kind_name(event.kind)}
                  </span>
                </td>
                <td class="px-5 py-3">
                  <div class="flex items-center justify-end gap-1">
                    <.link
                      id={"edit-#{event.id}"}
                      navigate={~p"/dashboard/events/#{event.id}/edit"}
                      aria-label={gettext("Edit")}
                      class="grid size-8 place-items-center rounded-lg text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                    </.link>
                    <button
                      type="button"
                      id={"delete-#{event.id}"}
                      phx-click="delete"
                      phx-value-id={event.id}
                      data-confirm={gettext("Delete this event?")}
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
          path={fn page -> list_path(@period, page) end}
        />
      </.card>
    </Layouts.dashboard>
    """
  end
end
