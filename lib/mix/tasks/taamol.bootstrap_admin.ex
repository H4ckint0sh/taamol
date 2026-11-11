defmodule Mix.Tasks.Taamol.BootstrapAdmin do
  use Mix.Task

  @shortdoc "Assigns the first administrator to a confirmed account"
  @moduledoc """
  Assigns the first administrator to an existing confirmed account:

      mix taamol.bootstrap_admin user@example.com

  Refuses to run if an administrator already exists.
  """

  @impl Mix.Task
  def run([email]) do
    Mix.Task.run("app.start")

    case Taamol.Accounts.bootstrap_admin(email) do
      {:ok, _user} ->
        Mix.shell().info("First administrator assigned.")

      {:error, :admin_already_exists} ->
        Mix.raise("An administrator already exists.")

      {:error, :user_unconfirmed} ->
        Mix.raise("The account must be confirmed first.")

      {:error, :user_not_found} ->
        Mix.raise("No account found for that email.")

      {:error, changeset} ->
        Mix.raise("Could not assign administrator: #{inspect(changeset.errors)}")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix taamol.bootstrap_admin user@example.com")
end
