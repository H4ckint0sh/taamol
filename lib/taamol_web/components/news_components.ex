defmodule TaamolWeb.NewsComponents do
  @moduledoc """
  Building blocks for the news pages: category names/icons, localized times,
  cover images and the article card variants used across the site.
  """
  use TaamolWeb, :html

  alias Taamol.Tracking.Article

  # ---------------------------------------------------------------------------
  # Categories
  # ---------------------------------------------------------------------------

  @doc "All categories, in navigation order."
  def categories, do: Article.categories()

  @doc "Looks up a category from a URL param without creating atoms."
  def category_from_param(param) when is_binary(param) do
    Enum.find(categories(), &(Atom.to_string(&1) == param))
  end

  def category_from_param(_), do: nil

  @doc "Translated category name."
  def category_name(:community), do: gettext("Community")
  def category_name(:religion), do: gettext("Religion")
  def category_name(:sweden), do: gettext("Sweden")
  def category_name(:world), do: gettext("World")
  def category_name(:society), do: gettext("Society")
  def category_name(:culture), do: gettext("Culture")
  def category_name(:education), do: gettext("Education")
  def category_name(:youth), do: gettext("Youth")
  def category_name(:health), do: gettext("Health")
  def category_name(:sport), do: gettext("Sport")

  @doc "Heroicon name for a category."
  def category_icon(:community), do: "hero-user-group"
  def category_icon(:religion), do: "hero-moon"
  def category_icon(:sweden), do: "hero-map-pin"
  def category_icon(:world), do: "hero-globe-europe-africa"
  def category_icon(:society), do: "hero-building-library"
  def category_icon(:culture), do: "hero-musical-note"
  def category_icon(:education), do: "hero-academic-cap"
  def category_icon(:youth), do: "hero-sparkles"
  def category_icon(:health), do: "hero-heart"
  def category_icon(:sport), do: "hero-trophy"

  # ---------------------------------------------------------------------------
  # Formatting
  # ---------------------------------------------------------------------------

  @doc "\"5 min ago\", \"2 h ago\", \"Yesterday\" or a date for older articles."
  def relative_time(nil), do: ""

  def relative_time(%DateTime{} = datetime) do
    minutes = div(max(DateTime.diff(DateTime.utc_now(), datetime), 0), 60)

    cond do
      minutes < 1 -> gettext("Just now")
      minutes < 60 -> ngettext("%{count} min ago", "%{count} min ago", minutes)
      minutes < 24 * 60 -> ngettext("%{count} hour ago", "%{count} hours ago", div(minutes, 60))
      minutes < 48 * 60 -> gettext("Yesterday")
      true -> format_date(datetime)
    end
  end

  @doc "\"19 May 2026\", or with `time: true` \"19 May 2026, 09:15\" (UTC)."
  def format_date(datetime, opts \\ [])
  def format_date(nil, _opts), do: ""

  def format_date(%DateTime{} = datetime, opts) do
    date = "#{datetime.day} #{month_name(datetime.month)} #{datetime.year}"

    if Keyword.get(opts, :time, false),
      do: "#{date}, #{Calendar.strftime(datetime, "%H:%M")}",
      else: date
  end

  @doc "Translated month name."
  def month_name(1), do: gettext("January")
  def month_name(2), do: gettext("February")
  def month_name(3), do: gettext("March")
  def month_name(4), do: gettext("April")
  def month_name(5), do: gettext("May")
  def month_name(6), do: gettext("June")
  def month_name(7), do: gettext("July")
  def month_name(8), do: gettext("August")
  def month_name(9), do: gettext("September")
  def month_name(10), do: gettext("October")
  def month_name(11), do: gettext("November")
  def month_name(12), do: gettext("December")

  @doc "Abbreviated month name (\"Nov\")."
  def month_short(month), do: month |> month_name() |> String.slice(0, 3)

  @doc "Groups thousands with a thin space: 12540 -> \"12 540\"."
  def format_count(nil), do: "0"

  def format_count(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(" ", &Enum.join/1)
    |> String.reverse()
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :article, :map, required: true
  attr :class, :string, default: nil
  attr :sizes, :string, default: "(min-width: 1024px) 40vw, 100vw"
  attr :loading, :string, default: "lazy", values: ~w(lazy eager)

  @doc "Cover image, or a tinted placeholder with the category icon."
  def cover(assigns) do
    ~H"""
    <%= if @article.cover_image_url do %>
      <img
        src={@article.cover_image_url}
        alt=""
        loading={@loading}
        decoding="async"
        sizes={@sizes}
        class={["bg-base-200 object-cover", @class]}
      />
    <% else %>
      <div class={["grid place-items-center bg-primary/10 text-primary", @class]}>
        <.icon name={category_icon(@article.category)} class="size-1/4 max-h-12 max-w-12 opacity-60" />
      </div>
    <% end %>
    """
  end

  attr :category, :atom, required: true
  attr :class, :string, default: nil

  @doc "Small uppercase category label."
  def category_label(assigns) do
    ~H"""
    <span class={["text-xs font-bold uppercase tracking-wider text-primary", @class]}>
      {category_name(@category)}
    </span>
    """
  end

  attr :article, :map, required: true
  attr :show_views, :boolean, default: true
  attr :class, :string, default: nil

  @doc "\"2 hours ago · 👁 12 540\"."
  def meta(assigns) do
    ~H"""
    <p class={["flex items-center gap-3 text-xs text-base-content/55", @class]}>
      <time datetime={@article.published && DateTime.to_iso8601(@article.published)}>
        {relative_time(@article.published)}
      </time>
      <span :if={@show_views} class="inline-flex items-center gap-1 tabular-nums">
        <.icon name="hero-eye-micro" class="size-3.5" />
        {format_count(@article.view_count)}
      </span>
    </p>
    """
  end

  attr :article, :map, required: true
  attr :id, :string, required: true

  @doc "The big lead story with the title over the image."
  def hero_card(assigns) do
    ~H"""
    <article
      id={@id}
      class="group relative h-full min-h-[22rem] overflow-hidden rounded-2xl bg-neutral text-white sm:min-h-[26rem]"
    >
      <.link navigate={~p"/articles/#{@article.id}"} class="block h-full">
        <.cover
          article={@article}
          loading="eager"
          class="absolute inset-0 size-full transition duration-500 group-hover:scale-[1.03]"
          sizes="(min-width: 1024px) 45vw, 100vw"
        />
        <div class="absolute inset-0 bg-linear-to-t from-black/85 via-black/35 to-transparent" />
        <div class="absolute inset-x-0 bottom-0 p-5 sm:p-7">
          <span class="inline-block rounded bg-primary px-2 py-1 text-[10px] font-bold uppercase tracking-wider text-primary-content">
            {if(@article.featured, do: gettext("Top story"), else: category_name(@article.category))}
          </span>
          <h2
            dir="auto"
            class="mt-3 text-2xl font-bold leading-tight tracking-tight text-balance sm:text-3xl"
          >
            {@article.title}
          </h2>
          <p
            :if={@article.summary}
            dir="auto"
            class="mt-2 line-clamp-2 text-sm text-white/80 sm:text-base"
          >
            {@article.summary}
          </p>
          <.meta article={@article} class="mt-4 !text-white/75" />
        </div>
      </.link>
    </article>
    """
  end

  attr :article, :map, required: true
  attr :id, :string, required: true
  attr :show_views, :boolean, default: false
  attr :show_category, :boolean, default: false
  attr :class, :string, default: nil

  @doc "Thumbnail on the side, title and time: for lists and rails."
  def compact_card(assigns) do
    ~H"""
    <article id={@id} class={["group", @class]}>
      <.link navigate={~p"/articles/#{@article.id}"} class="flex items-start gap-4 py-3">
        <.cover
          article={@article}
          class="aspect-[4/3] w-24 shrink-0 rounded-lg sm:w-28"
          sizes="112px"
        />
        <div class="min-w-0 flex-1">
          <.category_label :if={@show_category} category={@article.category} />
          <h3
            dir="auto"
            class="line-clamp-3 text-[15px] font-semibold leading-snug transition-colors group-hover:text-primary sm:text-base"
          >
            {@article.title}
          </h3>
          <.meta article={@article} show_views={@show_views} class="mt-1.5" />
        </div>
      </.link>
    </article>
    """
  end

  attr :article, :map, required: true
  attr :id, :string, required: true

  attr :class, :string, default: nil

  @doc "Image with category, title, meta and summary: for the main news feed."
  def feed_card(assigns) do
    ~H"""
    <article id={@id} class={["group", @class]}>
      <.link
        navigate={~p"/articles/#{@article.id}"}
        class="grid grid-cols-[6.5rem_minmax(0,1fr)] gap-4 py-4 sm:grid-cols-[minmax(0,0.9fr)_minmax(0,1fr)] sm:gap-5"
      >
        <.cover
          article={@article}
          class="aspect-[4/3] w-full rounded-lg transition duration-300 group-hover:opacity-90 sm:aspect-[16/10] sm:rounded-xl"
          sizes="(min-width: 640px) 22rem, 104px"
        />
        <div class="min-w-0">
          <.category_label category={@article.category} />
          <h3
            dir="auto"
            class="mt-1 line-clamp-3 text-[15px] font-bold leading-snug tracking-tight transition-colors group-hover:text-primary sm:line-clamp-2 sm:text-lg"
          >
            {@article.title}
          </h3>
          <p
            :if={@article.summary}
            dir="auto"
            class="mt-2 line-clamp-2 text-sm leading-relaxed text-base-content/65 max-sm:hidden"
          >
            {@article.summary}
          </p>
          <.meta article={@article} class="mt-2" />
        </div>
      </.link>
    </article>
    """
  end

  attr :categories, :list, default: nil
  attr :active, :any, default: nil
  attr :all_path, :string, required: true
  attr :id, :string, required: true
  attr :path, :any, required: true, doc: "fun category -> path"
  attr :patch, :boolean, default: true

  @doc """
  Category filter as chips ("All · Community · World …"), horizontally
  scrollable, e.g. the News section on the start page.
  """
  def category_tabs(assigns) do
    assigns = assign_new(assigns, :items, fn -> assigns.categories || categories() end)

    ~H"""
    <.chip_row id={@id} class="-mx-4 px-4 sm:mx-0 sm:px-0">
      <li>
        <.chip patch={@patch} to={@all_path} icon="hero-squares-2x2" active={is_nil(@active)}>
          {gettext("All")}
        </.chip>
      </li>
      <li :for={category <- @items}>
        <.chip
          patch={@patch}
          to={@path.(category)}
          icon={category_icon(category)}
          active={@active == category}
        >
          {category_name(category)}
        </.chip>
      </li>
    </.chip_row>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  @doc """
  A horizontally scrolling row of `chip/1`s with faded edges. The active chip
  is scrolled into view (e.g. "Sport" at the far end of the list).
  """
  def chip_row(assigns) do
    ~H"""
    <nav
      id={@id}
      phx-hook=".ScrollActiveIntoView"
      class={[
        "overflow-x-auto py-1 [mask-image:linear-gradient(to_right,transparent,black_0.75rem,black_calc(100%-1.5rem),transparent)] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden",
        @class
      ]}
    >
      <ul class="flex min-w-max gap-1.5 pe-4">
        {render_slot(@inner_block)}
      </ul>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollActiveIntoView">
        export default {
          mounted() { this.reveal("instant") },
          updated() { this.reveal("smooth") },
          reveal(behavior) {
            const active = this.el.querySelector("[aria-current=page]")
            if (active) active.scrollIntoView({behavior, block: "nearest", inline: "center"})
          },
        }
      </script>
    </nav>
    """
  end

  attr :to, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  attr :patch, :boolean, default: false, doc: "patch the current LiveView instead of navigating"
  slot :inner_block, required: true

  @doc "A compact pill with an icon; filled with the primary colour when active."
  def chip(assigns) do
    ~H"""
    <.link
      patch={@patch && @to}
      navigate={!@patch && @to}
      aria-current={if(@active, do: "page")}
      class="flex items-center gap-1.5 whitespace-nowrap rounded-full border border-base-300 bg-base-100 py-1 pe-3 ps-1 text-sm font-medium text-base-content/75 transition hover:border-primary/40 active:scale-95 aria-[current=page]:border-primary aria-[current=page]:bg-primary aria-[current=page]:text-primary-content"
    >
      <span class={[
        "grid size-6 place-items-center rounded-full",
        if(@active, do: "bg-primary-content/20", else: "bg-primary/10 text-primary")
      ]}>
        <.icon name={@icon} class="size-3.5" />
      </span>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :upcoming, :list,
    default: nil,
    doc: "upcoming calendar entries (`Taamol.Events.upcoming/1`)"

  slot :inner_block, doc: "extra cards below the prayer times (e.g. most read)"

  @doc """
  The right-hand column on wide screens: prayer times, upcoming calendar
  entries and any extra cards.
  """
  def rail(assigns) do
    ~H"""
    <aside class="hidden xl:block">
      <div class="sticky top-28 space-y-4">
        <section
          id="rail-prayer-card"
          class="rounded-2xl border border-base-300 bg-base-100 p-2"
        >
          <h2 class="mb-2 flex items-center gap-2 px-2 pt-2 text-sm font-semibold">
            <span class="grid size-6 place-items-center rounded-full bg-primary/10 text-primary">
              <.icon name="hero-moon-micro" class="size-4" />
            </span>
            {gettext("Prayer times")}
          </h2>
          <Layouts.prayer_times id="rail-prayer-times" variant={:card} />
        </section>
        <TaamolWeb.CalendarComponents.upcoming_card
          :if={@upcoming}
          id="rail-upcoming"
          entries={@upcoming}
        />
        {render_slot(@inner_block)}
      </div>
    </aside>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  @doc "A bordered sidebar card with a heading."
  def side_card(assigns) do
    ~H"""
    <section id={@id} class={["rounded-2xl border border-base-300 bg-base-100 p-4", @class]}>
      <h2 class="text-sm font-semibold">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end
end
