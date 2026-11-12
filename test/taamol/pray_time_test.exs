defmodule Taamol.PrayTimeTest do
  use ExUnit.Case, async: true

  alias Taamol.PrayTime

  test "computes ISNA times for Toronto" do
    times =
      PrayTime.new("ISNA")
      |> PrayTime.location({43, -80})
      |> PrayTime.utc_offset(-5)
      |> PrayTime.times(~D[2025-01-01])

    assert times.sunrise == "07:51"
    assert times.dhuhr == "12:24"
    assert times.sunset == "16:56"
  end

  test "returns ordered millisecond timestamps with the \"x\" format" do
    times =
      PrayTime.new()
      |> PrayTime.location({59.33, 18.07})
      |> PrayTime.format("x")
      |> PrayTime.times(~D[2026-06-21])

    ordered = [times.fajr, times.sunrise, times.dhuhr, times.asr, times.maghrib, times.isha]
    assert Enum.all?(ordered, &is_integer/1)
    assert ordered == Enum.sort(ordered)
  end

  test "marks uncomputable times as invalid without high latitude adjustment" do
    times =
      PrayTime.new()
      |> PrayTime.location({78.2, 15.6})
      |> PrayTime.adjust(high_lats: "None")
      |> PrayTime.times(~D[2026-06-21])

    assert times.fajr == PrayTime.invalid_time()
  end
end
