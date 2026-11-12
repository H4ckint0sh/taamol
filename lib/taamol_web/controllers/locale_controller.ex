defmodule TaamolWeb.LocaleController do
  use TaamolWeb, :controller

  def update(conn, %{"locale" => locale}) when locale in ~w(fa sv) do
    conn
    |> put_session(:locale, locale)
    |> redirect(to: return_path(conn))
  end

  def update(conn, _params), do: send_resp(conn, :bad_request, "Invalid locale")

  defp return_path(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, scheme: scheme, path: "/" <> _ = path} = uri <- URI.parse(referer),
         true <- host == conn.host and scheme in ["http", "https"],
         false <- String.starts_with?(path, "//") do
      if uri.query, do: path <> "?" <> uri.query, else: path
    else
      _ -> ~p"/"
    end
  end
end
