defmodule Taamol.Events.HijriTest do
  # DataCase: the Hijri adjustment is read from the site settings
  use Taamol.DataCase, async: true

  alias Taamol.Events.{Hijri, Holidays}

  # reference dates from ICU's islamic-umalqura calendar
  test "converts Gregorian dates to Umm al-Qura Hijri dates" do
    assert Hijri.from_date(~D[2026-11-12]) == {1448, 6, 2}
    assert Hijri.from_date(~D[2026-06-16]) == {1448, 1, 1}
    assert Hijri.from_date(~D[2027-02-08]) == {1448, 9, 1}
    assert Hijri.from_date(~D[2027-02-20]) == {1448, 9, 13}
  end

  test "converts Hijri dates back to Gregorian" do
    for date <- Date.range(~D[2026-01-01], ~D[2027-12-31]) do
      {y, m, d} = Hijri.from_date(date)
      assert Hijri.to_date(y, m, d) == date
    end
  end

  test "month lengths are 29 or 30 days" do
    for year <- 1446..1450, month <- 1..12 do
      assert Hijri.month_length(year, month) in [29, 30]
    end
  end

  test "falls back to the arithmetic calendar outside the table" do
    {year, month, day} = Hijri.from_date(~D[2010-01-01])
    assert {year, month} == {1431, 1}
    assert day in 14..16
  end

  test "lists holidays between two dates" do
    holidays = Holidays.between(~D[2026-06-01], ~D[2026-07-31])

    assert Enum.any?(
             holidays,
             &match?(%{key: :ashura, date: ~D[2026-06-25], kind: :mourning}, &1)
           )

    assert Enum.all?(holidays, &(Date.compare(&1.date, ~D[2026-06-01]) != :lt))
  end
end
