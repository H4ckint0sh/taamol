defmodule TaamolWeb.DashboardComponents do
  @moduledoc """
  Dashboard building blocks: stat tiles, single-series charts, status badges,
  cards and pagination.

  Charts follow one rule set: a single series in the theme's primary colour
  (no legend, the card title names it), thin marks with rounded data ends and
  a 2px gap, text in text colours, a hover tooltip per mark and a
  screen-reader table with the same numbers.
  """
  use TaamolWeb, :html

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :note, :string, default: nil

  @doc "A big number with a label (\"42 · Published articles\")."
  def stat_tile(assigns) do
    ~H"""
    <div id={@id} class="rounded-2xl border border-base-300 bg-base-100 p-5">
      <div class="flex items-center gap-3">
        <span class="grid size-9 place-items-center rounded-lg bg-base-200 text-base-content/70">
          <.icon name={@icon} class="size-5" />
        </span>
        <span data-value class="text-2xl font-bold tabular-nums">{@value}</span>
      </div>
      <p class="mt-3 font-semibold">{@label}</p>
      <p :if={@note} class="mt-0.5 text-sm text-base-content/55">{@note}</p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  @doc """
  A stat-tile style card for a piece of information ("Phone · 070 …"), used on
  the public contact and donate pages so they match the dashboard.
  """
  def info_card(assigns) do
    ~H"""
    <section
      id={@id}
      class={["flex items-start gap-3 rounded-2xl border border-base-300 bg-base-100 p-5", @class]}
    >
      <span class="grid size-9 shrink-0 place-items-center rounded-lg bg-base-200 text-base-content/70">
        <.icon name={@icon} class="size-5" />
      </span>
      <div class="min-w-0 flex-1">
        <h2 class="font-semibold">{@title}</h2>
        <div class="mt-0.5 text-sm text-base-content/60">{render_slot(@inner_block)}</div>
      </div>
    </section>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :class, :string, default: nil
  attr :padded, :boolean, default: true
  slot :inner_block, required: true
  slot :actions

  @doc "A bordered dashboard card with an optional title row."
  def card(assigns) do
    ~H"""
    <section
      id={@id}
      class={["rounded-2xl border border-base-300 bg-base-100", @padded && "p-5", @class]}
    >
      <div
        :if={@title || @actions != []}
        class={[
          "flex items-center justify-between gap-3",
          @padded && "mb-4",
          !@padded && "px-5 pt-5 pb-4"
        ]}
      >
        <h2 :if={@title} class="font-semibold">{@title}</h2>
        {render_slot(@actions)}
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :id, :string, required: true
  attr :points, :list, required: true, doc: "[%{label: String.t(), value: integer}] oldest first"

  attr :value_label, :string,
    required: true,
    doc: "unit for tooltips and the table, e.g. \"sign-ups\""

  @doc "Column chart for a short time series (e.g. sign-ups per week)."
  def column_chart(assigns) do
    max = assigns.points |> Enum.map(& &1.value) |> Enum.max(fn -> 0 end)
    assigns = assign(assigns, :max, max(max, 1))

    ~H"""
    <div id={@id}>
      <div class="flex h-40 items-end gap-0.5" aria-hidden="true">
        <div
          :for={point <- @points}
          class="group/bar relative flex h-full flex-1 items-end justify-center"
        >
          <%!-- hover target is the full column, bigger than the bar --%>
          <span
            class="block w-full max-w-10 rounded-t-[4px] bg-primary transition-opacity group-hover/bar:opacity-80"
            style={"height: #{max(point.value / @max * 100, if(point.value > 0, do: 2, else: 0))}%"}
          />
          <span class="pointer-events-none absolute -top-8 z-10 hidden whitespace-nowrap rounded-md bg-base-content px-2 py-1 text-[11px] text-base-100 shadow group-hover/bar:block">
            {point.label}: {point.value} {@value_label}
          </span>
        </div>
      </div>
      <div
        class="mt-2 flex gap-0.5 border-t border-base-300 pt-2 text-[10px] text-base-content/55"
        aria-hidden="true"
      >
        <span :for={point <- @points} class="flex-1 truncate text-center">{point.label}</span>
      </div>
      <table class="sr-only">
        <tr :for={point <- @points}>
          <th>{point.label}</th><td>{point.value} {@value_label}</td>
        </tr>
      </table>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "[%{label: String.t(), value: integer}] largest first"
  attr :format, :any, default: &Integer.to_string/1

  @doc "Horizontal bars with labels and values (e.g. views per category)."
  def bar_list(assigns) do
    max = assigns.rows |> Enum.map(& &1.value) |> Enum.max(fn -> 0 end)
    assigns = assign(assigns, :max, max(max, 1))

    ~H"""
    <ul id={@id} class="space-y-2.5">
      <li
        :for={row <- @rows}
        class="group/row grid grid-cols-[7rem_minmax(0,1fr)_4rem] items-center gap-3 text-sm"
      >
        <span class="truncate text-base-content/75">{row.label}</span>
        <span class="h-2.5 rounded-full bg-base-200" title={"#{row.label}: #{@format.(row.value)}"}>
          <span
            class="block h-full rounded-full bg-primary transition-opacity group-hover/row:opacity-80"
            style={"width: #{max(row.value / @max * 100, if(row.value > 0, do: 2, else: 0))}%"}
          />
        </span>
        <span class="text-end tabular-nums text-base-content/75">{@format.(row.value)}</span>
      </li>
    </ul>
    """
  end

  attr :status, :atom, required: true

  @doc "Published / Scheduled / Draft badge (icon + label, never colour alone)."
  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-medium",
      @status == :published && "bg-success/12 text-success",
      @status == :scheduled && "bg-info/12 text-info",
      @status == :draft && "bg-base-200 text-base-content/70"
    ]}>
      <.icon
        name={
          case @status do
            :published -> "hero-check-circle-micro"
            :scheduled -> "hero-clock-micro"
            :draft -> "hero-pencil-micro"
          end
        }
        class="size-3.5"
      />
      {status_name(@status)}
    </span>
    """
  end

  def status_name(:published), do: gettext("Published")
  def status_name(:scheduled), do: gettext("Scheduled")
  def status_name(:draft), do: gettext("Draft")

  attr :page, :integer, required: true, doc: "1-based"
  attr :per_page, :integer, required: true
  attr :total, :integer, required: true
  attr :path, :any, required: true, doc: "fun page -> path"

  @doc "\"Showing 1 to 20 of 54\" with previous/next and page numbers."
  def pagination(assigns) do
    pages = max(ceil(assigns.total / assigns.per_page), 1)

    assigns =
      assign(assigns,
        pages: pages,
        from: if(assigns.total == 0, do: 0, else: (assigns.page - 1) * assigns.per_page + 1),
        to: min(assigns.page * assigns.per_page, assigns.total)
      )

    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-3 border-t border-base-300 px-5 py-3 text-sm">
      <p class="text-base-content/60">
        {gettext("Showing %{from} to %{to} of %{total}", from: @from, to: @to, total: @total)}
      </p>
      <nav :if={@pages > 1} class="flex items-center gap-1" aria-label={gettext("Pages")}>
        <.link
          :if={@page > 1}
          patch={@path.(@page - 1)}
          class="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 transition hover:bg-base-200"
        >
          <.icon name="hero-chevron-left-micro" class="size-4 rtl:rotate-180" />{gettext("Previous")}
        </.link>
        <.link
          :for={n <- page_window(@page, @pages)}
          patch={@path.(n)}
          aria-current={if(n == @page, do: "page")}
          class="grid size-8 place-items-center rounded-lg tabular-nums transition hover:bg-base-200 aria-[current=page]:bg-base-content aria-[current=page]:text-base-100"
        >
          {n}
        </.link>
        <.link
          :if={@page < @pages}
          patch={@path.(@page + 1)}
          class="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 transition hover:bg-base-200"
        >
          {gettext("Next")}<.icon name="hero-chevron-right-micro" class="size-4 rtl:rotate-180" />
        </.link>
      </nav>
    </div>
    """
  end

  defp page_window(page, pages) do
    first = max(1, min(page - 2, pages - 4))
    first..min(pages, first + 4)//1
  end

  @doc "Parses a positive page number from params."
  def page_param(params) do
    case Integer.parse(params["page"] || "1") do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end
end
