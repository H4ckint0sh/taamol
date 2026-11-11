defmodule Taamol.Accounts.Helpers do
  import Ecto.Query

  alias Taamol.Accounts.User
  alias Taamol.Repo

  def find_admin_with_lock(user_id) do
    Repo.one(
      from u in User,
        where: u.id == ^user_id and u.role == :admin,
        lock: "FOR SHARE"
    )
  end
end
