defmodule Taamol.Bookings.Lock do
  @moduledoc false

  alias Taamol.Repo

  def acquire do
    unless Repo.in_transaction?(), do: raise("booking lock requires a transaction")
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [2_021_101_301])
    :ok
  end
end
