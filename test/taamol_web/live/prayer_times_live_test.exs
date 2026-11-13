defmodule TaamolWeb.PrayerTimesLiveTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures

  alias Taamol.{Accounts, PrayTime}

  test "visitors can calculate using their own settings but cannot save", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/prayer-times")

    assert has_element?(view, "#prayer-settings-form")
    refute has_element?(view, "#save-prayer-settings")

    for {section, icon} <- [
          {"prayer-location", "hero-map-pin"},
          {"prayer-calculation", "hero-cog-6-tooth"},
          {"prayer-tuning", "hero-adjustments-horizontal"},
          {"prayer-results", "hero-clock"}
        ] do
      assert has_element?(view, "##{section} h2")
      assert has_element?(view, "##{section} .#{icon}")
      assert has_element?(view, "##{section} p")
    end

    assert has_element?(view, "#prayer-calculation #site-prayer-preset")
    assert has_element?(view, "#selected-city", "Växjö")
    assert has_element?(view, "#prayer_method option[value=Tehran][selected]")
    assert has_element?(view, "#prayer_high_lats option[value=None][selected]")
    assert has_element?(view, "#prayer_rounding option[value=down][selected]")
    assert has_element?(view, "#prayer_tune_sunrise[value='0.07'][step=any]")
    assert has_element?(view, "#prayer_tune_dhuhr[value='0.15']")
    assert has_element?(view, "#prayer_tune_sunset[value='1.15']")
    assert has_element?(view, "#prayer_tune_maghrib[value='1.08']")
    assert has_element?(view, "label[for='prayer_tune_fajr']")
    assert has_element?(view, "#prayer_tune_fajr.h-10[type=number]")

    assert has_element?(
             view,
             "#prayer_tune_fajr-stepper[phx-hook=NumberStepper] button[data-step='1']"
           )

    assert has_element?(view, "#prayer-tuning .hero-clock")
    assert has_element?(view, "#city-search .hero-magnifying-glass")

    view |> element("#manual-location") |> render_click()

    view
    |> form("#prayer-settings-form",
      prayer: %{
        latitude: "59.33",
        longitude: "18.07",
        date: "2026-11-12",
        utc_offset: "1",
        method: "ISNA",
        tune_fajr: "5"
      }
    )
    |> render_change()

    expected =
      PrayTime.new("ISNA")
      |> PrayTime.location({59.33, 18.07})
      |> PrayTime.adjust(
        utc_offset: 60,
        high_lats: "None",
        rounding: "down",
        tune: %{fajr: 5, sunrise: 0.07, dhuhr: 0.15, sunset: 1.15, maghrib: 1.08}
      )
      |> PrayTime.times(~D[2026-11-12])

    assert has_element?(view, "#result-fajr", expected.fajr)
    render_hook(view, "save", %{"prayer" => %{}})
    assert has_element?(view, "#flash-error")
  end

  test "saved settings are restored for the account and remain private", %{conn: conn} do
    user = user_fixture()
    other = user_fixture()
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, ~p"/prayer-times")
    view |> element("#manual-location") |> render_click()

    view
    |> form("#prayer-settings-form",
      prayer: %{
        latitude: "35.7",
        longitude: "51.4",
        utc_offset: "3.5",
        date: "2026-11-12",
        method: "Tehran",
        fajr: "17",
        isha: "90 min",
        asr: "Hanafi",
        high_lats: "OneSeventh",
        tune_fajr: "7.25"
      }
    )
    |> render_submit()

    settings = Accounts.get_user!(user.id).prayer_settings
    assert settings["method"] == "Tehran"
    assert settings["fajr"] == 17.0
    assert settings["isha"] == "90 min"
    assert settings["tune_fajr"] == 7.25
    refute Map.has_key?(settings, "date")
    assert Accounts.get_user!(other.id).prayer_settings == nil

    {:ok, restored, _} = live(conn, ~p"/prayer-times")
    assert has_element?(restored, "#prayer_method option[value=Tehran][selected]")
    assert has_element?(restored, "#prayer_latitude[value='35.7']")
    assert has_element?(restored, "#prayer_tune_fajr[value='7.25']")
    assert has_element?(restored, "#prayer_date[value='#{Date.utc_today()}']")

    {:ok, account, _} = live(conn, ~p"/users/settings")
    assert has_element?(account, "#account-prayer-settings-link[href='/prayer-times']")
  end

  test "invalid settings cannot be calculated or saved", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _} = conn |> log_in_user(user) |> live(~p"/prayer-times")

    view
    |> element("#prayer-settings-form")
    |> render_submit(%{
      "prayer" => %{
        "latitude" => "90",
        "isha" => "999 min",
        "asr" => String.duplicate("9", 400)
      }
    })

    assert has_element?(view, "#prayer-invalid")
    assert Accounts.get_user!(user.id).prayer_settings == nil
  end

  test "searches for a city, calculates its times, and saves the location", %{conn: conn} do
    Req.Test.stub(Taamol.CitySearch, fn stub_conn ->
      assert stub_conn.query_params["name"] == "Stockholm"

      Req.Test.json(stub_conn, %{
        results: [
          %{
            id: 2_673_730,
            name: "Stockholm",
            admin1: "Stockholm County",
            country: "Sweden",
            latitude: 59.32938,
            longitude: 18.06871,
            timezone: "Europe/Stockholm"
          }
        ]
      })
    end)

    user = user_fixture()
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, ~p"/prayer-times")

    search_city(view, "Stockholm")
    assert has_element?(view, "#select-city-2673730", "Stockholm")

    view |> element("#select-city-2673730") |> render_click()
    assert has_element?(view, "#selected-city", "Europe/Stockholm")
    assert has_element?(view, "#prayer_latitude[value='59.32938']")
    assert has_element?(view, "#city-time-fajr[data-timezone='Europe/Stockholm']")
    refute has_element?(view, "#prayer_utc_offset[type=number]")

    render_hook(view, "city-today", %{"timezone" => "Europe/Stockholm", "date" => "2026-03-29"})
    assert has_element?(view, "#prayer_date[value='2026-03-29']")

    view |> form("#prayer-settings-form") |> render_submit()

    assert %{"city" => "Stockholm, Stockholm County, Sweden", "timezone" => "Europe/Stockholm"} =
             Accounts.get_user!(user.id).prayer_settings

    {:ok, restored, _} = live(conn, ~p"/prayer-times")
    assert has_element?(restored, "#selected-city", "Stockholm")
    assert has_element?(restored, "#city-time-fajr[data-timezone='Europe/Stockholm']")

    restored |> element("#manual-location") |> render_click()
    refute has_element?(restored, "#selected-city")
    assert has_element?(restored, "#prayer_utc_offset[type=number]")

    {:ok, restored_again, _} = live(conn, ~p"/prayer-times")

    restored_again
    |> element("#prayer-settings-form")
    |> render_change(%{
      "_target" => ["prayer", "latitude"],
      "prayer" => %{
        "latitude" => "60",
        "city" => "Stockholm",
        "timezone" => "Europe/Stockholm"
      }
    })

    refute has_element?(restored_again, "#selected-city")
    assert has_element?(restored_again, "#prayer_utc_offset[type=number]")
  end

  test "an explicitly chosen date is not replaced by the city's current date", %{conn: conn} do
    Req.Test.stub(Taamol.CitySearch, fn stub_conn ->
      Req.Test.json(stub_conn, %{
        results: [
          %{
            id: 1,
            name: "Stockholm",
            latitude: 59.33,
            longitude: 18.07,
            timezone: "Europe/Stockholm"
          }
        ]
      })
    end)

    {:ok, view, _} = live(conn, ~p"/prayer-times")

    view
    |> element("#prayer-settings-form")
    |> render_change(%{"_target" => ["prayer", "date"], "prayer" => %{"date" => "2026-03-29"}})

    search_city(view, "Stockholm")
    view |> element("#select-city-1") |> render_click()
    render_hook(view, "city-today", %{"timezone" => "Europe/Stockholm", "date" => "2026-11-13"})

    assert has_element?(view, "#prayer_date[value='2026-03-29']")
  end

  test "city search reports empty results and service errors", %{conn: conn} do
    Req.Test.stub(Taamol.CitySearch, fn stub_conn -> Req.Test.json(stub_conn, %{}) end)
    {:ok, view, _} = live(conn, ~p"/prayer-times")

    search_city(view, "Nowhere")
    assert has_element?(view, "#city-search-empty")

    Req.Test.stub(Taamol.CitySearch, fn stub_conn -> Plug.Conn.send_resp(stub_conn, 503, "") end)
    search_city(view, "Stockholm")
    assert has_element?(view, "#city-search-error")
    refute has_element?(view, "#city-search-empty")
  end

  test "autocomplete waits for three characters and clears stale results", %{conn: conn} do
    Req.Test.stub(Taamol.CitySearch, fn stub_conn ->
      Req.Test.json(stub_conn, %{
        results: [
          %{
            id: 1,
            name: "Stockholm",
            latitude: 59.33,
            longitude: 18.07,
            timezone: "Europe/Stockholm"
          }
        ]
      })
    end)

    {:ok, view, _} = live(conn, ~p"/prayer-times")
    assert has_element?(view, "#prayer-location #city-search-input[phx-debounce='350']")
    assert has_element?(view, "#city-search-input.w-full")
    assert has_element?(view, "#prayer_date.w-full")
    assert has_element?(view, "#prayer_latitude.w-full")
    assert has_element?(view, "#prayer_method.w-full")
    assert has_element?(view, "#prayer_tune_fajr.w-full")
    assert has_element?(view, "#city-search-input[aria-expanded='false']")

    search_city(view, "St")
    assert has_element?(view, "#city-search-input[aria-expanded='false']")
    refute has_element?(view, "#select-city-1")

    search_city(view, "Sto")
    assert has_element?(view, "#city-search-input[aria-expanded='true']")
    assert has_element?(view, "#select-city-1")

    render_hook(view, "city-query-changed", %{"query" => "St"})
    assert has_element?(view, "#city-search-input[aria-expanded='false']")
    refute has_element?(view, "#select-city-1")

    # A delayed event for an earlier query must not reopen the results.
    view
    |> element("#city-search-input")
    |> render_change(%{"city_search" => %{"query" => "Sto"}})

    render_async(view)
    refute has_element?(view, "#select-city-1")
    assert has_element?(view, "#city-search-input[aria-expanded='false']")
  end

  defp search_city(view, query) do
    render_hook(view, "city-query-changed", %{"query" => query})

    view
    |> element("#city-search-input")
    |> render_change(%{"city_search" => %{"query" => query}})

    render_async(view)
  end
end
