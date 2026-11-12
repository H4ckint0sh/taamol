defmodule TaamolWeb.CalendarLiveTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.Events

  defp make_admin(user), do: user |> Ecto.Changeset.change(role: :admin) |> Taamol.Repo.update!()

  test "shows a month with holidays and the selected day", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/calendar?month=2026-06&date=2026-06-25")

    assert has_element?(view, "#calendar-grid")
    assert has_element?(view, "#day-cell-2026-06-25[aria-current=date]")
    assert has_element?(view, "#calendar-day #day-holiday-ashura-2026-06-25")
    assert has_element?(view, "#calendar-month-list #month-holiday-ashura-2026-06-25")
    refute has_element?(view, "#calendar-add-event")
  end

  test "navigates between months", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/calendar?month=2026-06")
    view |> element("#calendar-next") |> render_click()
    assert_patch(view, ~p"/calendar?month=2026-07")
    assert has_element?(view, "#day-cell-2026-07-15")
  end

  test "shows stored events and admin controls", %{conn: conn} do
    admin = user_fixture() |> make_admin()

    {:ok, event} =
      Events.create_event(Scope.for_user(admin), %{
        "title" => "Community iftar",
        "starts_at" => "2026-06-10T19:00",
        "location" => "Main hall"
      })

    {:ok, view, _html} =
      conn |> log_in_user(admin) |> live(~p"/calendar?month=2026-06&date=2026-06-10")

    assert has_element?(view, "#day-event-#{event.id}", "Community iftar")
    assert has_element?(view, "#day-event-#{event.id}", "Main hall")
    assert has_element?(view, "#edit-event-#{event.id}")
    assert has_element?(view, "#calendar-add-event")
  end

  describe "admin event form" do
    test "admins can add an event", %{conn: conn} do
      admin = user_fixture() |> make_admin()
      conn = log_in_user(conn, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/events/new?date=2026-12-01")

      {:ok, _calendar, html} =
        view
        |> form("#event-form",
          event: %{title: "Quran class", kind: "community", starts_at: "2026-12-01T17:00"}
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Quran class"

      assert [%{title: "Quran class"}] =
               Events.list_events_between(~D[2026-12-01], ~D[2026-12-01])
    end

    test "admins can delete an event", %{conn: conn} do
      admin = user_fixture() |> make_admin()

      {:ok, event} =
        Events.create_event(Scope.for_user(admin), %{
          "title" => "Old",
          "starts_at" => "2026-12-02T10:00"
        })

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      view |> element("#delete-event") |> render_click()
      assert Events.list_events_between(~D[2026-12-02], ~D[2026-12-02]) == []
    end

    test "regular users cannot open the form", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/events/new")
    end
  end
end
