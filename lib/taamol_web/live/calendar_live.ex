defmodule TaamolWeb.CalendarLive do
  @moduledoc """
  The calendar, in two modes:

    * **Calendar** (default): Shia holidays, historical days, Taamol events and
      confirmed bookings (shown without personal details).
    * **Book**: select a day to choose a service and time in a booking dialog.
      An administrator accepts the request, offers another time or declines it.

  `?month=2026-11` picks the month and `?date=2026-11-13` the selected day.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.CalendarComponents

  import TaamolWeb.BookingComponents,
    only: [service_name: 1, service_description: 1, time_range: 2]

  import TaamolWeb.NewsComponents, only: [month_name: 1]

  alias Taamol.{Bookings, Events}
  alias Taamol.Events.Event

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :ok = Events.subscribe()
      :ok = Bookings.subscribe_availability()
    end

    {:ok,
     socket
     |> attach_hook(:calendar_event_updates, :handle_info, &handle_calendar_info/2)
     |> assign(
       page_title: gettext("Calendar"),
       admin?: Taamol.Accounts.admin?(socket.assigns.current_scope),
       today: Date.utc_today(),
       services: Bookings.list_services(),
       event_editor: nil,
       event_focus: nil,
       requested: nil
     )}
  end

  defp handle_calendar_info(:events_changed, %{assigns: %{mode: :events}} = socket) do
    month = socket.assigns.month
    {grid_start, grid_end} = grid_range(month)
    {:halt, assign_events(socket, grid_start, grid_end, month, Date.end_of_month(month))}
  end

  defp handle_calendar_info(:events_changed, socket), do: {:halt, socket}

  defp handle_calendar_info(:booking_availability_changed, socket) do
    socket =
      socket
      |> assign(:services, Bookings.list_services())
      |> assign_availability()
      |> refresh_booking_selection()

    socket =
      if socket.assigns.mode == :events do
        {grid_start, grid_end} = grid_range(socket.assigns.month)

        assign_events(
          socket,
          grid_start,
          grid_end,
          socket.assigns.month,
          Date.end_of_month(socket.assigns.month)
        )
      else
        socket
      end

    {:halt, socket}
  end

  defp handle_calendar_info({:event_editor, action, event}, socket)
       when action in [:saved, :deleted] do
    date =
      if action == :saved,
        do: NaiveDateTime.to_date(event.starts_at),
        else: socket.assigns.selected

    message = if action == :saved, do: gettext("Event saved."), else: gettext("Event deleted.")

    {:halt,
     socket
     |> assign(:event_editor, nil)
     |> put_flash(:info, message)
     |> push_patch(to: cal_path(:events, nil, date, date))}
  end

  defp handle_calendar_info({:event_editor, :error, message}, socket),
    do: {:halt, put_flash(socket, :error, message)}

  defp handle_calendar_info(_message, socket), do: {:cont, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    today = socket.assigns.today
    selected = parse_date(params["date"])
    month = parse_month(params["month"]) || first_of_month(selected || today)

    selected =
      cond do
        selected && same_month?(selected, month) -> selected
        same_month?(today, month) -> today
        true -> month
      end

    mode = if params["mode"] == "book", do: :book, else: :events
    {grid_start, grid_end} = grid_range(month)
    last_of_month = Date.end_of_month(month)

    socket =
      socket
      |> assign(
        mode: mode,
        month: month,
        selected: selected,
        booking_open?: mode == :book and (params["open"] == "1" or is_binary(params["slot"])),
        requested: nil,
        booking_error: nil,
        event_editor: nil,
        weeks: grid_start |> Date.range(grid_end) |> Enum.chunk_every(7),
        hijri_span: hijri_span(month, last_of_month)
      )
      |> assign_availability()

    socket =
      case mode do
        :events -> assign_events(socket, grid_start, grid_end, month, last_of_month)
        :book -> assign_booking(socket, params)
      end

    {:noreply, socket}
  end

  defp assign_events(socket, grid_start, grid_end, month, last_of_month) do
    bookings = Bookings.confirmed_between(grid_start, grid_end) |> Enum.map(&booking_entry/1)

    by_day =
      Enum.reduce(bookings, Events.entries_by_day(grid_start, grid_end), fn entry, acc ->
        Map.update(acc, entry.first_day, [entry], &(&1 ++ [entry]))
      end)

    month_entries =
      (Events.entries_between(month, last_of_month) ++
         Enum.filter(bookings, &same_month?(&1.first_day, month)))
      |> Enum.filter(&(Date.compare(&1.last_day, month) != :lt))
      |> Enum.sort_by(
        &{Date.to_gregorian_days(&1.first_day), if(&1.source == :booking, do: 1, else: 0)}
      )

    assign(socket,
      service: nil,
      slots: [],
      slot: nil,
      by_day: by_day,
      month_entries: month_entries,
      selected_entries: Map.get(by_day, socket.assigns.selected, [])
    )
  end

  defp assign_booking(socket, params) do
    services = socket.assigns.services

    service =
      Enum.find(services, &(&1.id == params["service"])) ||
        Enum.find(services, &(Bookings.available_slots(&1, socket.assigns.selected) != [])) ||
        List.first(services)

    slots = if service, do: Bookings.available_slots(service, socket.assigns.selected), else: []
    slot = select_slot(slots, params["slot"])
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    assign(socket,
      service: service,
      by_day: %{},
      month_entries: [],
      selected_entries: [],
      slots: slots,
      slot: slot,
      request_form:
        to_form(Bookings.change_request(%{"contact_name" => user && user.name}), as: :booking)
    )
  end

  defp assign_availability(socket) do
    {from, to} = grid_range(socket.assigns.month)
    assign(socket, :availability, Bookings.bookable_days(socket.assigns.services, from, to))
  end

  defp select_slot(slots, value) do
    Enum.find(slots, &(Calendar.strftime(&1.starts_at, "%H:%M") == value)) ||
      if(length(slots) == 1, do: hd(slots))
  end

  defp refresh_booking_selection(%{assigns: %{mode: :book}} = socket) do
    service = socket.assigns.service
    service = service && Enum.find(socket.assigns.services, &(&1.id == service.id))
    slots = if service, do: Bookings.available_slots(service, socket.assigns.selected), else: []
    previous_slot = socket.assigns.slot
    slot = previous_slot && Enum.find(slots, &(&1.starts_at == previous_slot.starts_at))

    error =
      if (previous_slot && !slot) || (socket.assigns.service && !service),
        do: gettext("Availability changed. Please choose a service and time again."),
        else: socket.assigns.booking_error

    assign(socket, service: service, slots: slots, slot: slot, booking_error: error)
  end

  defp refresh_booking_selection(socket), do: socket

  defp booking_entry(booking) do
    %{
      id: "booking-#{booking.id}",
      source: :booking,
      key: nil,
      event: nil,
      booking: booking,
      kind: :booking,
      first_day: NaiveDateTime.to_date(booking.starts_at),
      last_day: NaiveDateTime.to_date(booking.ends_at),
      starts_at: booking.starts_at,
      ends_at: booking.ends_at,
      all_day: false
    }
  end

  @impl true
  def handle_event("new-event", _params, %{assigns: %{admin?: true, mode: :events}} = socket) do
    event = %Event{starts_at: NaiveDateTime.new!(socket.assigns.selected, ~T[18:00:00])}
    {:noreply, assign(socket, event_editor: event, event_focus: "#calendar-add-event")}
  end

  def handle_event(
        "edit-event",
        %{"id" => id},
        %{assigns: %{admin?: true, mode: :events}} = socket
      ) do
    case Events.get_event(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("This event no longer exists."))}

      event ->
        {:noreply, assign(socket, event_editor: event, event_focus: "#edit-event-#{event.id}")}
    end
  end

  def handle_event(action, _params, socket) when action in ["new-event", "edit-event"] do
    {:noreply, put_flash(socket, :error, gettext("You are not allowed to do that."))}
  end

  def handle_event("close-event", _params, socket),
    do: {:noreply, assign(socket, :event_editor, nil)}

  def handle_event("booking-change", params, socket) do
    service = Enum.find(socket.assigns.services, &(&1.id == params["service"]))
    slots = if service, do: Bookings.available_slots(service, socket.assigns.selected), else: []
    slot = select_slot(slots, params["slot"])

    {:noreply,
     assign(socket,
       service: service,
       slots: slots,
       slot: slot,
       booking_error: nil,
       request_form: to_form(Bookings.change_request(params["booking"] || %{}), as: :booking)
     )}
  end

  def handle_event("close-booking", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: cal_path(:book, socket.assigns.service, socket.assigns.month, socket.assigns.selected)
     )}
  end

  def handle_event("request", %{"booking" => params} = submitted, socket) do
    %{current_scope: scope, selected: selected} = socket.assigns
    service = Enum.find(socket.assigns.services, &(&1.id == submitted["service"]))
    service = service && Bookings.get_service(service.id)

    slots =
      if service && service.active, do: Bookings.available_slots(service, selected), else: []

    slot = Enum.find(slots, &(Calendar.strftime(&1.starts_at, "%H:%M") == submitted["slot"]))
    socket = assign(socket, service: service, slots: slots, slot: slot)

    result =
      cond do
        is_nil(scope) -> {:error, :forbidden}
        is_nil(slot) -> {:error, :unavailable}
        true -> Bookings.request_booking(scope, service, slot.starts_at, params)
      end

    case result do
      {:ok, booking} ->
        {:noreply, assign(socket, requested: booking, booking_error: nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, request_form: to_form(changeset, as: :booking))}

      {:error, :unavailable} ->
        {:noreply,
         socket
         |> assign(:services, Bookings.list_services())
         |> assign_availability()
         |> refresh_booking_selection()
         |> assign(
           request_form: to_form(Bookings.change_request(params), as: :booking),
           booking_error: gettext("That time is no longer available. Please choose another time.")
         )}

      {:error, :forbidden} ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}
    end
  end

  # --- paths -----------------------------------------------------------------

  defp cal_path(mode, service, month, date, opts \\ []) do
    query =
      [
        mode: if(mode == :book, do: "book"),
        service: if(mode == :book && service, do: service.id),
        month: month_param(month),
        date: date && Date.to_iso8601(date),
        open: if(Keyword.get(opts, :open, false), do: "1")
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    ~p"/calendar?#{query}"
  end

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp parse_month(value) when is_binary(value), do: parse_date(value <> "-01")
  defp parse_month(_), do: nil

  defp first_of_month(date), do: Date.beginning_of_month(date)
  defp same_month?(a, b), do: a.year == b.year and a.month == b.month

  # whole weeks covering the month, starting on the locale's first weekday
  defp grid_range(month) do
    start_offset = Integer.mod(Date.day_of_week(month) - week_start(), 7)
    last = Date.end_of_month(month)
    end_offset = Integer.mod(week_start() + 6 - Date.day_of_week(last), 7)
    {Date.add(month, -start_offset), Date.add(last, end_offset)}
  end

  # "Jumada al-Ula – Jumada al-Thani 1448"
  defp hijri_span(first, last) do
    {y1, m1, _} = Events.hijri(first)
    {y2, m2, _} = Events.hijri(last)

    cond do
      {y1, m1} == {y2, m2} -> "#{hijri_month_name(m1)} #{y1}"
      y1 == y2 -> "#{hijri_month_name(m1)} – #{hijri_month_name(m2)} #{y2}"
      true -> "#{hijri_month_name(m1)} #{y1} – #{hijri_month_name(m2)} #{y2}"
    end
  end

  defp month_param(date), do: Calendar.strftime(date, "%Y-%m")
  defp shift_month(month, n), do: month |> Date.shift(month: n) |> first_of_month()
  defp weekday_order, do: Enum.map(0..6, &(Integer.mod(week_start() - 1 + &1, 7) + 1))

  # details of a confirmed booking: only for the person who booked and admins
  defp booking_details?(%{source: :booking, booking: booking}, scope, admin?),
    do: admin? or (scope != nil and scope.user.id == booking.user_id)

  defp booking_details?(_entry, _scope, _admin?), do: false

  # --- render ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={:calendar}>
      <div id="calendar" class="mx-auto max-w-7xl px-4 pt-5 sm:px-6 lg:px-8 lg:pt-8">
        <Layouts.page_hero id="calendar-hero">
          <:title>{gettext("Calendar")}</:title>
          <:subtitle>
            {gettext("Explore events and book a time.")}
          </:subtitle>
        </Layouts.page_hero>

        <div class={["mt-6 grid gap-6", @mode == :events && "xl:grid-cols-[minmax(0,1fr)_22rem]"]}>
          <%!-- month grid --%>
          <div
            id="calendar-grid"
            class="overflow-hidden rounded-2xl border border-base-300 bg-base-100"
          >
            <header id="calendar-controls" class="border-b border-base-300 p-4 sm:p-5">
              <div class="flex flex-wrap items-center justify-between gap-4">
                <div class="min-w-0">
                  <h2 id="calendar-title" class="text-lg font-bold capitalize sm:text-xl">
                    {month_name(@month.month)} {@month.year}
                  </h2>
                  <p class="mt-1 flex items-center gap-1.5 text-xs text-base-content/60">
                    <.icon name="hero-moon-micro" class="size-4 text-primary" />
                    {@hijri_span}
                  </p>
                </div>
                <div class="flex flex-wrap items-center gap-2">
                  <.segmented_control
                    id="calendar-mode"
                    role="group"
                    aria-label={gettext("Calendar")}
                  >
                    <.link
                      id="mode-events"
                      patch={cal_path(:events, nil, @month, @selected)}
                      aria-current={if(@mode == :events, do: "page")}
                      class={segmented_option_class()}
                    >
                      <.icon name="hero-calendar-days-micro" class="size-4" />{gettext("Calendar")}
                    </.link>
                    <.link
                      :if={@services != []}
                      id="mode-book"
                      patch={cal_path(:book, nil, @month, @selected)}
                      aria-current={if(@mode == :book, do: "page")}
                      class={segmented_option_class()}
                    >
                      <.icon name="hero-bookmark-square-micro" class="size-4" />{gettext("Book")}
                    </.link>
                  </.segmented_control>

                  <.link
                    id="calendar-today"
                    patch={cal_path(@mode, @service, @today, @today)}
                    class="inline-flex h-8 items-center gap-2 rounded-full border border-base-300 bg-base-100 pe-3 ps-1 text-xs font-semibold transition hover:border-primary/40 hover:bg-base-200 active:scale-95 focus-visible:outline-2 focus-visible:outline-primary"
                  >
                    <span class="grid size-6 place-items-center rounded-full bg-primary/10 text-primary">
                      <.icon name="hero-calendar-days-micro" class="size-4" />
                    </span>
                    {gettext("Today")}
                  </.link>
                  <div class="inline-flex h-8 items-center gap-1 rounded-full bg-neutral-200 p-1 shadow-inner ring-1 ring-inset ring-black/5 dark:bg-neutral-800 dark:ring-white/10">
                    <.link
                      id="calendar-prev"
                      patch={cal_path(@mode, @service, shift_month(@month, -1), nil)}
                      aria-label={gettext("Previous month")}
                      class="grid size-6 place-items-center rounded-full bg-white text-neutral-800 shadow-md transition hover:bg-primary/10 active:scale-95 focus-visible:outline-2 focus-visible:outline-primary"
                    >
                      <.icon name="hero-chevron-left" class="size-4 rtl:rotate-180" />
                    </.link>
                    <.link
                      id="calendar-next"
                      patch={cal_path(@mode, @service, shift_month(@month, 1), nil)}
                      aria-label={gettext("Next month")}
                      class="grid size-6 place-items-center rounded-full bg-white text-neutral-800 shadow-md transition hover:bg-primary/10 active:scale-95 focus-visible:outline-2 focus-visible:outline-primary"
                    >
                      <.icon name="hero-chevron-right" class="size-4 rtl:rotate-180" />
                    </.link>
                  </div>
                  <button
                    :if={@admin? and @mode == :events}
                    type="button"
                    id="calendar-add-event"
                    phx-click="new-event"
                    aria-label={gettext("Add event")}
                    class="inline-flex h-8 items-center gap-1.5 rounded-full bg-primary px-3 text-xs font-semibold text-primary-content transition hover:opacity-85 active:scale-95 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                  >
                    <.icon name="hero-plus" class="size-4" />
                    <span class="hidden sm:inline">{gettext("Add event")}</span>
                  </button>
                </div>
              </div>
              <p
                :if={@mode == :book}
                id="booking-instructions"
                class="mt-4 flex items-center gap-2 text-sm text-base-content/65"
              >
                <.icon name="hero-cursor-arrow-rays" class="size-4 shrink-0 text-primary" />
                {gettext("Choose a day to request a booking.")}
              </p>
              <p id="availability-help" class="mt-2 text-xs leading-relaxed text-base-content/55">
                {gettext("A day is available when at least one service has a free time.")}
              </p>
            </header>
            <div class="grid grid-cols-7 border-b border-base-300 bg-base-200/50 text-center text-[11px] font-semibold uppercase tracking-wider text-base-content/55">
              <div :for={weekday <- weekday_order()} class="truncate px-0.5 py-2.5">
                {weekday_short(weekday)}
              </div>
            </div>

            <div
              :for={week <- @weeks}
              class="grid grid-cols-7 border-b border-base-300 last:border-b-0"
            >
              <.day_cell
                :for={day <- week}
                day={day}
                in_month={same_month?(day, @month)}
                today={day == @today}
                selected={day == @selected}
                path={cal_path(@mode, @service, first_of_month(day), day, open: @mode == :book)}
                entries={if(@mode == :events, do: Map.get(@by_day, day, []), else: [])}
                availability={Map.get(@availability, day, false)}
              />
            </div>
          </div>

          <%!-- side panel --%>
          <div :if={@mode == :events} class="space-y-4">
            <section
              id="calendar-day"
              class="rounded-2xl border border-base-300 bg-base-100 p-4"
            >
              <.day_heading selected={@selected} today={@today} />

              <p :if={@selected_entries == []} class="mt-4 text-sm text-base-content/55">
                {gettext("Nothing on this day.")}
              </p>
              <ul class="mt-3 space-y-2">
                <li
                  :for={entry <- @selected_entries}
                  id={"day-#{entry.id}"}
                  class="rounded-xl border border-base-300/70 p-3"
                >
                  <div class="flex items-start justify-between gap-2">
                    <span class={[
                      "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-medium",
                      kind_chip(entry.kind)
                    ]}>
                      <.kind_dot_badge kind={entry.kind} class="size-1.5" />
                      {kind_name(entry.kind)}
                    </span>
                    <button
                      :if={@admin? && entry.source == :event}
                      type="button"
                      id={"edit-#{entry.id}"}
                      phx-click="edit-event"
                      phx-value-id={entry.event.id}
                      class="text-xs font-medium text-primary hover:underline"
                    >
                      {gettext("Edit")}
                    </button>
                    <.link
                      :if={booking_details?(entry, @current_scope, @admin?)}
                      navigate={~p"/dashboard/bookings"}
                      class="text-xs font-medium text-primary hover:underline"
                    >
                      {gettext("Details")}
                    </.link>
                  </div>
                  <p dir="auto" class={["mt-2 font-semibold leading-snug", kind_text(entry.kind)]}>
                    {entry_title(entry)}
                  </p>
                  <p
                    :if={booking_details?(entry, @current_scope, @admin?)}
                    dir="auto"
                    class="text-sm text-base-content/70"
                  >
                    {entry.booking.contact_name}
                  </p>
                  <p
                    :if={entry_time(entry) || (entry.event && entry.event.location)}
                    class="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-base-content/60"
                  >
                    <span :if={entry_time(entry)} class="inline-flex items-center gap-1">
                      <.icon name="hero-clock-micro" class="size-3.5" />{entry_time(entry)}
                    </span>
                    <span
                      :if={entry.event && entry.event.location}
                      dir="auto"
                      class="inline-flex items-center gap-1"
                    >
                      <.icon name="hero-map-pin-micro" class="size-3.5" />{entry.event.location}
                    </span>
                  </p>
                  <p
                    :if={entry.event && entry.event.description}
                    dir="auto"
                    class="mt-2 whitespace-pre-line text-sm text-base-content/70"
                    phx-no-format
                  >{entry.event.description}</p>
                </li>
              </ul>
            </section>

            <section
              id="calendar-month-list"
              class="rounded-2xl border border-base-300 bg-base-100 p-4"
            >
              <h2 class="text-sm font-semibold">{gettext("This month")}</h2>
              <p :if={@month_entries == []} class="mt-2 text-sm text-base-content/55">
                {gettext("Nothing this month.")}
              </p>
              <ol class="mt-2 divide-y divide-base-300/70">
                <li :for={entry <- @month_entries} id={"month-#{entry.id}"}>
                  <.link
                    patch={cal_path(:events, nil, @month, entry.first_day)}
                    class="group flex items-start gap-3 py-2"
                  >
                    <span class="w-7 shrink-0 pt-0.5 text-end text-sm font-bold tabular-nums">
                      {entry.first_day.day}
                    </span>
                    <.kind_dot_badge kind={entry.kind} class="mt-2 size-1.5" />
                    <span
                      dir="auto"
                      class={[
                        "min-w-0 flex-1 text-sm leading-snug transition-opacity group-hover:opacity-75",
                        kind_text(entry.kind)
                      ]}
                    >
                      {entry_title(entry)}
                    </span>
                  </.link>
                </li>
              </ol>
            </section>

            <section
              id="calendar-legend"
              class="flex flex-wrap gap-x-4 gap-y-2 px-1 text-xs text-base-content/60"
            >
              <span
                :for={kind <- Taamol.Events.Event.kinds() ++ [:booking]}
                class="inline-flex items-center gap-1.5"
              >
                <.kind_dot_badge kind={kind} />{kind_name(kind)}
              </span>
            </section>
          </div>
        </div>

        <.booking_dialog
          :if={@booking_open?}
          services={@services}
          service={@service}
          selected={@selected}
          slots={@slots}
          slot={@slot}
          request_form={@request_form}
          requested={@requested}
          booking_error={@booking_error}
          current_scope={@current_scope}
        />
        <.live_component
          :if={@event_editor}
          module={TaamolWeb.EventEditorComponent}
          id="calendar-event"
          event={@event_editor}
          current_scope={@current_scope}
          dialog={true}
          focus_return={@event_focus}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :selected, Date, required: true
  attr :today, Date, required: true

  defp day_heading(assigns) do
    ~H"""
    <p class="text-xs font-semibold uppercase tracking-wider text-primary">
      {if(@selected == @today, do: gettext("Today"), else: weekday_short(Date.day_of_week(@selected)))}
    </p>
    <h2 class="mt-0.5 text-lg font-bold tracking-tight">
      {@selected.day} {month_name(@selected.month)} {@selected.year}
    </h2>
    <p class="text-sm text-base-content/55">{format_hijri(@selected)}</p>
    """
  end

  attr :services, :list, required: true
  attr :service, :map, default: nil
  attr :selected, Date, required: true
  attr :slots, :list, required: true
  attr :slot, :map, default: nil
  attr :request_form, :any, required: true
  attr :requested, :map, default: nil
  attr :booking_error, :string, default: nil
  attr :current_scope, :map, default: nil

  defp booking_dialog(assigns) do
    ~H"""
    <div
      id="booking-dialog-backdrop"
      class="fixed inset-0 z-[60] flex items-end justify-center bg-black/55 p-3 backdrop-blur-sm sm:items-center sm:p-6"
    >
      <.focus_wrap
        id="booking-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="booking-dialog-title"
        phx-mounted={JS.focus(to: "#booking-dialog-close")}
        phx-window-keydown={JS.push("close-booking") |> JS.focus(to: "#day-cell-#{@selected}")}
        phx-key="Escape"
        phx-click-away="close-booking"
        class="max-h-[calc(100dvh-1.5rem)] w-full max-w-lg overflow-y-auto rounded-3xl border border-base-300 bg-base-100 shadow-2xl sm:max-h-[calc(100dvh-3rem)]"
      >
        <div class="flex items-start justify-between gap-4 border-b border-base-300 bg-base-200/40 p-5 sm:p-6">
          <div class="flex min-w-0 items-start gap-3">
            <span class="grid size-11 shrink-0 place-items-center rounded-2xl bg-primary/10 text-primary">
              <.icon name="hero-calendar-days" class="size-6" />
            </span>
            <div>
              <h2 id="booking-dialog-title" class="text-xl font-bold">
                {gettext("Request a booking")}
              </h2>
              <p class="mt-1 text-sm text-base-content/65">
                {@selected.day} {month_name(@selected.month)} {@selected.year} · {format_hijri(
                  @selected
                )}
              </p>
            </div>
          </div>
          <button
            type="button"
            id="booking-dialog-close"
            phx-click={JS.push("close-booking") |> JS.focus(to: "#day-cell-#{@selected}")}
            aria-label={gettext("Close")}
            class="grid size-10 shrink-0 place-items-center rounded-full text-base-content/60 transition hover:bg-base-200 hover:text-base-content focus-visible:outline-2 focus-visible:outline-primary"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="p-5 sm:p-6">
          <div
            :if={@requested}
            id="booking-requested"
            role="status"
            class="rounded-2xl bg-success/10 p-5 text-sm"
          >
            <p class="flex items-center gap-2 text-base font-semibold text-success">
              <.icon name="hero-check-circle" class="size-6" />{gettext("Request sent!")}
            </p>
            <p class="mt-2 leading-relaxed text-base-content/70">
              {gettext(
                "We will confirm your booking or suggest another time. You'll get an email, and you can follow it in your dashboard."
              )}
            </p>
            <.link
              navigate={~p"/dashboard/bookings"}
              class="mt-4 inline-flex font-semibold text-primary hover:underline"
            >
              {gettext("My bookings")}
              <.icon name="hero-arrow-right" class="ms-1 size-4 rtl:rotate-180" />
            </.link>
          </div>

          <.form
            :if={!@requested}
            for={@request_form}
            id="booking-form"
            phx-change="booking-change"
            phx-submit="request"
          >
            <p
              :if={@booking_error}
              id="booking-error"
              role="alert"
              class="mb-4 rounded-xl bg-error/10 p-3 text-sm text-error"
            >
              {@booking_error}
            </p>
            <p
              :if={@services == []}
              id="booking-no-services"
              class="rounded-xl bg-base-200/70 p-4 text-sm text-base-content/65"
            >
              {gettext("Nothing can be booked right now.")}
            </p>
            <div :if={@services != []} id="booking-request" class="space-y-3">
              <.input
                type="select"
                id="booking-service"
                name="service"
                label={gettext("Service")}
                icon="hero-squares-2x2"
                value={@service && @service.id}
                prompt={gettext("Choose a service")}
                options={Enum.map(@services, &{service_name(&1), &1.id})}
                required
              />
              <p
                :if={@service && service_description(@service)}
                dir="auto"
                class="text-sm leading-relaxed text-base-content/60"
              >
                {service_description(@service)}
              </p>
              <p
                :if={@service && @slots == []}
                id="booking-unavailable"
                class="rounded-xl bg-base-200/70 p-3 text-sm text-base-content/65"
              >
                {gettext(
                  "No times are available for this service on this day. Choose another service or day."
                )}
              </p>
              <.input
                type="select"
                id="booking-time"
                name="slot"
                label={gettext("Time")}
                icon="hero-clock"
                value={@slot && Calendar.strftime(@slot.starts_at, "%H:%M")}
                prompt={gettext("Choose a time")}
                options={
                  Enum.map(
                    @slots,
                    &{time_range(&1.starts_at, &1.ends_at), Calendar.strftime(&1.starts_at, "%H:%M")}
                  )
                }
                disabled={@slots == []}
                required
              />
              <p class="text-xs leading-relaxed text-base-content/55">
                {gettext("Requests are subject to confirmation. Book at least 24 hours in advance.")}
              </p>

              <%= if @current_scope do %>
                <div class="grid gap-x-4 sm:grid-cols-2">
                  <.input
                    field={@request_form[:contact_name]}
                    type="text"
                    label={gettext("Name")}
                    required
                    dir="auto"
                  />
                  <.input
                    field={@request_form[:contact_phone]}
                    type="tel"
                    label={gettext("Phone")}
                    required
                    placeholder="070 123 45 67"
                  />
                </div>
                <.input
                  field={@request_form[:guests]}
                  type="number"
                  label={gettext("Number of guests (optional)")}
                  min="0"
                  max="2000"
                />
                <.input
                  field={@request_form[:notes]}
                  type="textarea"
                  label={gettext("Anything we should know? (optional)")}
                  rows="3"
                  dir="auto"
                />
                <button
                  type="submit"
                  id="send-booking"
                  phx-disable-with={gettext("Sending…")}
                  disabled={@slots == []}
                  class="mt-2 flex w-full items-center justify-center gap-2 rounded-xl bg-primary px-4 py-3 text-sm font-semibold text-primary-content transition hover:opacity-85 active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <.icon name="hero-paper-airplane" class="size-4" />{gettext("Send booking request")}
                </button>
              <% else %>
                <div id="booking-login" class="mt-3 rounded-xl bg-base-200/70 p-3 text-sm">
                  <p class="text-base-content/70">{gettext("Log in to send a booking request.")}</p>
                  <.link
                    navigate={~p"/users/log-in"}
                    class="mt-2 inline-block font-semibold text-primary hover:underline"
                  >
                    {gettext("Log in")}
                  </.link>
                </div>
              <% end %>
            </div>
          </.form>
        </div>
      </.focus_wrap>
    </div>
    """
  end

  attr :day, Date, required: true
  attr :in_month, :boolean, required: true
  attr :today, :boolean, required: true
  attr :selected, :boolean, required: true
  attr :path, :string, required: true
  attr :entries, :list, default: []
  attr :availability, :boolean, required: true

  defp day_cell(assigns) do
    {_, hijri_month, hijri_day} = Events.hijri(assigns.day)
    assigns = assign(assigns, hijri_day: hijri_day, hijri_month: hijri_month)

    ~H"""
    <.link
      id={"day-cell-#{Date.to_iso8601(@day)}"}
      patch={@path}
      aria-current={if(@selected, do: "date")}
      class={[
        "group relative flex min-h-16 flex-col gap-1 border-e border-base-300 p-1.5 text-start transition last:border-e-0 hover:bg-base-200/60 sm:min-h-24 sm:p-2 lg:min-h-28",
        !@in_month && "bg-base-200/30 text-base-content/40",
        @selected && "bg-primary/5 ring-2 ring-inset ring-primary/60"
      ]}
    >
      <span class="flex items-start justify-between gap-1">
        <span class={[
          "grid size-6 place-items-center rounded-full text-xs font-semibold tabular-nums sm:size-7 sm:text-sm",
          @today && "bg-primary text-primary-content"
        ]}>
          {@day.day}
        </span>
        <span class="pt-0.5 text-[10px] leading-tight tabular-nums text-base-content/45 sm:text-[11px]">
          <span :if={@hijri_day == 1} class="hidden font-semibold text-primary/80 lg:inline">
            {hijri_month_name(@hijri_month)}
          </span>
          {@hijri_day}
        </span>
      </span>

      <span
        id={"day-availability-#{Date.to_iso8601(@day)}"}
        class={[
          "mt-auto flex items-center gap-1 text-[10px] font-semibold leading-tight sm:text-[11px]",
          if(@availability, do: "text-success", else: "text-base-content/50")
        ]}
      >
        <.icon
          name={if(@availability, do: "hero-check-circle-micro", else: "hero-minus-circle-micro")}
          class="size-3.5 shrink-0"
        />
        <span class="sm:hidden">{if(@availability, do: gettext("Free"), else: gettext("No slots"))}</span>
        <span class="hidden sm:inline">{if(@availability,
          do: gettext("Available"),
          else: gettext("Unavailable")
        )}</span>
      </span>

      <%!-- calendar mode: chips on larger screens, dots on phones --%>
      <span :if={@entries != []} class="hidden flex-col gap-1 sm:flex">
        <span
          :for={entry <- Enum.take(@entries, 2)}
          dir="auto"
          class={["truncate rounded-md px-1.5 py-0.5 text-[11px] font-medium", kind_chip(entry.kind)]}
        >
          {entry_title(entry)}
        </span>
        <span :if={length(@entries) > 2} class="px-1.5 text-[11px] text-base-content/55">
          {gettext("+%{count} more", count: length(@entries) - 2)}
        </span>
      </span>
      <span :if={@entries != []} class="mt-auto flex flex-wrap gap-1 sm:hidden">
        <.kind_dot_badge :for={entry <- Enum.take(@entries, 4)} kind={entry.kind} class="size-1.5" />
      </span>
    </.link>
    """
  end
end
