defmodule TaamolWeb.CalendarLive do
  @moduledoc """
  Month calendar of Shia holidays, historical days and Taamol community
  events. `?month=2026-11` picks the month, `?date=2026-11-13` the selected day.
  Administrators get links to add and edit events.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.CalendarComponents
  import TaamolWeb.NewsComponents, only: [month_name: 1]

  alias Taamol.Events

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Calendar"),
       admin?: Taamol.Accounts.admin?(socket.assigns.current_scope),
       today: Date.utc_today()
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

    {grid_start, grid_end} = grid_range(month)
    by_day = Events.entries_by_day(grid_start, grid_end)
    last_of_month = Date.end_of_month(month)

    month_entries =
      Events.entries_between(month, last_of_month)
      |> Enum.filter(&(Date.compare(&1.last_day, month) != :lt))

    {:noreply,
     assign(socket,
       month: month,
       selected: selected,
       weeks: grid_start |> Date.range(grid_end) |> Enum.chunk_every(7),
       by_day: by_day,
       month_entries: month_entries,
       selected_entries: Map.get(by_day, selected, []),
       hijri_span: hijri_span(month, last_of_month)
     )}
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

  defp day_path(date),
    do: ~p"/calendar?#{[month: month_param(date), date: Date.to_iso8601(date)]}"

  defp weekday_order, do: Enum.map(0..6, &(Integer.mod(week_start() - 1 + &1, 7) + 1))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={:calendar}>
      <div id="calendar" class="mx-auto max-w-7xl px-4 pt-5 sm:px-6 lg:px-8 lg:pb-16 lg:pt-8">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 id="calendar-title" class="text-2xl font-bold tracking-tight sm:text-3xl">
              {month_name(@month.month)} {@month.year}
            </h1>
            <p class="mt-1 flex items-center gap-1.5 text-sm text-base-content/60">
              <.icon name="hero-moon-micro" class="size-4 text-primary" />
              {@hijri_span}
            </p>
          </div>

          <div class="flex items-center gap-2">
            <.link
              id="calendar-today"
              patch={day_path(@today)}
              class="rounded-xl border border-base-300 px-3 py-2 text-sm font-medium transition hover:bg-base-200"
            >
              {gettext("Today")}
            </.link>
            <div class="flex overflow-hidden rounded-xl border border-base-300">
              <.link
                id="calendar-prev"
                patch={~p"/calendar?#{[month: month_param(shift_month(@month, -1))]}"}
                aria-label={gettext("Previous month")}
                class="grid size-9 place-items-center transition hover:bg-base-200"
              >
                <.icon name="hero-chevron-left" class="size-4 rtl:rotate-180" />
              </.link>
              <.link
                id="calendar-next"
                patch={~p"/calendar?#{[month: month_param(shift_month(@month, 1))]}"}
                aria-label={gettext("Next month")}
                class="grid size-9 place-items-center border-s border-base-300 transition hover:bg-base-200"
              >
                <.icon name="hero-chevron-right" class="size-4 rtl:rotate-180" />
              </.link>
            </div>
            <.link
              :if={@admin?}
              id="calendar-add-event"
              navigate={~p"/admin/events/new?#{[date: Date.to_iso8601(@selected)]}"}
              class="inline-flex items-center gap-1.5 rounded-xl bg-primary px-3 py-2 text-sm font-semibold text-primary-content transition hover:opacity-85"
            >
              <.icon name="hero-plus" class="size-4" />
              <span class="hidden sm:inline">{gettext("Add event")}</span>
            </.link>
          </div>
        </div>

        <div class="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_21rem]">
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
                entries={Map.get(@by_day, day, [])}
              />
            </div>
          </div>

          <%!-- selected day + month list --%>
          <div class="space-y-4">
            <section
              id="calendar-day"
              class="rounded-2xl border border-base-300 bg-base-100 p-4"
            >
              <p class="text-xs font-semibold uppercase tracking-wider text-primary">
                {if(@selected == @today,
                  do: gettext("Today"),
                  else: weekday_short(Date.day_of_week(@selected))
                )}
              </p>
              <h2 class="mt-0.5 text-lg font-bold tracking-tight">
                {@selected.day} {month_name(@selected.month)} {@selected.year}
              </h2>
              <p class="text-sm text-base-content/55">{format_hijri(@selected)}</p>

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
                      navigate={~p"/admin/events/#{entry.event.id}/edit"}
                      class="text-xs font-medium text-primary hover:underline"
                    >
                      {gettext("Edit")}
                    </.link>
                  </div>
                  <p dir="auto" class="mt-2 font-semibold leading-snug">{entry_title(entry)}</p>
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
                  >
                    {entry.event.description}
                  </p>
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
                  <.link patch={day_path(entry.first_day)} class="group flex items-start gap-3 py-2">
                    <span class="w-7 shrink-0 pt-0.5 text-end text-sm font-bold tabular-nums">
                      {entry.first_day.day}
                    </span>
                    <.kind_dot_badge kind={entry.kind} class="mt-2 size-1.5" />
                    <span
                      dir="auto"
                      class="min-w-0 flex-1 text-sm leading-snug transition-colors group-hover:text-primary"
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
                :for={kind <- Taamol.Events.Event.kinds()}
                class="inline-flex items-center gap-1.5"
              >
                <.kind_dot_badge kind={kind} />{kind_name(kind)}
              </span>
            </section>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :day, Date, required: true
  attr :in_month, :boolean, required: true
  attr :today, :boolean, required: true
  attr :selected, :boolean, required: true
  attr :entries, :list, required: true

  defp day_cell(assigns) do
    {_, hijri_month, hijri_day} = Events.hijri(assigns.day)
    assigns = assign(assigns, hijri_day: hijri_day, hijri_month: hijri_month)

    ~H"""
    <.link
      id={"day-cell-#{Date.to_iso8601(@day)}"}
      patch={day_path(@day)}
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

      <%!-- chips on larger screens, dots on phones --%>
      <span class="hidden flex-col gap-1 sm:flex">
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
