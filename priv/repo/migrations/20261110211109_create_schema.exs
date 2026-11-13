defmodule Taamol.Repo.Migrations.CreateSchema do
  @moduledoc """
  The whole Taamol database in one migration: accounts, news, calendar
  events, site settings, gallery, contact messages and bookings.

  Add new migrations for changes from here on; don't edit this file once it
  has run on a database you can't reset.
  """
  use Ecto.Migration

  def change do
    # --- Accounts: users, login tokens and the first administrator ---------

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

    # --- News: articles, threaded comments and likes -----------------------

    create table(:articles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false, size: 100
      add :summary, :text
      # Markdown
      add :body, :text
      add :category, :string, null: false, default: "community"
      add :cover_image_url, :string, size: 2048
      add :featured, :boolean, null: false, default: false
      add :view_count, :integer, null: false, default: 0
      # publish time; nil = draft
      add :published, :utc_datetime
      add :author, :string
      add :creator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:articles, [:creator_id])
    create index(:articles, [:published])
    create index(:articles, [:category, :published])
    create index(:articles, [:view_count])

    create table(:comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false

      add :article_id, references(:articles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :creator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:comments, [:article_id])
    create index(:comments, [:creator_id])
    create unique_index(:comments, [:id, :article_id])

    alter table(:comments) do
      add :parent_id,
          references(:comments,
            type: :binary_id,
            with: [article_id: :article_id],
            on_delete: :delete_all
          )
    end

    create index(:comments, [:parent_id])

    create constraint(:comments, :comments_not_own_parent,
             check: "parent_id IS NULL OR parent_id <> id"
           )

    create table(:article_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :article_id, references(:articles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:article_likes, [:article_id, :user_id])
    create index(:article_likes, [:user_id])

    create table(:comment_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :comment_id, references(:comments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:comment_likes, [:comment_id, :user_id])
    create index(:comment_likes, [:user_id])

    # --- Calendar: community events (holidays are computed, not stored) ----

    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false, size: 150
      add :description, :text
      add :location, :string
      add :kind, :string, null: false, default: "community"
      add :all_day, :boolean, null: false, default: false
      # local (community) time: the community is in one place, so no time zone
      add :starts_at, :naive_datetime, null: false
      add :ends_at, :naive_datetime
      add :creator_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:starts_at])
    create index(:events, [:creator_id])

    # --- Site settings: one row managed by administrators ------------------

    # a single row (id = 1) of site-wide settings managed by administrators
    create table(:site_settings) do
      add :hijri_adjustment_days, :integer, null: false, default: 0
      add :prayer_method, :string, null: false, default: "MWL"

      # social media links shown in the footer
      add :instagram_url, :string
      add :facebook_url, :string
      add :youtube_url, :string
      add :x_url, :string
      add :telegram_url, :string
      add :whatsapp_url, :string
      add :tiktok_url, :string

      # Swish number for donations (digits only); empty = donations hidden
      add :swish_number, :string
      add :swish_message, :string

      timestamps(type: :utc_datetime)
    end

    create constraint(:site_settings, :single_row, check: "id = 1")

    # --- Gallery -----------------------------------------------------------

    create table(:gallery_images, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :image_url, :string, null: false, size: 2048
      add :caption, :string
      add :creator_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:gallery_images, [:inserted_at])

    # --- Contact page messages ---------------------------------------------

    create table(:contact_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :email, :string, null: false
      add :topic, :string, null: false, default: "feedback"
      add :message, :text, null: false
      add :read_at, :utc_datetime
      # set when the sender was logged in
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:contact_messages, [:inserted_at])
    create index(:contact_messages, [:email, :inserted_at])

    # --- Booking: what members can book ------------------------------------

    # what members can book (premises, the imam, …); managed by administrators
    create table(:booking_services, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name_fa, :string, null: false
      add :name_sv, :string, null: false
      add :description_fa, :text
      add :description_sv, :text
      # bookings of the same resource can't overlap: premises, imam, other
      add :resource, :string, null: false, default: "premises"
      add :duration_minutes, :integer, null: false, default: 120
      add :icon, :string, null: false, default: "hero-calendar-days"
      add :active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    # --- Booking: requests and their status --------------------------------

    create table(:bookings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :service_id, references(:booking_services, type: :binary_id, on_delete: :restrict),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # pending | confirmed | proposed | declined | cancelled
      add :status, :string, null: false, default: "pending"
      # local (community) time, like calendar events
      add :starts_at, :naive_datetime, null: false
      add :ends_at, :naive_datetime, null: false
      # another time offered by an administrator
      add :proposed_starts_at, :naive_datetime
      add :proposed_ends_at, :naive_datetime
      add :contact_name, :string, null: false
      add :contact_phone, :string, null: false
      add :guests, :integer
      add :notes, :text
      add :admin_message, :text
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decided_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:bookings, [:service_id])
    create index(:bookings, [:user_id])
    create index(:bookings, [:status, :starts_at])
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
