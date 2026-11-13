defmodule Taamol.Bookings.Service do
  @moduledoc "Something members can book (the premises, the imam, …)."
  use Ecto.Schema
  import Ecto.Changeset

  @resources [:premises, :imam, :other]
  @icons ~w(hero-building-library hero-heart hero-sparkles hero-user hero-book-open hero-musical-note hero-calendar-days hero-moon)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "booking_services" do
    field :name_fa, :string
    field :name_sv, :string
    field :description_fa, :string
    field :description_sv, :string
    field :resource, Ecto.Enum, values: @resources, default: :premises
    field :duration_minutes, :integer, default: 120
    field :icon, :string, default: "hero-calendar-days"
    field :active, :boolean, default: true
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def resources, do: @resources
  def icons, do: @icons

  @doc false
  def changeset(service, attrs) do
    service
    |> cast(attrs, [
      :name_fa,
      :name_sv,
      :description_fa,
      :description_sv,
      :resource,
      :duration_minutes,
      :icon,
      :active,
      :position
    ])
    |> validate_required([:name_fa, :name_sv, :resource, :duration_minutes, :icon])
    |> validate_length(:name_fa, max: 100)
    |> validate_length(:name_sv, max: 100)
    |> validate_length(:description_fa, max: 1000)
    |> validate_length(:description_sv, max: 1000)
    |> validate_number(:duration_minutes,
      greater_than_or_equal_to: 30,
      less_than_or_equal_to: 720
    )
    |> validate_inclusion(:icon, @icons)
  end
end
