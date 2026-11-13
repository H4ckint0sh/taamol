defmodule Taamol.Settings.SiteSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @prayer_methods ~w(MWL ISNA Egypt Makkah Karachi Tehran Jafari France Russia Singapore)
  @social_fields ~w(instagram_url facebook_url youtube_url x_url telegram_url whatsapp_url tiktok_url)a

  schema "site_settings" do
    field :hijri_adjustment_days, :integer, default: 0
    field :prayer_method, :string, default: "MWL"

    # social media links shown in the footer (empty = hidden)
    field :instagram_url, :string
    field :facebook_url, :string
    field :youtube_url, :string
    field :x_url, :string
    field :telegram_url, :string
    field :whatsapp_url, :string
    field :tiktok_url, :string

    # donations via Swish (empty number = donations hidden)
    field :swish_number, :string
    field :swish_message, :string

    # contact details on the contact page (empty = hidden)
    field :contact_address, :string
    field :contact_phone, :string
    field :contact_email, :string
    field :opening_hours, :string

    timestamps(type: :utc_datetime)
  end

  def prayer_methods, do: @prayer_methods

  @doc "The social link fields, in display order."
  def social_fields, do: @social_fields

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [
      :hijri_adjustment_days,
      :prayer_method,
      :swish_number,
      :swish_message,
      :contact_address,
      :contact_phone,
      :contact_email,
      :opening_hours | @social_fields
    ])
    |> validate_required([:hijri_adjustment_days, :prayer_method])
    |> validate_number(:hijri_adjustment_days,
      greater_than_or_equal_to: -2,
      less_than_or_equal_to: 2
    )
    |> validate_inclusion(:prayer_method, @prayer_methods)
    |> validate_social_links()
    |> update_change(:swish_number, &String.replace(&1, ~r/\D/, ""))
    |> validate_format(:swish_number, ~r/^\d{10}$/, message: "must be a 10-digit Swish number")
    |> validate_length(:swish_message, max: 50)
    |> validate_length(:contact_address, max: 300)
    |> validate_length(:contact_phone, max: 40)
    |> validate_length(:contact_email, max: 160)
    |> validate_format(:contact_email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:opening_hours, max: 500)
  end

  defp validate_social_links(changeset) do
    Enum.reduce(@social_fields, changeset, fn field, acc ->
      acc
      |> validate_length(field, max: 255)
      |> validate_format(field, ~r{^https?://[^\s]+$}, message: "must start with https://")
    end)
  end
end
