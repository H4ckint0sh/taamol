defmodule TaamolWeb.RedirectController do
  @moduledoc "Permanent redirects for old URLs (category pages moved to /news)."
  use TaamolWeb, :controller

  def categories(conn, %{"category" => category}),
    do: conn |> put_status(:moved_permanently) |> redirect(to: ~p"/news?#{[category: category]}")

  def categories(conn, _params),
    do: conn |> put_status(:moved_permanently) |> redirect(to: ~p"/news")
end
