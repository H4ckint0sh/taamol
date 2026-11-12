defmodule Taamol.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :name, :string
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :role, :string, null: false, default: "user"
      # administrators who may also see the statistics on the dashboard
      add :can_view_dashboard, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create constraint(:users, :users_role_valid, check: "role IN ('user', 'admin')")

    create constraint(:users, :dashboard_access_requires_admin,
             check: "NOT can_view_dashboard OR role = 'admin'"
           )

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    # The first administrator, from `config :taamol, :initial_admin` (turned off
    # in tests). Already confirmed: they sign in with a magic link and can set
    # a password in their account settings. Skipped if the email exists.
    execute(&create_initial_admin/0, fn -> :ok end)
  end

  defp create_initial_admin do
    case Application.get_env(:taamol, :initial_admin) do
      [email: email, name: name] ->
        repo().query!(
          """
          INSERT INTO users (id, email, name, role, can_view_dashboard, confirmed_at, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, $2, 'admin', true, now() AT TIME ZONE 'utc',
                  now() AT TIME ZONE 'utc', now() AT TIME ZONE 'utc')
          ON CONFLICT (email) DO NOTHING
          """,
          [email, name]
        )

      _ ->
        :ok
    end
  end
end
