defmodule Taamol.PrayerSettingsTest do
  use ExUnit.Case, async: true

  alias Taamol.{PrayTime, PrayerSettings}

  test "custom calculation settings and tuning are applied to the selected method" do
    attrs = %{
      "method" => "Makkah",
      "latitude" => "35.7",
      "longitude" => "51.4",
      "utc_offset" => "3.5",
      "date" => "2026-03-10",
      "fajr" => "16",
      "isha" => "75 min",
      "maghrib" => "4",
      "dhuhr" => "3",
      "asr" => "Hanafi",
      "high_lats" => "OneSeventh",
      "midnight" => "Jafari",
      "format" => "x",
      "rounding" => "down",
      "iterations" => "2",
      "tune_sunrise" => "0",
      "tune_dhuhr" => "0",
      "tune_sunset" => "-4",
      "tune_maghrib" => "0",
      "tune_isha" => "8"
    }

    assert {:ok, settings} =
             attrs |> PrayerSettings.changeset() |> Ecto.Changeset.apply_action(:validate)

    actual = settings |> PrayerSettings.calculator() |> PrayTime.times(settings.date)

    expected =
      PrayTime.new("Makkah")
      |> PrayTime.location({35.7, 51.4})
      |> PrayTime.adjust(
        utc_offset: 210,
        fajr: 16.0,
        isha: "75 min",
        maghrib: "4",
        dhuhr: "3 min",
        asr: "Hanafi",
        high_lats: "OneSeventh",
        midnight: "Jafari",
        format: "x",
        rounding: "down",
        iterations: 2,
        tune: %{sunset: -4, isha: 8}
      )
      |> PrayTime.times(~D[2026-03-10])

    assert actual == expected
  end

  test "defaults reproduce the Växjö Tehran schedule with fractional tuning" do
    assert {:ok, settings} =
             %{"date" => "2026-11-13"}
             |> PrayerSettings.changeset()
             |> Ecto.Changeset.apply_action(:validate)

    times =
      settings
      |> PrayerSettings.calculator()
      |> PrayTime.format("x")
      |> PrayTime.times(settings.date)

    for {prayer, expected} <- [
          fajr: "05:24",
          sunrise: "07:36",
          dhuhr: "11:45",
          sunset: "15:53",
          maghrib: "16:24"
        ] do
      local =
        times[prayer]
        |> DateTime.from_unix!(:millisecond)
        |> DateTime.add(3600, :second)
        |> Calendar.strftime("%H:%M")

      assert local == expected
    end

    assert settings.timezone == "Europe/Stockholm"
    assert settings.high_lats == "None"
    assert settings.rounding == "down"
  end

  test "invalid custom values are rejected before calculation" do
    for attrs <- [
          %{"method" => "unknown"},
          %{"high_lats" => "unknown"},
          %{"maghrib" => "181 min"},
          %{"isha" => "91"},
          %{"asr" => "0"},
          %{"iterations" => "0"},
          %{"utc_offset" => "15"}
        ] do
      refute PrayerSettings.changeset(attrs).valid?
    end
  end
end
