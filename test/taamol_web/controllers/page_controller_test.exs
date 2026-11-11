defmodule TaamolWeb.PageControllerTest do
  use TaamolWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Welcome to Taamol"
    assert response =~ "start-page"
    assert response =~ ~p"/users/register"
    assert response =~ ~p"/users/log-in"
  end
end
