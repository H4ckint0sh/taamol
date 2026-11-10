defmodule Taamol.Repo do
  use Ecto.Repo,
    otp_app: :taamol,
    adapter: Ecto.Adapters.Postgres
end
