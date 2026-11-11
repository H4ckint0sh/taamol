defmodule TaamolWeb.Locale do
  import Plug.Conn

  @locales ~w(en fa sv)

  def normalize(locale) when locale in @locales, do: locale
  def normalize(_), do: "en"

  def set_locale(conn, _opts) do
    locale = normalize(get_session(conn, :locale))
    Gettext.put_locale(TaamolWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = normalize(session["locale"])
    Gettext.put_locale(TaamolWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
