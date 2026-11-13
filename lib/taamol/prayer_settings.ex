defmodule Taamol.PrayerSettings do
  @moduledoc "Validated, portable preferences for the prayer time calculator."

  use Ecto.Schema
  import Ecto.Changeset

  alias Taamol.PrayTime

  @primary_key false
  embedded_schema do
    field :method, :string, default: "Tehran"
    field :latitude, :float, default: 56.8790
    field :longitude, :float, default: 14.8059
    field :city, :string
    field :timezone, :string
    field :utc_offset, :float, default: 0.0
    field :date, :date, virtual: true
    field :fajr, :float
    field :isha, :string
    field :maghrib, :string
    field :dhuhr, :integer, default: 0
    field :asr, :string, default: "Standard"
    field :high_lats, :string, default: "None"
    field :midnight, :string
    field :format, :string, default: "24h"
    field :rounding, :string, default: "down"
    field :iterations, :integer, default: 1
    field :tune_fajr, :float, default: 0.0
    field :tune_sunrise, :float, default: 0.07
    field :tune_dhuhr, :float, default: 0.15
    field :tune_asr, :float, default: 0.0
    field :tune_sunset, :float, default: 1.15
    field :tune_maghrib, :float, default: 1.08
    field :tune_isha, :float, default: 0.0
    field :tune_midnight, :float, default: 0.0
  end

  @tune_fields ~w(tune_fajr tune_sunrise tune_dhuhr tune_asr tune_sunset tune_maghrib tune_isha tune_midnight)a
  @fields ~w(method latitude longitude city timezone utc_offset date fajr isha maghrib dhuhr asr high_lats midnight format rounding iterations)a ++
            @tune_fields
  @required ~w(method latitude longitude utc_offset date dhuhr asr high_lats format rounding iterations)a ++
              @tune_fields

  def defaults do
    %__MODULE__{city: "Växjö", timezone: "Europe/Stockholm", date: Date.utc_today()}
  end

  def changeset(attrs \\ %{}) do
    defaults()
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:method, Map.keys(PrayTime.methods()))
    |> validate_number(:latitude, greater_than: -90, less_than: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_length(:city, max: 300)
    |> validate_length(:timezone, max: 100)
    |> validate_format(:timezone, ~r/^[A-Za-z0-9_+\/-]+$/)
    |> validate_number(:utc_offset, greater_than_or_equal_to: -12, less_than_or_equal_to: 14)
    |> validate_number(:fajr, greater_than: 0, less_than_or_equal_to: 90)
    |> validate_number(:dhuhr, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_number(:iterations, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_inclusion(:high_lats, ~w(None NightMiddle OneSeventh AngleBased))
    |> validate_inclusion(:midnight, ~w(Standard Jafari))
    |> validate_inclusion(:format, ~w(24h 12h 12H x X))
    |> validate_inclusion(:rounding, ~w(nearest up down none))
    |> validate_format(:isha, ~r/^(?:\d+(?:\.\d+)?)(?: min)?$/,
      message: "must be an angle or minutes, for example 18 or 90 min"
    )
    |> validate_format(:maghrib, ~r/^(?:\d+(?:\.\d+)?)(?: min)?$/,
      message: "must be an angle or minutes, for example 4.5 or 1 min"
    )
    |> validate_format(:asr, ~r/^(?:Standard|Hanafi|(?:[1-9]\d*(?:\.\d+)?|0\.\d*[1-9]\d*))$/,
      message: "must be Standard, Hanafi, or a positive shadow factor"
    )
    |> validate_change(:asr, fn :asr, value ->
      case value do
        method when method in ["Standard", "Hanafi"] ->
          []

        _ ->
          case Float.parse(value) do
            {factor, ""} when factor > 0 and factor <= 1000 -> []
            _ -> [asr: "must be a positive shadow factor at most 1000"]
          end
      end
    end)
    |> validate_custom_values()
    |> validate_tuning()
  end

  defp validate_custom_values(changeset) do
    Enum.reduce([:isha, :maghrib], changeset, fn field, changeset ->
      validate_change(changeset, field, fn _, value ->
        case Float.parse(value) do
          {number, rest} when number <= 90 and rest == "" -> []
          {number, " min"} when number <= 180 -> []
          _ -> [{field, "must be at most 90 degrees or 180 minutes"}]
        end
      end)
    end)
  end

  defp validate_tuning(changeset) do
    Enum.reduce(@tune_fields, changeset, fn field, changeset ->
      validate_number(changeset, field,
        greater_than_or_equal_to: -180,
        less_than_or_equal_to: 180
      )
    end)
  end

  def to_map(settings) do
    settings
    |> Map.from_struct()
    |> Map.drop([:date])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  def calculator(settings) do
    adjustments =
      [
        fajr: settings.fajr,
        isha: settings.isha,
        maghrib: settings.maghrib,
        midnight: settings.midnight
      ]
      |> Enum.reject(fn {_, value} -> is_nil(value) end)

    tune =
      Map.new(@tune_fields, fn field ->
        key =
          field
          |> Atom.to_string()
          |> String.replace_prefix("tune_", "")
          |> String.to_existing_atom()

        {key, Map.fetch!(settings, field)}
      end)

    settings.method
    |> PrayTime.new()
    |> PrayTime.location({settings.latitude, settings.longitude})
    |> PrayTime.adjust(
      adjustments ++
        [
          utc_offset: settings.utc_offset * 60,
          dhuhr: "#{settings.dhuhr} min",
          asr: settings.asr,
          high_lats: settings.high_lats,
          format: settings.format,
          rounding: settings.rounding,
          iterations: settings.iterations,
          tune: tune
        ]
    )
  end
end
