defmodule TaamolWeb.Locale do
  @moduledoc """
  The site is in Persian and Swedish. A visitor's choice is kept in the
  session; on the first visit the browser's language decides (Swedish browsers
  get Swedish, everyone else the default, Persian).
  """
  import Plug.Conn

  @locales ~w(fa sv)

  @doc "Supported locales."
  def locales, do: @locales

  @doc "The locale used when nothing else applies (`config :taamol, :default_locale`)."
  def default, do: Application.get_env(:taamol, :default_locale, "fa")

  def normalize(locale) when locale in @locales, do: locale
  def normalize(_), do: default()

  def set_locale(conn, _opts) do
    {locale, conn} =
      case get_session(conn, :locale) do
        saved when saved in @locales ->
          {saved, conn}

        _ ->
          # remember it so LiveViews (which read the session) agree
          locale = from_accept_language(conn)
          {locale, put_session(conn, :locale, locale)}
      end

    Gettext.put_locale(TaamolWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = normalize(session["locale"])
    Gettext.put_locale(TaamolWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  # "sv-SE,sv;q=0.9,en;q=0.8" -> "sv"; the first supported language wins
  defp from_accept_language(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first("")
    |> String.split(",")
    |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim() |> String.downcase()))
    |> Enum.find_value(default(), fn tag ->
      Enum.find(@locales, &(tag == &1 or String.starts_with?(tag, &1 <> "-")))
    end)
  end
end
