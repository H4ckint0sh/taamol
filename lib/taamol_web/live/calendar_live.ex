defmodule TaamolWeb.CalendarLive do
  @moduledoc """
  The calendar, in two modes:

    * **Calendar** (default): Shia holidays, historical days, Taamol events and
      confirmed bookings (shown without personal details).
    * **Book** (`?mode=book&service=…`): pick a service; every day shows how
      many times are free; pick a day and a time (`&slot=18:00`) and send a
      booking request. An administrator accepts it, offers another time or
      declines it (Dashboard → Bookings).

  `?month=2026-11` picks the month and `?date=2026-11-13` the selected day.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.CalendarComponents

  import TaamolWeb.BookingComponents,
    only: [service_name: 1, service_description: 1, time_range: 2]

  import TaamolWeb.NewsComponents, only: [month_name: 1]

  alias Taamol.{Bookings, Events}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Calendar"),
       admin?: Taamol.Accounts.admin?(socket.assigns.current_scope),
       today: Date.utc_today(),
       services: Bookings.list_services(),
       requested: nil
     )}
  end

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
        weeks: grid_start |> Date.range(grid_end) |> Enum.chunk_every(7),
        hijri_span: hijri_span(month, last_of_month)
      )

    socket =
      case mode do
        :events -> assign_events(socket, grid_start, grid_end, month, last_of_month)
        :book -> assign_booking(socket, params, grid_start, grid_end)
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
      availability: %{},
      slots: [],
      slot: nil,
      by_day: by_day,
      month_entries: month_entries,
      selected_entries: Map.get(by_day, socket.assigns.selected, [])
    )
  end

  defp assign_booking(socket, params, grid_start, grid_end) do
    services = socket.assigns.services

    service =
      Enum.find(services, &(&1.id == params["service"])) || List.first(services)

    {availability, slots} =
      if service,
        do:
          {Bookings.availability(service, grid_start, grid_end),
           Bookings.available_slots(service, socket.assigns.selected)},
        else: {%{}, []}

    slot = Enum.find(slots, &(Calendar.strftime(&1.starts_at, "%H:%M") == params["slot"]))
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    assign(socket,
      service: service,
      by_day: %{},
      month_entries: [],
      selected_entries: [],
      availability: availability,
      slots: slots,
      slot: slot,
      request_form:
        to_form(Bookings.change_request(%{"contact_name" => user && user.name}), as: :booking)
    )
  end

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
  def handle_event("request", %{"booking" => params}, socket) do
    %{current_scope: scope, service: service, slot: slot} = socket.assigns

    case scope && slot && Bookings.request_booking(scope, service, slot.starts_at, params) do
      {:ok, booking} ->
        {:noreply,
         socket
         |> assign(requested: booking)
         |> push_patch(
           to: cal_path(:book, service, socket.assigns.month, socket.assigns.selected)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, request_form: to_form(changeset, as: :booking))}

      {:error, :unavailable} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("That time was just taken. Please choose another time.")
         )}

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/users/log-in")}
    end
  end

  def handle_event("dismiss-request", _params, socket),
    do: {:noreply, assign(socket, requested: nil)}

  # --- paths -----------------------------------------------------------------

  defp cal_path(mode, service, month, date, slot \\ nil) do
    query =
      [
        mode: if(mode == :book, do: "book"),
        service: if(mode == :book && service, do: service.id),
        month: month_param(month),
        date: date && Date.to_iso8601(date),
        slot: slot
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
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 id="calendar-title" class="text-2xl font-bold capitalize sm:text-3xl">
              {month_name(@month.month)} {@month.year}
            </h1>
            <p class="mt-1 flex items-center gap-1.5 text-sm text-base-content/60">
              <.icon name="hero-moon-micro" class="size-4 text-primary" />
              {@hijri_span}
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <%!-- Calendar | Book --%>
            <div
              id="calendar-mode"
              class="flex rounded-xl bg-base-200 p-1 text-sm font-medium"
              role="tablist"
            >
              <.link
                id="mode-events"
                patch={cal_path(:events, nil, @month, @selected)}
                aria-current={if(@mode == :events, do: "page")}
                class="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-base-content/65 transition aria-[current=page]:bg-base-100 aria-[current=page]:text-base-content aria-[current=page]:shadow-sm"
              >
                <.icon name="hero-calendar-days-micro" class="size-4" />{gettext("Calendar")}
              </.link>
              <.link
                :if={@services != []}
                id="mode-book"
                patch={cal_path(:book, nil, @month, @selected)}
                aria-current={if(@mode == :book, do: "page")}
                class="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-base-content/65 transition aria-[current=page]:bg-base-100 aria-[current=page]:text-base-content aria-[current=page]:shadow-sm"
              >
                <.icon name="hero-bookmark-square-micro" class="size-4" />{gettext("Book")}
              </.link>
            </div>

            <.link
              id="calendar-today"
              patch={cal_path(@mode, @service, @today, @today)}
              class="rounded-xl border border-base-300 px-3 py-2 text-sm font-medium transition hover:bg-base-200"
            >
              {gettext("Today")}
            </.link>
            <div class="flex overflow-hidden rounded-xl border border-base-300">
              <.link
                id="calendar-prev"
                patch={cal_path(@mode, @service, shift_month(@month, -1), nil)}
                aria-label={gettext("Previous month")}
                class="grid size-9 place-items-center transition hover:bg-base-200"
              >
                <.icon name="hero-chevron-left" class="size-4 rtl:rotate-180" />
              </.link>
              <.link
                id="calendar-next"
                patch={cal_path(@mode, @service, shift_month(@month, 1), nil)}
                aria-label={gettext("Next month")}
                class="grid size-9 place-items-center border-s border-base-300 transition hover:bg-base-200"
              >
                <.icon name="hero-chevron-right" class="size-4 rtl:rotate-180" />
              </.link>
            </div>
            <.link
              :if={@admin? and @mode == :events}
              id="calendar-add-event"
              navigate={~p"/dashboard/events/new?#{[date: Date.to_iso8601(@selected)]}"}
              class="inline-flex items-center gap-1.5 rounded-xl bg-primary px-3 py-2 text-sm font-semibold text-primary-content transition hover:opacity-85"
            >
              <.icon name="hero-plus" class="size-4" />
              <span class="hidden sm:inline">{gettext("Add event")}</span>
            </.link>
          </div>
        </div>

        <%!-- book mode: what to book --%>
        <div :if={@mode == :book && @service} id="booking-services" class="mt-5">
          <TaamolWeb.NewsComponents.chip_row id="service-chips" class="-mx-4 px-4 sm:mx-0 sm:px-0">
            <li :for={service <- @services}>
              <TaamolWeb.NewsComponents.chip
                patch={true}
                to={cal_path(:book, service, @month, @selected)}
                icon={service.icon}
                active={service.id == @service.id}
              >
                {service_name(service)}
              </TaamolWeb.NewsComponents.chip>
            </li>
          </TaamolWeb.NewsComponents.chip_row>
          <p
            :if={service_description(@service)}
            dir="auto"
            class="mt-2 max-w-3xl text-sm text-base-content/65"
          >
            {service_description(@service)}
          </p>
        </div>

        <div class="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_22rem]">
          <%!-- month grid --%>
          <div
            id="calendar-grid"
            class="overflow-hidden rounded-2xl border border-base-300 bg-base-100"
          >
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
                path={cal_path(@mode, @service, @month, day)}
                entries={if(@mode == :events, do: Map.get(@by_day, day, []), else: [])}
                availability={if(@mode == :book, do: Map.get(@availability, day))}
              />
            </div>
          </div>

          <%!-- side panel --%>
          <div class="space-y-4">
            <%= if @mode == :book do %>
              <.booking_panel
                service={@service}
                selected={@selected}
                today={@today}
                slots={@slots}
                slot={@slot}
                month={@month}
                availability={Map.get(@availability, @selected)}
                request_form={@request_form}
                requested={@requested}
                current_scope={@current_scope}
              />
            <% else %>
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
                      <.link
                        :if={@admin? && entry.source == :event}
                        id={"edit-#{entry.id}"}
                        navigate={~p"/dashboard/events/#{entry.event.id}/edit"}
                        class="text-xs font-medium text-primary hover:underline"
                      >
                        {gettext("Edit")}
                      </.link>
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
            <% end %>
          </div>
        </div>
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

  attr :service, :map, default: nil
  attr :selected, Date, required: true
  attr :today, Date, required: true
  attr :month, Date, required: true
  attr :slots, :list, required: true
  attr :slot, :map, default: nil
  attr :availability, :map, default: nil
  attr :request_form, :any, required: true
  attr :requested, :map, default: nil
  attr :current_scope, :map, default: nil

  # Book mode: free times for the selected day, then the request form
  defp booking_panel(assigns) do
    ~H"""
    <section id="booking-panel" class="rounded-2xl border border-base-300 bg-base-100 p-4">
      <div
        :if={@requested}
        id="booking-requested"
        class="mb-4 rounded-xl bg-success/10 p-4 text-sm"
      >
        <p class="flex items-center gap-2 font-semibold text-success">
          <.icon name="hero-check-circle" class="size-5" />{gettext("Request sent!")}
        </p>
        <p class="mt-1 text-base-content/70">
          {gettext(
            "We will confirm your booking or suggest another time. You'll get an email, and you can follow it in your dashboard."
          )}
        </p>
        <div class="mt-3 flex gap-3">
          <.link navigate={~p"/dashboard/bookings"} class="font-semibold text-primary hover:underline">
            {gettext("My bookings")}
          </.link>
          <button
            type="button"
            phx-click="dismiss-request"
            class="text-base-content/60 hover:underline"
          >
            {gettext("Close")}
          </button>
        </div>
      </div>

      <.day_heading selected={@selected} today={@today} />

      <%= cond do %>
        <% is_nil(@service) -> %>
          <p class="mt-4 text-sm text-base-content/55">
            {gettext("Nothing can be booked right now.")}
          </p>
        <% is_nil(@availability) or @availability.total == 0 -> %>
          <p
            id="booking-closed"
            class="mt-4 rounded-xl bg-base-200/70 p-3 text-sm text-base-content/65"
          >
            {gettext("This day can't be booked. Bookings are made at least a day in advance.")}
          </p>
        <% @slots == [] -> %>
          <p id="booking-full" class="mt-4 rounded-xl bg-base-200/70 p-3 text-sm text-base-content/65">
            {gettext("Fully booked this day. Please choose another day.")}
          </p>
        <% true -> %>
          <h3 class="mt-4 text-sm font-semibold">{gettext("Choose a time")}</h3>
          <p class="text-xs text-base-content/55">
            {ngettext("Takes %{count} minute", "Takes %{count} minutes", @service.duration_minutes)}
          </p>
          <div id="booking-slots" class="mt-2 grid grid-cols-3 gap-1.5">
            <.link
              :for={slot <- @slots}
              id={"slot-#{Calendar.strftime(slot.starts_at, "%H%M")}"}
              patch={
                cal_path(
                  :book,
                  @service,
                  @month,
                  @selected,
                  Calendar.strftime(slot.starts_at, "%H:%M")
                )
              }
              aria-current={if(@slot && @slot.starts_at == slot.starts_at, do: "true")}
              class="rounded-lg border border-base-300 py-2 text-center text-sm font-medium tabular-nums transition hover:border-primary/50 hover:bg-primary/5 aria-[current=true]:border-primary aria-[current=true]:bg-primary aria-[current=true]:text-primary-content"
            >
              {Calendar.strftime(slot.starts_at, "%H:%M")}
            </.link>
          </div>

          <div :if={@slot} id="booking-request" class="mt-5 border-t border-base-300 pt-4">
            <p class="text-sm font-semibold">{service_name(@service)}</p>
            <p class="text-sm text-base-content/65 tabular-nums">
              {@selected.day} {month_name(@selected.month)} · {time_range(
                @slot.starts_at,
                @slot.ends_at
              )}
            </p>

            <%= if @current_scope do %>
              <.form
                for={@request_form}
                id="booking-form"
                phx-submit="request"
                class="mt-3"
              >
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
                  class="mt-2 w-full rounded-xl bg-primary py-2.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
                >
                  {gettext("Send booking request")}
                </button>
              </.form>
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
      <% end %>
    </section>
    """
  end

  attr :day, Date, required: true
  attr :in_month, :boolean, required: true
  attr :today, :boolean, required: true
  attr :selected, :boolean, required: true
  attr :path, :string, required: true
  attr :entries, :list, default: []
  attr :availability, :map, default: nil, doc: "book mode: %{free:, total:}"

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
        @availability && @availability.total == 0 && "text-base-content/35",
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

      <%!-- book mode: free times --%>
      <span :if={@availability && @availability.total > 0} class="mt-auto">
        <%= if @availability.free > 0 do %>
          <span class="flex items-center gap-1 text-[11px] font-medium text-success">
            <span class="size-2 shrink-0 rounded-full bg-success" />
            <span class="hidden sm:inline">
              {ngettext("%{count} free", "%{count} free", @availability.free)}
            </span>
          </span>
        <% else %>
          <span class="flex items-center gap-1 text-[11px] font-medium text-base-content/45">
            <span class="size-2 shrink-0 rounded-full bg-base-content/25" />
            <span class="hidden sm:inline">{gettext("Full")}</span>
          </span>
        <% end %>
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
