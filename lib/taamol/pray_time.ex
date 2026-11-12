# pray_time.ex - Prayer Times Calculator (Elixir port of praytime.js v3.2)
# Original: Copyright (c) 2007-2025 Hamid Zarrabi-Zadeh
# Source: https://praytimes.org
# License: MIT

defmodule Taamol.PrayTime do
  @moduledoc """
  Prayer times calculator, ported from praytime.js v3.2 (praytimes.org).

  ## User interface (pipe-friendly, every setter returns a `%PrayTime{}`)

      method(pt, method)        # set calculation method
      location(pt, {lat, lng})  # set location
      timezone(pt, tz)          # set IANA timezone, e.g. "Europe/Stockholm"
      utc_offset(pt, number)    # set UTC offset in minutes or hours
      adjust(pt, params)        # adjust calculation parameters
      tune(pt, mins)            # tune times by given minutes
      format(pt, format)        # "24h", "12h", "12H", "x", "X" or a fun/1
      rounding(pt, method)      # "nearest", "up", "down", "none"
      times(pt, date)           # Date, {y, m, d}, [y, m, d], day offset or ms timestamp

  ## Sample usage

      Taamol.PrayTime.new("ISNA")
      |> Taamol.PrayTime.location({43, -80})
      |> Taamol.PrayTime.utc_offset(-5)
      |> Taamol.PrayTime.times()

  Named timezones other than "UTC"/"Etc/UTC" need a time zone database,
  e.g. `{:tzdata, "~> 1.1"}` plus
  `config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase`
  (or pass one with `adjust(pt, time_zone_database: Tz.TimeZoneDatabase)`).

  Times that cannot be computed (e.g. polar regions with `high_lats: "None"`)
  are returned as `"-----"`, like the JavaScript version.
  """

  defstruct settings: %{}

  @type t :: %__MODULE__{settings: map()}

  @methods %{
    "MWL" => %{fajr: 18, isha: 17},
    "ISNA" => %{fajr: 15, isha: 15},
    "Egypt" => %{fajr: 19.5, isha: 17.5},
    "Makkah" => %{fajr: 18.5, isha: "90 min"},
    "Karachi" => %{fajr: 18, isha: 18},
    "Tehran" => %{fajr: 17.7, maghrib: 4.5, midnight: "Jafari"},
    "Jafari" => %{fajr: 16, maghrib: 4, midnight: "Jafari"},
    "France" => %{fajr: 12, isha: 12},
    "Russia" => %{fajr: 16, isha: 15},
    "Singapore" => %{fajr: 20, isha: 18}
  }

  @method_defaults %{isha: 14, maghrib: "1 min", midnight: "Standard"}

  @default_settings %{
    dhuhr: "0 min",
    asr: "Standard",
    high_lats: "NightMiddle",
    tune: %{},
    format: "24h",
    rounding: "nearest",
    utc_offset: :auto,
    timezone: "Etc/UTC",
    location: {0, 0},
    iterations: 1
  }

  @labels ~w(Fajr Sunrise Dhuhr Asr Sunset Maghrib Isha Midnight)

  @invalid_time "-----"

  # ---------------------- Constructor ------------------------

  @doc "Creates a new calculator with the given method (default \"MWL\")."
  @spec new(String.t() | atom()) :: t()
  def new(method \\ "MWL") do
    method(%__MODULE__{settings: @default_settings}, method)
  end

  @doc "Available calculation methods."
  def methods, do: @methods

  @doc "Display labels for the prayer times."
  def labels, do: @labels

  @doc "The value returned for times that cannot be computed."
  def invalid_time, do: @invalid_time

  # ---------------------- Setters ------------------------

  @doc "Sets the calculation method."
  def method(%__MODULE__{} = pt, method) do
    pt
    |> set(@method_defaults)
    |> set(Map.get(@methods, to_string(method), %{}))
  end

  @doc "Sets calculation parameters (map or keyword list)."
  def adjust(%__MODULE__{} = pt, params), do: set(pt, params)

  @doc "Sets the location as `{lat, lng}` or `[lat, lng]`."
  def location(%__MODULE__{} = pt, location), do: set(pt, location: location)

  @doc "Sets the IANA timezone."
  def timezone(%__MODULE__{} = pt, timezone), do: set(pt, timezone: timezone)

  @doc "Sets tuning minutes, e.g. `%{fajr: 2, isha: -1}`."
  def tune(%__MODULE__{} = pt, tune), do: set(pt, tune: Map.new(tune))

  @doc "Sets the rounding method: \"nearest\", \"up\", \"down\" or \"none\"."
  def rounding(%__MODULE__{} = pt, rounding \\ "nearest"), do: set(pt, rounding: rounding)

  @doc "Sets the time format: \"24h\", \"12h\", \"12H\", \"x\", \"X\" or a fun/1."
  def format(%__MODULE__{} = pt, format), do: set(pt, format: format)

  @doc "Merges settings."
  def set(%__MODULE__{settings: settings} = pt, params) do
    params =
      params
      |> Map.new()
      |> Map.update(:location, nil, &normalize_location/1)
      |> Enum.reject(fn {k, v} -> k == :location and is_nil(v) end)
      |> Map.new()

    %{pt | settings: Map.merge(settings, params)}
  end

  @doc "Sets the UTC offset in minutes, or in hours when |offset| < 16."
  def utc_offset(%__MODULE__{} = pt, utc_offset \\ :auto) do
    utc_offset =
      cond do
        utc_offset in [:auto, "auto"] -> :auto
        is_number(utc_offset) and abs(utc_offset) < 16 -> utc_offset * 60
        true -> utc_offset
      end

    pt |> set(timezone: "Etc/UTC") |> set(utc_offset: utc_offset)
  end

  defp normalize_location([lat, lng]), do: {lat, lng}
  defp normalize_location({_lat, _lng} = loc), do: loc

  # ---------------------- Getters ------------------------

  @doc """
  Returns prayer times for a date.

  `date` can be a `Date`, `DateTime`, `NaiveDateTime`, `{y, m, d}`, `[y, m, d]`,
  a day offset from today (number < 1000) or a Unix timestamp in ms.
  """
  def times(%__MODULE__{settings: s}, date \\ 0) do
    {y, m, d} = to_ymd(date, s)
    utc_time = Date.diff(Date.new!(y, m, d), ~D[1970-01-01]) * 86_400_000

    s
    |> Map.put(:utc_time, utc_time)
    |> compute_times()
  end

  @doc "Backward compatible getter (`getTimes` in the JS version)."
  def get_times(pt, date \\ 0, location \\ nil, timezone \\ :auto, dst \\ 0, format \\ "24h")

  def get_times(pt, date, nil, _timezone, _dst, _format), do: times(pt, date)

  def get_times(pt, date, location, timezone, dst, format) do
    utc_offset = if timezone in [:auto, "auto"], do: :auto, else: timezone + dst

    pt
    |> location(location)
    |> utc_offset(utc_offset)
    |> format(format)
    |> times(date)
  end

  defp to_ymd(%Date{} = d, _s), do: {d.year, d.month, d.day}
  defp to_ymd(%DateTime{} = d, _s), do: {d.year, d.month, d.day}
  defp to_ymd(%NaiveDateTime{} = d, _s), do: {d.year, d.month, d.day}
  defp to_ymd({y, m, d}, _s), do: {y, m, d}
  defp to_ymd([y, m, d], _s), do: {y, m, d}

  defp to_ymd(date, s) when is_number(date) do
    ms =
      if date < 1000,
        do: System.system_time(:millisecond) + Kernel.round(date * 86_400_000),
        else: Kernel.trunc(date)

    dt = local_datetime(ms, s)
    {dt.year, dt.month, dt.day}
  end

  # ---------------------- Compute Times -----------------------

  defp compute_times(s) do
    initial = %{
      fajr: 5,
      sunrise: 6,
      dhuhr: 12,
      asr: 13,
      sunset: 18,
      maghrib: 18,
      isha: 18,
      midnight: 24
    }

    times = Enum.reduce(1..s.iterations//1, initial, fn _, t -> process_times(t, s) end)
    {times, adjusted} = adjust_high_lats(times, s)

    times
    |> update_times(s, adjusted)
    |> tune_times(s)
    |> convert_times(s)
    |> format_times(s)
  end

  defp process_times(times, s) do
    horizon = 0.833

    %{
      fajr: angle_time(s[:fajr], times.fajr, s, -1),
      sunrise: angle_time(horizon, times.sunrise, s, -1),
      dhuhr: mid_day(times.dhuhr, s),
      asr: angle_time(asr_angle(s.asr, times.asr, s), times.asr, s),
      sunset: angle_time(horizon, times.sunset, s),
      maghrib: angle_time(s[:maghrib], times.maghrib, s),
      isha: angle_time(s[:isha], times.isha, s),
      midnight: mid_day(times.midnight, s) + 12
    }
  end

  defp update_times(times, s, adjusted) do
    times =
      if min?(s[:maghrib]),
        do: %{times | maghrib: add(times.sunset, mul(value(s[:maghrib]), 1 / 60))},
        else: times

    times =
      if min?(s[:isha]),
        do: %{times | isha: add(times.maghrib, mul(value(s[:isha]), 1 / 60))},
        else: times

    times =
      if s[:midnight] == "Jafari" do
        next_fajr = add(angle_time(s[:fajr], 29, s, -1), 24)
        fajr = if adjusted, do: add(times.fajr, 24), else: next_fajr
        %{times | midnight: mul(add(times.sunset, fajr), 0.5)}
      else
        times
      end

    %{times | dhuhr: add(times.dhuhr, mul(value(s.dhuhr), 1 / 60))}
  end

  defp tune_times(times, s) do
    tune = s.tune

    Map.new(times, fn {key, time} ->
      mins = Map.get(tune, key, Map.get(tune, Atom.to_string(key)))
      if is_nil(mins), do: {key, time}, else: {key, add(time, mul(mins, 1 / 60))}
    end)
  end

  defp convert_times(times, s) do
    {_lat, lng} = s.location

    Map.new(times, fn {key, time} ->
      case sub(time, lng / 15) do
        nil -> {key, nil}
        t -> {key, round_time(s.utc_time + Kernel.floor(t * 3_600_000), s.rounding)}
      end
    end)
  end

  defp round_time(timestamp, rounding) do
    one_minute = 60_000

    case rounding do
      "up" -> Kernel.ceil(timestamp / one_minute) * one_minute
      "down" -> Kernel.floor(timestamp / one_minute) * one_minute
      # JS Math.round: halves round towards +Infinity
      "nearest" -> Kernel.floor(timestamp / one_minute + 0.5) * one_minute
      _ -> timestamp
    end
  end

  # ---------------------- Calculation Functions -----------------------

  defp sun_position(time, s) do
    {_lat, lng} = s.location
    d = s.utc_time / 86_400_000 - 10957.5 + (value(time) || 0) / 24 - lng / 360

    g = mod(357.529 + 0.98560028 * d, 360)
    q = mod(280.459 + 0.98564736 * d, 360)
    l = mod(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g), 360)
    e = 23.439 - 0.00000036 * d
    ra = mod(darctan2(dcos(e) * dsin(l), dcos(l)) / 15, 24)

    %{declination: darcsin(dsin(e) * dsin(l)), equation: q / 15 - ra}
  end

  defp mid_day(time, s) do
    eqt = sun_position(time, s).equation
    mod(12 - eqt, 24)
  end

  # time when the sun reaches a specific angle below the horizon (nil = NaN)
  defp angle_time(angle, time, s, direction \\ 1) do
    {lat, _lng} = s.location

    with a when is_number(a) <- num(angle),
         decl = sun_position(time, s).declination,
         numerator = -dsin(a) - dsin(lat) * dsin(decl),
         diff when is_number(diff) <- darccos(numerator / (dcos(lat) * dcos(decl))) do
      mid_day(time, s) + diff / 15 * direction
    else
      _ -> nil
    end
  end

  defp asr_angle(asr_param, time, s) do
    shadow_factor =
      case asr_param do
        "Standard" -> 1
        "Hanafi" -> 2
        other -> value(other)
      end

    if is_number(shadow_factor) do
      {lat, _lng} = s.location
      decl = sun_position(time, s).declination
      -darccot(shadow_factor + dtan(abs(lat - decl)))
    end
  end

  # ---------------------- Higher Latitudes -----------------------

  defp adjust_high_lats(times, %{high_lats: "None"}), do: {times, false}

  defp adjust_high_lats(times, s) do
    night = add(24, sub(times.sunrise, times.sunset))

    {fajr, a1} = adjust_time(times.fajr, times.sunrise, s[:fajr], night, s, -1)
    {isha, a2} = adjust_time(times.isha, times.sunset, s[:isha], night, s)
    {maghrib, a3} = adjust_time(times.maghrib, times.sunset, s[:maghrib], night, s)

    {%{times | fajr: fajr, isha: isha, maghrib: maghrib}, a1 or a2 or a3}
  end

  defp adjust_time(time, base, angle, night, s, direction \\ 1) do
    factor =
      case s.high_lats do
        "NightMiddle" -> 1 / 2
        "OneSeventh" -> 1 / 7
        "AngleBased" -> mul(1 / 60, value(angle))
        _ -> nil
      end

    portion = mul(factor, night)
    time_diff = mul(sub(time, base), direction)

    if is_nil(time) or gt(time_diff, portion),
      do: {add(base, mul(portion, direction)), true},
      else: {time, false}
  end

  # ---------------------- Formatting Functions ---------------------

  defp format_times(times, s), do: Map.new(times, fn {k, t} -> {k, format_time(t, s)} end)

  defp format_time(nil, _s), do: @invalid_time
  defp format_time(timestamp, %{format: fun}) when is_function(fun, 1), do: fun.(timestamp)
  defp format_time(timestamp, %{format: "x"}), do: timestamp
  defp format_time(timestamp, %{format: "X"}), do: Integer.floor_div(timestamp, 1000)
  defp format_time(timestamp, s), do: time_to_string(timestamp, s.format, s)

  defp time_to_string(timestamp, format, s) do
    %{hour: h, minute: m} = local_datetime(timestamp, s)
    mm = pad2(m)

    case to_string(format) do
      "24h" ->
        "#{pad2(h)}:#{mm}"

      "12H" ->
        "#{hour12(h)}:#{mm}"

      _ ->
        "#{hour12(h)}:#{mm} #{if h < 12, do: "AM", else: "PM"}"
    end
  end

  defp local_datetime(timestamp, s) do
    offset = if s.utc_offset == :auto, do: 0, else: s.utc_offset
    ms = Kernel.trunc(timestamp + offset * 60_000)
    dt = DateTime.from_unix!(ms, :millisecond)

    case s.timezone do
      tz when tz in ["UTC", "Etc/UTC"] ->
        dt

      tz ->
        db = Map.get(s, :time_zone_database, Calendar.get_time_zone_database())
        DateTime.shift_zone!(dt, tz, db)
    end
  end

  defp hour12(h) when rem(h, 12) == 0, do: 12
  defp hour12(h), do: rem(h, 12)

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  # ---------------------- Misc Functions -----------------------

  # numeric prefix of a value, like JS `+String(str).split(/[^0-9.+-]/)[0]`
  defp value(nil), do: 0
  defp value(x) when is_number(x), do: x

  defp value(x) do
    [first | _] = Regex.split(~r/[^0-9.+-]/, to_string(x))
    js_number(first)
  end

  # strict number conversion, like JS `Number(x)` (nil = NaN)
  defp num(x) when is_number(x), do: x
  defp num(x) when is_binary(x), do: js_number(String.trim(x))
  defp num(_), do: nil

  defp js_number(""), do: 0

  defp js_number(str) do
    if Regex.match?(~r/^[+-]?(\d+\.?\d*|\.\d+)$/, str) do
      str
      |> String.replace(~r/^([+-]?)\./, "\\g{1}0.")
      |> String.replace(~r/\.$/, "")
      |> Float.parse()
      |> elem(0)
    end
  end

  defp min?(x), do: String.contains?(to_string(x), "min")

  # positive modulo
  defp mod(a, b), do: a - b * Float.floor(a / b)

  # NaN-aware arithmetic: nil stands for NaN and propagates
  defp add(a, b) when is_number(a) and is_number(b), do: a + b
  defp add(_, _), do: nil
  defp sub(a, b) when is_number(a) and is_number(b), do: a - b
  defp sub(_, _), do: nil
  defp mul(a, b) when is_number(a) and is_number(b), do: a * b
  defp mul(_, _), do: nil
  defp gt(a, b) when is_number(a) and is_number(b), do: a > b
  defp gt(_, _), do: false

  # --------------------- Degree-Based Trigonometry -----------------

  defp dtr(d), do: d * :math.pi() / 180
  defp rtd(r), do: r * 180 / :math.pi()

  defp dsin(d), do: :math.sin(dtr(d))
  defp dcos(d), do: :math.cos(dtr(d))
  defp dtan(d), do: :math.tan(dtr(d))

  defp darcsin(x), do: rtd(:math.asin(x))
  defp darccos(x) when x >= -1 and x <= 1, do: rtd(:math.acos(x))
  defp darccos(_), do: nil

  defp darccot(x), do: rtd(:math.atan(1 / x))
  defp darctan2(y, x), do: rtd(:math.atan2(y, x))
end
