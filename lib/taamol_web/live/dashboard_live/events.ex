defmodule TaamolWeb.DashboardLive.Events do
  @moduledoc """
  `/dashboard/events`: Taamol community events (administrators).
  `?when=past&page=2` switch between upcoming and past events.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.DashboardComponents
  import TaamolWeb.CalendarComponents, only: [kind_name: 1, kind_chip: 1, kind_dot_badge: 1]

  alias Taamol.Events
  alias Taamol.Events.Event

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :ok = Events.subscribe()

    {:ok,
     assign(socket, page_title: gettext("Calendar events"), event_editor: nil, event_focus: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    period = if params["when"] == "past", do: :past, else: :upcoming
    page = page_param(params)

    {:noreply, socket |> assign(period: period, page: page) |> refresh_events()}
  end

  @impl true
  def handle_info(:events_changed, socket), do: {:noreply, refresh_events(socket)}

  def handle_info({:event_editor, action, _event}, socket) when action in [:saved, :deleted] do
    message = if action == :saved, do: gettext("Event saved."), else: gettext("Event deleted.")

    {:noreply,
     socket |> assign(:event_editor, nil) |> refresh_events() |> put_flash(:info, message)}
  end

  def handle_info({:event_editor, :error, message}, socket),
    do: {:noreply, put_flash(socket, :error, message)}

  defp refresh_events(socket) do
    period = socket.assigns.period
    page = socket.assigns.page

    %{entries: events, total: total} =
      Events.list_events_page(when: period, limit: @per_page, offset: (page - 1) * @per_page)

    last_page = max(div(total + @per_page - 1, @per_page), 1)

    if page > last_page do
      push_patch(socket, to: list_path(period, last_page), replace: true)
    else
      socket
      |> assign(total: total)
      |> stream(:events, events, reset: true)
    end
  end

  defp list_path(period, page) do
    query =
      Enum.reject([when: if(period == :past, do: "past"), page: page], fn {_, v} ->
        v in [nil, 1]
      end)

    ~p"/dashboard/events?#{query}"
  end

  @impl true
  def handle_event("new-event", _params, socket) do
    event = %Event{starts_at: NaiveDateTime.new!(Date.utc_today(), ~T[18:00:00])}
    {:noreply, assign(socket, event_editor: event, event_focus: "#new-event")}
  end

  def handle_event("edit-event", %{"id" => id}, socket) do
    case Events.get_event(id) do
      nil -> {:noreply, put_flash(socket, :error, gettext("This event no longer exists."))}
      event -> {:noreply, assign(socket, event_editor: event, event_focus: "#edit-#{event.id}")}
    end
  end

  def handle_event("close-event", _params, socket),
    do: {:noreply, assign(socket, :event_editor, nil)}

  def handle_event("delete", %{"id" => id}, socket) do
    with %Taamol.Events.Event{} = event <- Events.get_event(id),
         {:ok, _event} <- Events.delete_event(socket.assigns.current_scope, event) do
      {:noreply,
       socket
       |> refresh_events()
       |> put_flash(:info, gettext("Event deleted."))}
    else
      _ ->
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
      unread_messages={@unread_messages}
      pending_bookings={@pending_bookings}
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
          <button
            id="new-event"
            type="button"
            phx-click="new-event"
            class="inline-flex items-center gap-1.5 rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-primary-content transition hover:opacity-85"
          >
            <.icon name="hero-plus" class="size-4" />{gettext("Add event")}
          </button>
        </:actions>
      </Layouts.dashboard_heading>

      <.card padded={false}>
        <div class="px-5 py-4">
          <.segmented_control id="event-periods" role="group" aria-label={gettext("Calendar events")}>
            <.link
              :for={
                {period, label, icon} <- [
                  {:upcoming, gettext("Upcoming"), "hero-calendar-days-micro"},
                  {:past, gettext("Past"), "hero-clock-micro"}
                ]
              }
              id={"event-period-#{period}"}
              patch={list_path(period, 1)}
              aria-current={if(@period == period, do: "page")}
              class={segmented_option_class()}
            >
              <.icon name={icon} class="size-4" />
              {label}
            </.link>
          </.segmented_control>
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
                    <button
                      id={"edit-#{event.id}"}
                      type="button"
                      phx-click="edit-event"
                      phx-value-id={event.id}
                      aria-label={gettext("Edit")}
                      class="grid size-8 place-items-center rounded-lg text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                    </button>
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
      <.live_component
        :if={@event_editor}
        module={TaamolWeb.EventEditorComponent}
        id="dashboard-event"
        event={@event_editor}
        current_scope={@current_scope}
        dialog={true}
        focus_return={@event_focus}
      />
    </Layouts.dashboard>
    """
  end
end
