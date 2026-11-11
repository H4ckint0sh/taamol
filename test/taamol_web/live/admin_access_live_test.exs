defmodule TaamolWeb.AdminAccessLiveTest do
  use TaamolWeb.ConnCase

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures

  alias Taamol.Accounts
  alias Taamol.Accounts.Scope

  defp admin_fixture do
    user = user_fixture()
    {:ok, admin} = Accounts.bootstrap_admin(user.email)
    admin
  end

  test "requires an administrator for access management and dashboard", %{conn: conn} do
    assert redirected_to(get(conn, "/admin/access")) == ~p"/users/log-in"
    assert redirected_to(get(conn, ~p"/dashboard")) == ~p"/users/log-in"
    assert redirected_to(get(conn, ~p"/dashboard/create/article")) == ~p"/users/log-in"

    conn = log_in_user(conn, user_fixture())
    assert redirected_to(get(conn, "/admin/access")) == ~p"/"
    assert redirected_to(get(conn, ~p"/dashboard")) == ~p"/"
    assert redirected_to(get(conn, ~p"/dashboard/create/article")) == ~p"/"
    refute html_response(get(conn, ~p"/"), 200) =~ ~p"/dashboard"
  end

  test "admin can manage roles and dashboard access", %{conn: conn} do
    admin = admin_fixture()
    target = user_fixture()
    unconfirmed_user_fixture()
    conn = log_in_user(conn, admin)

    assert {:ok, dashboard, _html} = live(conn, ~p"/dashboard")
    assert has_element?(dashboard, "#admin-dashboard")
    assert {:ok, create_article, _html} = live(conn, ~p"/dashboard/create/article")
    assert has_element?(create_article, "#article-creation-placeholder")
    assert has_element?(dashboard, "#dashboard-users", "3")
    assert has_element?(dashboard, "#dashboard-confirmed", "2")
    assert has_element?(dashboard, "#dashboard-admins", "1")
    assert html_response(get(conn, ~p"/"), 200) =~ ~p"/dashboard"
    {:ok, view, _} = live(conn, ~p"/admin/access")
    assert has_element?(view, "#access-management")

    view |> element("#promote-#{target.id}") |> render_click()
    assert %{role: :admin, can_view_dashboard: true} = Accounts.get_user!(target.id)

    view |> element("#dashboard-#{target.id}") |> render_click()
    assert %{role: :admin, can_view_dashboard: false} = Accounts.get_user!(target.id)

    target_conn = build_conn() |> log_in_user(Accounts.get_user!(target.id))
    assert html_response(get(target_conn, "/admin/access"), 200)
    assert redirected_to(get(target_conn, ~p"/dashboard")) == ~p"/"
    refute html_response(get(target_conn, ~p"/"), 200) =~ ~p"/dashboard"

    view |> element("#dashboard-#{target.id}") |> render_click()
    assert Accounts.allowed?(Scope.for_user(Accounts.get_user!(target.id)), :view_dashboard)
    view |> element("#demote-#{target.id}") |> render_click()
    assert %{role: :user, can_view_dashboard: false} = Accounts.get_user!(target.id)
  end

  test "access changes revoke existing sessions and stale administrators cannot change access", %{
    conn: conn
  } do
    admin = admin_fixture()
    other = user_fixture()

    {:ok, {other_admin, _}} =
      Accounts.update_user_access(Scope.for_user(admin), other.id, "promote")

    other_conn = log_in_user(build_conn(), other_admin)
    token = get_session(other_conn, :user_token)
    assert Accounts.get_user_by_session_token(token)
    TaamolWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64(token)}")

    {:ok, view, _} = conn |> log_in_user(admin) |> live(~p"/admin/access")
    view |> element("#demote-#{other.id}") |> render_click()

    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    refute Accounts.get_user_by_session_token(token)

    assert {:error, :forbidden} =
             Accounts.update_user_access(Scope.for_user(other_admin), admin.id, "demote")

    assert {:error, :cannot_demote_self} =
             Accounts.update_user_access(Scope.for_user(admin), admin.id, "demote")
  end
end
