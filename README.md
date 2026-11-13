# Taamol

## Local database

The development app expects PostgreSQL at `localhost:5432` with user
`postgres`, password `postgres`, and database `taamol_dev` (see
`config/dev.exs`). Start PostgreSQL before running `mix setup`.

If PostgreSQL is not already running, you can start it with Docker:

```sh
docker run -d --name taamol-postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 127.0.0.1:5432:5432 \
  -v taamol-postgres-data:/var/lib/postgresql/data \
  postgres:17
```

Wait until `docker exec taamol-postgres pg_isready -U postgres` reports that it
is accepting connections. On later starts, use `docker start taamol-postgres`;
the named volume keeps the database data. If a PostgreSQL container is already
using port 5432, use it instead of starting another one, provided its credentials
match `config/dev.exs`. Use `docker ps` to find its name.

To inspect the database after setup, replace `taamol-postgres` with your
container name if different:

```sh
docker exec -it my-saas-postgres psql -U postgres -d taamol_dev
```

In `psql`, run `\dt` to list tables, `\d articles` to inspect a table, or
`SELECT * FROM articles;` to see its rows. SQL statements need a semicolon. If the
prompt shows `taamol_dev-#`, use `\r` to clear the unfinished command. Use `\q`
to exit.

## Starting the application

Once PostgreSQL is ready:

- Run `mix setup` to install and setup dependencies
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
For an existing database, run `mix ecto.migrate` after pulling new migrations.

## Languages

The navigation offers English, Persian and Swedish. The choice is stored in
the browser session and survives login and logout. Persian uses right-to-left
layout. Article text is entered by its author and is not translated automatically.
Translation catalogs are in `priv/gettext`; use `mix gettext.extract --merge`
after marking new interface strings with `gettext`.

## Administrator access

Register and confirm an account, run migrations, then assign the first admin from
the server terminal. In development, email is not sent to real addresses: open
[`localhost:4000/dev/mailbox`](http://localhost:4000/dev/mailbox) to find and
follow the confirmation link.

```sh
mix ecto.migrate
mix taamol.bootstrap_admin user@example.com
```

Use the correct `MIX_ENV` for the target database. The command refuses to run
once an admin exists; it does not create an account. Administrators can manage
roles and the dashboard permission at `/admin/access`. Access changes sign the
affected user out, including other active sessions. An administrator cannot
remove their own admin role.

The application dashboard at `/dashboard` requires both the admin role and
dashboard permission. The development-only mailbox preview is accessible without
login from localhost and contains sensitive login links; do not expose it through
a proxy or to other users. To deliver real emails, configure a production Swoosh
adapter and its credentials.

## Prayer times

The site widget and calculator default to Växjö (Europe/Stockholm), the Tehran
method, no high-latitude adjustment, downward rounding, and the site's fractional
minute adjustments. Administrators can change the site method. Saved personal
calculator preferences are retained; the widget always shows the site schedule.

## Booking updates

Booking requests and status changes update the member's bookings and the
administrators' dashboard live. Calendar availability changes when a booking
is confirmed or cancelled; pending requests do not reserve a time. The calendar
shows holidays, events and visible bookings alongside each day's booking status;
select a day to see its activities or use its Book button to request a time.
Imam bookings are visible on the calendar only to their owner and
administrators. They require a venue and, outside the association's
premises, an address. The celebration-hall service is no longer bookable;
existing requests remain in the booking history.

## Article comments

After running `mix ecto.migrate`, administrators can create articles through the
`Taamol.Tracking` context. It can also create comments and nested replies and
manage one like per user on articles and comments. Its operations take the
authenticated user scope; articles, comments and likes always use that user as their
creator. Deleting a comment also deletes its replies and likes. Published
articles can be viewed at `/articles`; creation and other operations do not yet
have a web interface.

If the earlier separate news migrations were already applied to a database,
their migration history and any existing data must be reconciled before using
the consolidated migration. Do not reset a database containing data you need.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://phoenix.hexdocs.pm/overview.html
- Docs: https://phoenix.hexdocs.pm
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
