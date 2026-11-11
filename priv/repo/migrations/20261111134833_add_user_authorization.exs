defmodule Taamol.Repo.Migrations.AddUserAuthorization do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "user"
      add :can_view_dashboard, :boolean, null: false, default: false
    end

    create constraint(:users, :users_role_valid, check: "role IN ('user', 'admin')")

    create constraint(:users, :dashboard_access_requires_admin,
             check: "NOT can_view_dashboard OR role = 'admin'"
           )
  end
end
