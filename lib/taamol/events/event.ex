defmodule Taamol.Events.Event do
  @moduledoc """
  A calendar event added by an administrator (e.g. a Taamol community event).

  `starts_at`/`ends_at` are local (community) times without a time zone.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:community, :celebration, :mourning, :observance]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "events" do
    field :title, :string
    field :description, :string
    field :location, :string
    field :kind, Ecto.Enum, values: @kinds, default: :community
    field :all_day, :boolean, default: false
    field :starts_at, :naive_datetime
    field :ends_at, :naive_datetime
    belongs_to :creator, Taamol.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Event kinds, in display order."
  def kinds, do: @kinds

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :description, :location, :kind, :all_day, :starts_at, :ends_at])
    |> validate_required([:title, :kind, :starts_at])
    |> validate_length(:title, max: 150)
    |> validate_length(:location, max: 255)
    |> validate_length(:description, max: 5000)
    |> validate_ends_after_start()
  end

  defp validate_ends_after_start(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && NaiveDateTime.compare(ends_at, starts_at) == :lt do
      add_error(changeset, :ends_at, "must be after the start")
    else
      changeset
    end
  end
end
