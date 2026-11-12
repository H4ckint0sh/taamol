defmodule Taamol.Settings.SiteSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @prayer_methods ~w(MWL ISNA Egypt Makkah Karachi Tehran Jafari France Russia Singapore)

  schema "site_settings" do
    field :hijri_adjustment_days, :integer, default: 0
    field :prayer_method, :string, default: "MWL"

    timestamps(type: :utc_datetime)
  end

  def prayer_methods, do: @prayer_methods

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:hijri_adjustment_days, :prayer_method])
    |> validate_required([:hijri_adjustment_days, :prayer_method])
    |> validate_number(:hijri_adjustment_days,
      greater_than_or_equal_to: -2,
      less_than_or_equal_to: 2
    )
    |> validate_inclusion(:prayer_method, @prayer_methods)
  end
end
