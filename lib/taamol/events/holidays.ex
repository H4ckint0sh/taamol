defmodule Taamol.Events.Holidays do
  @moduledoc """
  Shia Muslim holidays and important historical days, defined on the Hijri
  calendar and converted to Gregorian dates on demand (see
  `Taamol.Events.Hijri`). Names are translated in the web layer
  (`TaamolWeb.CalendarComponents.holiday_name/1`).

  Kinds:

    * `:celebration` - Eids, births (wiladat)
    * `:mourning` - martyrdoms and deaths (shahadat / wafat)
    * `:observance` - other notable days and nights

  Where traditions differ, the date most commonly observed in Shia calendars
  (Iran/Iraq) is used. `day: :last` means the last day of the month.
  """

  alias Taamol.Events.Hijri

  @holidays [
    # 1 Muharram
    {:islamic_new_year, 1, 1, :observance},
    {:tasua, 1, 9, :mourning},
    {:ashura, 1, 10, :mourning},
    {:martyrdom_imam_sajjad, 1, 25, :mourning},
    # 2 Safar
    {:birth_imam_kadhim, 2, 7, :celebration},
    {:arbaeen, 2, 20, :mourning},
    {:demise_prophet_imam_hasan, 2, 28, :mourning},
    {:martyrdom_imam_reza, 2, :last, :mourning},
    # 3 Rabi al-Awwal
    {:martyrdom_imam_askari, 3, 8, :mourning},
    {:birth_prophet_imam_sadiq, 3, 17, :celebration},
    # 4 Rabi al-Thani
    {:birth_imam_askari, 4, 8, :celebration},
    {:death_lady_masumeh, 4, 10, :mourning},
    # 5 Jumada al-Ula
    {:birth_lady_zaynab, 5, 5, :celebration},
    {:fatimiyya_first, 5, 13, :mourning},
    # 6 Jumada al-Thani
    {:martyrdom_lady_fatima, 6, 3, :mourning},
    {:birth_lady_fatima, 6, 20, :celebration},
    # 7 Rajab
    {:birth_imam_baqir, 7, 1, :celebration},
    {:martyrdom_imam_hadi, 7, 3, :mourning},
    {:birth_imam_jawad, 7, 10, :celebration},
    {:birth_imam_ali, 7, 13, :celebration},
    {:death_lady_zaynab, 7, 15, :mourning},
    {:martyrdom_imam_kadhim, 7, 25, :mourning},
    {:mabath, 7, 27, :celebration},
    # 8 Shaban
    {:birth_imam_hussain, 8, 3, :celebration},
    {:birth_abbas, 8, 4, :celebration},
    {:birth_imam_sajjad, 8, 5, :celebration},
    {:birth_ali_akbar, 8, 11, :celebration},
    {:birth_imam_mahdi, 8, 15, :celebration},
    # 9 Ramadan
    {:ramadan_begins, 9, 1, :observance},
    {:death_lady_khadija, 9, 10, :mourning},
    {:birth_imam_hasan, 9, 15, :celebration},
    {:qadr_night_19, 9, 19, :observance},
    {:martyrdom_imam_ali, 9, 21, :mourning},
    {:qadr_night_23, 9, 23, :observance},
    # 10 Shawwal
    {:eid_al_fitr, 10, 1, :celebration},
    {:martyrdom_imam_sadiq, 10, 25, :mourning},
    # 11 Dhu al-Qadah
    {:birth_lady_masumeh, 11, 1, :celebration},
    {:birth_imam_reza, 11, 11, :celebration},
    {:martyrdom_imam_jawad, 11, :last, :mourning},
    # 12 Dhu al-Hijjah
    {:marriage_imam_ali_lady_fatima, 12, 1, :celebration},
    {:martyrdom_imam_baqir, 12, 7, :mourning},
    {:day_of_arafah, 12, 9, :observance},
    {:eid_al_adha, 12, 10, :celebration},
    {:birth_imam_hadi, 12, 15, :celebration},
    {:eid_al_ghadir, 12, 18, :celebration},
    {:eid_al_mubahala, 12, 24, :celebration}
  ]

  @doc "All holiday keys."
  def keys, do: Enum.map(@holidays, &elem(&1, 0))

  @doc """
  Holidays falling between two Gregorian dates (inclusive), as maps:
  `%{key: atom, kind: atom, date: Date.t(), hijri: {y, m, d}}`, sorted by date.
  """
  def between(%Date{} = from, %Date{} = to) do
    {first_year, _, _} = Taamol.Events.Hijri.from_date(from)
    {last_year, _, _} = Hijri.from_date(to)

    for year <- first_year..last_year,
        {key, month, day, kind} <- @holidays,
        day = if(day == :last, do: Hijri.month_length(year, month), else: day),
        date = Hijri.to_date(year, month, day),
        Date.compare(date, from) != :lt and Date.compare(date, to) != :gt do
      %{key: key, kind: kind, date: date, hijri: {year, month, day}}
    end
    |> Enum.sort_by(& &1.date, Date)
  end
end
