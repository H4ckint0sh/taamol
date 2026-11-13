defmodule Taamol.Settings do
  @moduledoc """
  Site-wide settings managed by administrators (one database row).

  Reads are cached in `:persistent_term` for 30 seconds because some settings
  are used on every request (e.g. the Hijri adjustment for each calendar day).
  Saving through `update/2` refreshes the cache immediately.
  """

  alias Taamol.Accounts
  alias Taamol.Repo
  alias Taamol.Settings.SiteSetting

  @cache_key {__MODULE__, :site}

  @social_networks [
    instagram: :instagram_url,
    facebook: :facebook_url,
    youtube: :youtube_url,
    x: :x_url,
    telegram: :telegram_url,
    whatsapp: :whatsapp_url,
    tiktok: :tiktok_url
  ]

  # cached settings are re-read after this long, so changes made outside this
  # server (seeds, a console, another node) show up without a restart
  @cache_ttl_ms 30_000

  @doc "The current settings (defaults when none are saved yet)."
  def get do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(@cache_key, nil) do
      {%SiteSetting{} = settings, cached_at} when now - cached_at < @cache_ttl_ms ->
        settings

      _missing_or_stale ->
        settings = Repo.get(SiteSetting, 1) || %SiteSetting{id: 1}
        :persistent_term.put(@cache_key, {settings, now})
        settings
    end
  end

  @doc "Reads one setting."
  def get(key), do: Map.fetch!(get(), key)

  @doc """
  Social media links that are filled in, as `[{network, url}]` in display
  order (e.g. `[{:instagram, "https://instagram.com/taamol"}]`).
  """
  def social_links do
    settings = get()

    for {network, field} <- @social_networks,
        url = Map.get(settings, field),
        is_binary(url) and url != "" do
      {network, url}
    end
  end

  @doc """
  The Swish details for donations, or nil when no Swish number is set:
  `%{number: "1231181189", message: "Gåva till Taamol"}`.
  """
  def swish do
    case get() do
      %{swish_number: number} = settings when is_binary(number) and number != "" ->
        %{number: number, message: settings.swish_message || "Taamol"}

      _ ->
        nil
    end
  end

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
        :persistent_term.put(@cache_key, {settings, System.monotonic_time(:millisecond)})
        {:ok, settings}
      end
    else
      {:error, :forbidden}
    end
  end

  @doc "Forgets the cached settings (used by tests)."
  def reset_cache, do: :persistent_term.erase(@cache_key)
end
