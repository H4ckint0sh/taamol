defmodule TaamolWeb.PrayerTimeController do
  @moduledoc """
  Computes prayer times for a location and local date using `Taamol.PrayTime`.

  Times are returned as UTC Unix timestamps in milliseconds so the browser can
  format them in the visitor's own timezone and locale. Times that cannot be
  computed (e.g. extreme latitudes) are returned as `null`.
  """
  use TaamolWeb, :controller

  alias Taamol.{PrayTime, PrayerSettings}

  @keys ~w(fajr sunrise dhuhr asr maghrib isha)a

  def index(conn, params) do
    with {:ok, lat} <- parse_coordinate(params["lat"], 90),
         {:ok, lng} <- parse_coordinate(params["lng"], 180),
         {:ok, date} <- parse_date(params["date"]) do
      method = parse_method(params["method"])

      calculator =
        %{"method" => method, "latitude" => lat, "longitude" => lng}
        |> PrayerSettings.changeset()
        |> Ecto.Changeset.apply_action!(:validate)
        |> PrayerSettings.calculator()
        |> PrayTime.format("x")

      today = PrayTime.times(calculator, date)
      tomorrow = PrayTime.times(calculator, Date.add(date, 1))

      json(conn, %{
        method: method,
        date: Date.to_iso8601(date),
        times: Map.new(@keys, &{&1, timestamp(today[&1])}),
        next_fajr: timestamp(tomorrow.fajr)
      })
    else
      {:error, field} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid #{field}"})
    end
  end

  defp parse_coordinate(value, max) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} when max == 90 and abs(number) < 90 -> {:ok, number}
      {number, ""} when max == 180 and abs(number) <= 180 -> {:ok, number}
      _ -> {:error, if(max == 90, do: "lat", else: "lng")}
    end
  end

  defp parse_coordinate(_value, max), do: {:error, if(max == 90, do: "lat", else: "lng")}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, "date"}
    end
  end

  defp parse_date(_value), do: {:error, "date"}

  defp parse_method(method) do
    if is_binary(method) and Map.has_key?(PrayTime.methods(), method),
      do: method,
      else: Taamol.Settings.get(:prayer_method) || "Tehran"
  end

  defp timestamp(value) when is_integer(value), do: value
  defp timestamp(_invalid), do: nil
end
