defmodule Taamol.Repo.Migrations.AddContactDetailsToSiteSettings do
  use Ecto.Migration

  def change do
    alter table(:site_settings) do
      # shown on the contact page (empty = hidden)
      add :contact_address, :text
      add :contact_phone, :string
      add :contact_email, :string
      add :opening_hours, :text
    end
  end
end
