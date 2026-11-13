defmodule TaamolWeb.CalendarComponents do
  @moduledoc """
  Calendar building blocks: translated holiday names, Hijri month and weekday
  names, kind colours, and the "Upcoming" card shown under the prayer times.
  """
  use TaamolWeb, :html

  alias Taamol.Events

  # ---------------------------------------------------------------------------
  # Names
  # ---------------------------------------------------------------------------

  @doc "The display title of a calendar entry."
  def entry_title(%{source: :holiday, key: key}), do: holiday_name(key)
  def entry_title(%{source: :event, event: event}), do: event.title

  # bookings are private: everyone sees only what is booked
  def entry_title(%{source: :booking, booking: booking}),
    do:
      gettext("%{service} (booked)",
        service: TaamolWeb.BookingComponents.service_name(booking.service)
      )

  @doc "Translated holiday name."
  def holiday_name(:islamic_new_year), do: gettext("Islamic New Year")
  def holiday_name(:tasua), do: gettext("Tasu'a")
  def holiday_name(:ashura), do: gettext("Ashura, martyrdom of Imam Hussain")
  def holiday_name(:martyrdom_imam_sajjad), do: gettext("Martyrdom of Imam Sajjad")
  def holiday_name(:birth_imam_kadhim), do: gettext("Birth of Imam Musa al-Kadhim")
  def holiday_name(:arbaeen), do: gettext("Arbaeen")

  def holiday_name(:demise_prophet_imam_hasan),
    do: gettext("Demise of the Prophet and martyrdom of Imam Hasan")

  def holiday_name(:martyrdom_imam_reza), do: gettext("Martyrdom of Imam Reza")
  def holiday_name(:martyrdom_imam_askari), do: gettext("Martyrdom of Imam Hasan al-Askari")

  def holiday_name(:birth_prophet_imam_sadiq),
    do: gettext("Birth of the Prophet and Imam Ja'far al-Sadiq")

  def holiday_name(:birth_imam_askari), do: gettext("Birth of Imam Hasan al-Askari")
  def holiday_name(:death_lady_masumeh), do: gettext("Death of Lady Fatima Masumeh")
  def holiday_name(:birth_lady_zaynab), do: gettext("Birth of Lady Zaynab")
  def holiday_name(:fatimiyya_first), do: gettext("Fatimiyya (first narration)")
  def holiday_name(:martyrdom_lady_fatima), do: gettext("Martyrdom of Lady Fatima al-Zahra")
  def holiday_name(:birth_lady_fatima), do: gettext("Birth of Lady Fatima al-Zahra")
  def holiday_name(:birth_imam_baqir), do: gettext("Birth of Imam Muhammad al-Baqir")
  def holiday_name(:martyrdom_imam_hadi), do: gettext("Martyrdom of Imam Ali al-Hadi")
  def holiday_name(:birth_imam_jawad), do: gettext("Birth of Imam Muhammad al-Jawad")
  def holiday_name(:birth_imam_ali), do: gettext("Birth of Imam Ali")
  def holiday_name(:death_lady_zaynab), do: gettext("Death of Lady Zaynab")
  def holiday_name(:martyrdom_imam_kadhim), do: gettext("Martyrdom of Imam Musa al-Kadhim")
  def holiday_name(:mabath), do: gettext("Mab'ath, the Prophet's mission")
  def holiday_name(:birth_imam_hussain), do: gettext("Birth of Imam Hussain")
  def holiday_name(:birth_abbas), do: gettext("Birth of Abbas ibn Ali")
  def holiday_name(:birth_imam_sajjad), do: gettext("Birth of Imam Sajjad")
  def holiday_name(:birth_ali_akbar), do: gettext("Birth of Ali al-Akbar")
  def holiday_name(:birth_imam_mahdi), do: gettext("Birth of Imam Mahdi")
  def holiday_name(:ramadan_begins), do: gettext("First day of Ramadan")
  def holiday_name(:death_lady_khadija), do: gettext("Death of Lady Khadija")
  def holiday_name(:birth_imam_hasan), do: gettext("Birth of Imam Hasan")
  def holiday_name(:qadr_night_19), do: gettext("Night of Qadr (19th)")
  def holiday_name(:martyrdom_imam_ali), do: gettext("Martyrdom of Imam Ali, Night of Qadr")
  def holiday_name(:qadr_night_23), do: gettext("Night of Qadr (23rd)")
  def holiday_name(:eid_al_fitr), do: gettext("Eid al-Fitr")
  def holiday_name(:martyrdom_imam_sadiq), do: gettext("Martyrdom of Imam Ja'far al-Sadiq")
  def holiday_name(:birth_lady_masumeh), do: gettext("Birth of Lady Fatima Masumeh")
  def holiday_name(:birth_imam_reza), do: gettext("Birth of Imam Reza")
  def holiday_name(:martyrdom_imam_jawad), do: gettext("Martyrdom of Imam Muhammad al-Jawad")

  def holiday_name(:marriage_imam_ali_lady_fatima),
    do: gettext("Marriage of Imam Ali and Lady Fatima")

  def holiday_name(:martyrdom_imam_baqir), do: gettext("Martyrdom of Imam Muhammad al-Baqir")
  def holiday_name(:day_of_arafah), do: gettext("Day of Arafah")
  def holiday_name(:eid_al_adha), do: gettext("Eid al-Adha")
  def holiday_name(:birth_imam_hadi), do: gettext("Birth of Imam Ali al-Hadi")
  def holiday_name(:eid_al_ghadir), do: gettext("Eid al-Ghadir")
  def holiday_name(:eid_al_mubahala), do: gettext("Eid al-Mubahala")

  @doc "Translated name of an entry kind."
  def kind_name(:community), do: gettext("Taamol event")
  def kind_name(:celebration), do: gettext("Celebration")
  def kind_name(:mourning), do: gettext("Mourning")
  def kind_name(:observance), do: gettext("Observance")
  def kind_name(:booking), do: gettext("Booking")

  @doc "Hijri month name."
  def hijri_month_name(1), do: gettext("Muharram")
  def hijri_month_name(2), do: gettext("Safar")
  def hijri_month_name(3), do: gettext("Rabi al-Awwal")
  def hijri_month_name(4), do: gettext("Rabi al-Thani")
  def hijri_month_name(5), do: gettext("Jumada al-Ula")
  def hijri_month_name(6), do: gettext("Jumada al-Thani")
  def hijri_month_name(7), do: gettext("Rajab")
  def hijri_month_name(8), do: gettext("Shaban")
  def hijri_month_name(9), do: gettext("Ramadan")
  def hijri_month_name(10), do: gettext("Shawwal")
  def hijri_month_name(11), do: gettext("Dhu al-Qadah")
  def hijri_month_name(12), do: gettext("Dhu al-Hijjah")

  @doc "\"2 Jumada al-Thani 1448\"."
  def format_hijri(%Date{} = date) do
    {year, month, day} = Events.hijri(date)
    "#{day} #{hijri_month_name(month)} #{year}"
  end

  @doc "Short weekday name, 1 = Monday … 7 = Sunday."
  def weekday_short(1), do: gettext("Mon")
  def weekday_short(2), do: gettext("Tue")
  def weekday_short(3), do: gettext("Wed")
  def weekday_short(4), do: gettext("Thu")
  def weekday_short(5), do: gettext("Fri")
  def weekday_short(6), do: gettext("Sat")
  def weekday_short(7), do: gettext("Sun")

  @doc "Weeks start on Saturday in Persian, Monday otherwise."
  def week_start do
    if Gettext.get_locale(TaamolWeb.Gettext) == "fa", do: 6, else: 1
  end

  @doc "\"18:30\" or \"18:30–20:00\" for timed events, nil for all-day ones."
  def entry_time(%{all_day: true}), do: nil
  def entry_time(%{starts_at: nil}), do: nil

  def entry_time(%{starts_at: starts_at, ends_at: ends_at}) do
    start = Calendar.strftime(starts_at, "%H:%M")

    if ends_at && NaiveDateTime.to_date(ends_at) == NaiveDateTime.to_date(starts_at),
      do: "#{start}–#{Calendar.strftime(ends_at, "%H:%M")}",
      else: start
  end

  # ---------------------------------------------------------------------------
  # Colours (spelled out in full so Tailwind can find them)
  # ---------------------------------------------------------------------------

  @doc "Dot colour for a kind."
  def kind_dot(:community), do: "bg-primary"
  def kind_dot(:celebration), do: "bg-emerald-500"
  def kind_dot(:mourning), do: "bg-base-content/70"
  def kind_dot(:observance), do: "bg-sky-500"
  def kind_dot(:booking), do: "bg-violet-500"

  @doc "Chip colours for a kind."
  def kind_chip(:community), do: "bg-primary/12 text-primary"
  def kind_chip(:celebration), do: "bg-emerald-500/12 text-emerald-700 dark:text-emerald-400"
  def kind_chip(:mourning), do: "bg-base-content/8 text-base-content/80"
  def kind_chip(:observance), do: "bg-sky-500/12 text-sky-700 dark:text-sky-400"
  def kind_chip(:booking), do: "bg-violet-500/12 text-violet-700 dark:text-violet-400"

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :kind, :atom, required: true
  attr :class, :string, default: "size-2"

  def kind_dot_badge(assigns) do
    ~H"""
    <span class={["inline-block shrink-0 rounded-full", kind_dot(@kind), @class]} />
    """
  end

  attr :id, :string, required: true
  attr :entries, :list, required: true
  attr :class, :string, default: nil

  @doc "The \"Upcoming\" list of holidays and community events."
  def upcoming_card(assigns) do
    ~H"""
    <section id={@id} class={["rounded-2xl border border-base-300 bg-base-100 p-4", @class]}>
      <div class="flex items-center justify-between gap-2">
        <h2 class="flex items-center gap-2 text-sm font-semibold">
          <.icon name="hero-calendar-days" class="size-4 text-primary" />
          {gettext("Upcoming")}
        </h2>
        <.link
          navigate={~p"/calendar"}
          class="text-xs font-medium text-primary transition hover:opacity-75"
        >
          {gettext("Calendar")}
        </.link>
      </div>

      <p :if={@entries == []} class="mt-3 text-xs text-base-content/55">
        {gettext("Nothing coming up.")}
      </p>

      <ol class="mt-2 divide-y divide-base-300/70">
        <li :for={entry <- @entries}>
          <.link
            navigate={~p"/calendar?#{[date: Date.to_iso8601(entry.first_day)]}"}
            class="group flex items-start gap-3 py-2.5"
          >
            <span class="grid w-11 shrink-0 place-items-center rounded-xl border border-base-300 py-1 leading-none">
              <span class="text-base font-bold tabular-nums">{entry.first_day.day}</span>
              <span class="mt-0.5 text-[10px] uppercase text-base-content/55">
                {TaamolWeb.NewsComponents.month_short(entry.first_day.month)}
              </span>
            </span>
            <span class="min-w-0 flex-1">
              <span class="flex items-start gap-1.5">
                <.kind_dot_badge kind={entry.kind} class="mt-1.5 size-1.5" />
                <span
                  dir="auto"
                  class="line-clamp-2 text-[13px] font-medium leading-snug transition-colors group-hover:text-primary"
                >
                  {entry_title(entry)}
                </span>
              </span>
              <span class="mt-0.5 block ps-3 text-[11px] text-base-content/55">
                {format_hijri(entry.first_day)}<span :if={entry_time(entry)}> · {entry_time(entry)}</span>
              </span>
            </span>
          </.link>
        </li>
      </ol>
    </section>
    """
  end
end
