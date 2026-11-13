defmodule Taamol.Contact.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @topics [:feedback, :question, :events, :other]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "contact_messages" do
    field :name, :string
    field :email, :string
    field :topic, Ecto.Enum, values: @topics, default: :feedback
    field :message, :string
    field :read_at, :utc_datetime
    belongs_to :user, Taamol.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def topics, do: @topics

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:name, :email, :topic, :message])
    |> update_change(:name, &String.trim/1)
    |> update_change(:email, &String.trim/1)
    |> update_change(:message, &String.trim/1)
    |> validate_required([:name, :email, :topic, :message])
    |> validate_length(:name, max: 100)
    |> validate_length(:email, max: 160)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:message, min: 10, max: 5000)
  end
end
