defmodule TaamolWeb.PageControllerTest do
  use TaamolWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Peace of mind from prototype to production"
    assert response =~ ~p"/users/register"
    assert response =~ ~p"/users/log-in"
  end
end
