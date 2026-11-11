# Taamol

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Administrator access

Register and confirm an account, run migrations, then assign the first admin from
the server terminal:

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
dashboard permission. The development mailbox preview requires the admin role.

## News comments

After running `mix ecto.migrate`, administrators can create news through the
`Taamol.Tracking` context. It can also create comments and nested replies and
manage one like per user on news and comments. Its operations take the
authenticated user scope; news, comments and likes always use that user as their
creator. Deleting a comment also deletes its replies and likes. These operations
do not yet have a web interface.

If the earlier separate news migrations were already applied to a database,
their migration history and any existing data must be reconciled before using
the consolidated migration. Do not reset a database containing data you need.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
