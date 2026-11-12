defmodule Taamol.Settings do
  @moduledoc """
  Site-wide settings managed by administrators (one database row).

  Reads are cached in `:persistent_term` because some settings are used on
  every request (e.g. the Hijri adjustment for each calendar day).
  """

  alias Taamol.Accounts
  alias Taamol.Repo
  alias Taamol.Settings.SiteSetting

  @cache_key {__MODULE__, :site}

  @doc "The current settings (defaults when none are saved yet)."
  def get do
    case :persistent_term.get(@cache_key, nil) do
      nil ->
        settings = Repo.get(SiteSetting, 1) || %SiteSetting{id: 1}
        :persistent_term.put(@cache_key, settings)
        settings

      settings ->
        settings
    end
  end

  @doc "Reads one setting."
  def get(key), do: Map.fetch!(get(), key)

  @doc "A changeset for the settings form."
  def change(attrs \\ %{}), do: SiteSetting.changeset(get(), attrs)

  @doc "Saves the settings. Administrators only."
  def update(scope, attrs) do
    if Accounts.can?(scope, :manage_settings) do
      result =
        (Repo.get(SiteSetting, 1) || %SiteSetting{id: 1})
        |> SiteSetting.changeset(attrs)
        |> Repo.insert_or_update()

      with {:ok, settings} <- result do
        :persistent_term.put(@cache_key, settings)
        {:ok, settings}
      end
    else
      {:error, :forbidden}
    end
  end

  @doc "Forgets the cached settings (used by tests)."
  def reset_cache, do: :persistent_term.erase(@cache_key)
end
