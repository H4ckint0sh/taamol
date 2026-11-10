defmodule TaamolWeb.PageController do
  use TaamolWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
