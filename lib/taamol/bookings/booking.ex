defmodule Taamol.Bookings.Booking do
  @moduledoc """
  A booking request. Times are local (community) time without a time zone.

  Status flow: `pending` → `confirmed` | `proposed` (another time offered) |
  `declined`; `proposed` → `confirmed` | `cancelled` (member's answer); any
  open booking → `cancelled` by the member.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :confirmed, :proposed, :declined, :cancelled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "bookings" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :starts_at, :naive_datetime
    field :ends_at, :naive_datetime
    field :proposed_starts_at, :naive_datetime
    field :proposed_ends_at, :naive_datetime
    field :contact_name, :string
    field :contact_phone, :string
    field :guests, :integer
    field :notes, :string
    field :location_type, Ecto.Enum, values: [:association, :other]
    field :address, :string
    field :private_calendar, :boolean, default: false
    field :admin_message, :string
    field :decided_at, :utc_datetime
    belongs_to :service, Taamol.Bookings.Service
    belongs_to :user, Taamol.Accounts.User
    belongs_to :decided_by, Taamol.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc "The member's details for a new request."
  def request_changeset(booking, attrs, service) do
    booking
    |> cast(attrs, [:contact_name, :contact_phone, :guests, :notes, :location_type, :address])
    |> update_change(:contact_name, &String.trim/1)
    |> update_change(:contact_phone, &String.trim/1)
    |> validate_required([:contact_name, :contact_phone])
    |> validate_length(:contact_name, max: 100)
    |> validate_format(:contact_phone, ~r/^[0-9+()\s-]{6,20}$/, message: "must be a phone number")
    |> validate_number(:guests, greater_than_or_equal_to: 0, less_than_or_equal_to: 2000)
    |> validate_length(:notes, max: 2000)
    |> update_change(:address, &String.trim/1)
    |> validate_length(:address, max: 255)
    |> validate_location(service)
  end

  defp validate_location(changeset, %{resource: :imam}) do
    changeset = validate_required(changeset, [:location_type])

    if get_field(changeset, :location_type) == :other,
      do: validate_required(changeset, [:address]),
      else: put_change(changeset, :address, nil)
  end

  defp validate_location(changeset, _service) do
    changeset |> put_change(:location_type, nil) |> put_change(:address, nil)
  end
end
