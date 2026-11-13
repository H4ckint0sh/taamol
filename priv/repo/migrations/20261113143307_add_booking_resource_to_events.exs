defmodule Taamol.Repo.Migrations.AddBookingResourceToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :booking_resource, :string
    end
  end
end
