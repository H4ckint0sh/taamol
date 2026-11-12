defmodule TaamolWeb.PrayerTimeControllerTest do
  use TaamolWeb.ConnCase, async: true

  test "returns prayer timestamps for a location and date", %{conn: conn} do
    conn = get(conn, ~p"/api/prayer-times?lat=59.33&lng=18.07&date=2026-11-12")

    assert %{"method" => "MWL", "date" => "2026-11-12", "times" => times, "next_fajr" => fajr} =
             json_response(conn, 200)

    assert Map.keys(times) == ~w(asr dhuhr fajr isha maghrib sunrise)
    assert Enum.all?(Map.values(times), &is_integer/1)
    assert fajr > times["fajr"]
  end

  test "accepts a known calculation method", %{conn: conn} do
    conn = get(conn, ~p"/api/prayer-times?lat=35.7&lng=51.4&date=2026-11-12&method=Tehran")
    assert %{"method" => "Tehran"} = json_response(conn, 200)
  end

  test "rejects invalid parameters", %{conn: conn} do
    assert %{"error" => "invalid lat"} =
             conn
             |> get(~p"/api/prayer-times?lat=200&lng=18&date=2026-11-12")
             |> json_response(422)

    assert %{"error" => "invalid date"} =
             conn |> get(~p"/api/prayer-times?lat=59&lng=18&date=nope") |> json_response(422)
  end
end
