defmodule TaamolWeb.CalendarLiveTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures
  import Taamol.TrackingFixtures

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
    assert has_element?(view, "#calendar-grid #calendar-controls #calendar-title", "June 2026")
    assert has_element?(view, "#calendar-grid #calendar-controls #calendar-next")
    refute has_element?(view, "#calendar-hero #calendar-next")
    view |> element("#calendar-next") |> render_click()
    assert_patch(view, ~p"/calendar?month=2026-07")
    assert has_element?(view, "#day-cell-2026-07-15")
    assert has_element?(view, "#calendar-grid #calendar-title", "July 2026")
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
    assert has_element?(view, "#calendar-controls #calendar-add-event")
  end

  test "calendar event dialogs create, edit and delete without leaving the calendar", %{
    conn: conn
  } do
    admin = user_fixture() |> make_admin()
    conn = log_in_user(conn, admin)
    {:ok, view, _} = live(conn, ~p"/calendar?month=2030-06&date=2030-06-10")

    view |> element("#calendar-add-event") |> render_click()
    assert has_element?(view, "#event-dialog[role=dialog] #event-form")
    assert has_element?(view, "#event_starts_at[value='2030-06-10T18:00']")
    view |> element("#event-dialog-close") |> render_click()
    refute has_element?(view, "#event-dialog")

    view |> element("#calendar-add-event") |> render_click()

    view
    |> form("#event-form", event: %{title: "", starts_at: "2030-06-10T18:00"})
    |> render_submit()

    assert has_element?(view, "#event-form", "can't be blank")

    view
    |> form("#event-form", event: %{title: "Dialog event", starts_at: "2030-06-10T19:00"})
    |> render_submit()

    assert_patch(view, ~p"/calendar?date=2030-06-10&month=2030-06")
    assert [%{id: id}] = Events.list_events_between(~D[2030-06-10], ~D[2030-06-10])
    assert has_element?(view, "#day-event-#{id}", "Dialog event")
    refute has_element?(view, "#event-dialog")

    view |> element("#edit-event-#{id}") |> render_click()
    assert has_element?(view, "#event-dialog #delete-event")

    view
    |> form("#event-form", event: %{title: "Moved event", starts_at: "2030-07-02T18:00"})
    |> render_submit()

    assert_patch(view, ~p"/calendar?date=2030-07-02&month=2030-07")
    assert has_element?(view, "#day-event-#{id}", "Moved event")

    view |> element("#edit-event-#{id}") |> render_click()
    view |> element("#delete-event") |> render_click()
    assert_patch(view, ~p"/calendar?date=2030-07-02&month=2030-07")
    refute has_element?(view, "#day-event-#{id}")
    assert Events.get_event(id) == nil
  end

  test "calendar event dialogs are restricted to administrators", %{conn: conn} do
    for conn <- [conn, log_in_user(conn, user_fixture())] do
      {:ok, view, _} = live(conn, ~p"/calendar")
      refute has_element?(view, "#calendar-add-event")
      render_hook(view, "new-event", %{})
      refute has_element?(view, "#event-dialog")
      assert has_element?(view, "#flash-error")
    end
  end

  test "dashboard event buttons use the same dialog", %{conn: conn} do
    admin = user_fixture() |> make_admin()
    {:ok, view, _} = conn |> log_in_user(admin) |> live(~p"/dashboard/events")
    date = Date.add(Date.utc_today(), 10)

    view |> element("#new-event") |> render_click()
    assert has_element?(view, "#event-dialog #event-form")

    view
    |> form("#event-form", event: %{title: "Dashboard event", starts_at: "#{date}T18:00"})
    |> render_submit()

    assert [%{id: id}] = Events.list_events_between(date, date)
    assert has_element?(view, "#events-#{id}", "Dashboard event")
    refute has_element?(view, "#event-dialog")

    view |> element("#edit-#{id}") |> render_click()
    view |> form("#event-form", event: %{title: "Changed event"}) |> render_submit()
    assert has_element?(view, "#events-#{id}", "Changed event")
    refute has_element?(view, "#event-dialog")
  end

  test "live event updates do not erase an open dialog draft", %{conn: conn} do
    admin = user_fixture() |> make_admin()
    {:ok, view, _} = conn |> log_in_user(admin) |> live(~p"/calendar")
    view |> element("#calendar-add-event") |> render_click()
    view |> form("#event-form", event: %{title: "Draft"}) |> render_change()

    assert {:ok, _} =
             Events.create_event(Scope.for_user(admin), %{
               title: "Other",
               starts_at: "2030-01-01T18:00"
             })

    assert has_element?(view, "#event-dialog #event_title[value='Draft']")
  end

  test "an open dialog reports revoked access and concurrently deleted events", %{conn: conn} do
    admin = user_fixture() |> make_admin()
    scope = Scope.for_user(admin)
    {:ok, event} = Events.create_event(scope, %{title: "Original", starts_at: "2030-06-10T18:00"})
    {:ok, view, _} = conn |> log_in_user(admin) |> live(~p"/calendar?date=2030-06-10")

    view |> element("#edit-event-#{event.id}") |> render_click()
    assert {:ok, _} = Events.delete_event(scope, event)
    view |> form("#event-form", event: %{title: "Changed"}) |> render_submit()
    assert has_element?(view, "#event-form-error", "This event no longer exists.")
    view |> element("#event-dialog-close") |> render_click()

    view |> element("#calendar-add-event") |> render_click()
    admin |> Ecto.Changeset.change(role: :user) |> Taamol.Repo.update!()
    view |> form("#event-form", event: %{title: "Not allowed"}) |> render_submit()
    assert has_element?(view, "#event-form-error", "You are not allowed to do that.")
    assert Events.list_events_between(~D[2030-06-10], ~D[2030-06-10]) == []
  end

  test "calendar and dashboard event lists update across sessions", %{conn: conn} do
    admin = user_fixture() |> make_admin()
    scope = Scope.for_user(admin)
    day = Date.add(Date.utc_today(), 2)
    next_day = Date.add(day, 1)
    month = Calendar.strftime(day, "%Y-%m")
    admin_conn = log_in_user(conn, admin)

    {:ok, calendar, _} = live(conn, ~p"/calendar?month=#{month}&date=#{Date.to_iso8601(day)}")
    {:ok, upcoming, _} = live(admin_conn, ~p"/dashboard/events")
    {:ok, past, _} = live(admin_conn, ~p"/dashboard/events?when=past")

    assert {:ok, event} =
             Events.create_event(scope, %{
               title: "Live gathering",
               starts_at: "#{day}T18:00"
             })

    assert has_element?(calendar, "#day-event-#{event.id}", "Live gathering")
    assert has_element?(upcoming, "#events-#{event.id}", "Live gathering")
    refute has_element?(past, "#events-#{event.id}")

    assert {:ok, event} =
             Events.update_event(scope, event, %{
               title: "Moved gathering",
               starts_at: "#{next_day}T18:00"
             })

    refute has_element?(calendar, "#day-event-#{event.id}")
    assert has_element?(calendar, "#day-cell-#{day}[aria-current=date]")
    assert has_element?(upcoming, "#events-#{event.id}", "Moved gathering")

    view_date = Date.to_iso8601(next_day)
    assert has_element?(calendar, "#day-cell-#{view_date}", "Moved gathering")
    assert {:ok, _} = Events.delete_event(scope, event)
    refute has_element?(calendar, "#day-cell-#{view_date}", "Moved gathering")
    refute has_element?(upcoming, "#events-#{event.id}")
  end

  test "upcoming cards and dashboard event statistics update", %{conn: conn} do
    admin =
      user_fixture()
      |> make_admin()
      |> Ecto.Changeset.change(can_view_dashboard: true)
      |> Taamol.Repo.update!()

    scope = Scope.for_user(admin)
    article = article_fixture(admin)
    admin_conn = log_in_user(conn, admin)

    {:ok, home, _} = live(conn, ~p"/")
    {:ok, news, _} = live(conn, ~p"/news")
    {:ok, article_view, _} = live(conn, ~p"/articles/#{article.id}")
    {:ok, overview, _} = live(admin_conn, ~p"/dashboard")

    before_count = length(Events.upcoming(limit: 1000, days: 30))
    today = Date.utc_today()

    assert {:ok, event} =
             Events.create_event(scope, %{title: "Live card event", starts_at: "#{today}T00:00"})

    for {view, id} <- [
          {home, "rail-upcoming"},
          {news, "rail-upcoming"},
          {article_view, "rail-upcoming"},
          {overview, "dashboard-upcoming"}
        ] do
      assert has_element?(view, "##{id}", "Live card event")
    end

    assert has_element?(
             overview,
             "#stat-events [data-value]",
             Integer.to_string(before_count + 1)
           )

    assert {:ok, event} = Events.update_event(scope, event, %{title: "Updated card event"})
    assert has_element?(news, "#rail-upcoming", "Updated card event")
    assert {:ok, _} = Events.delete_event(scope, event)
    refute has_element?(home, "#rail-upcoming", "Updated card event")
    refute has_element?(article_view, "#rail-upcoming", "Updated card event")
    assert has_element?(overview, "#stat-events [data-value]", Integer.to_string(before_count))
  end

  test "deleting the last event on a page repairs both sessions", %{conn: conn} do
    admin = user_fixture() |> make_admin()
    scope = Scope.for_user(admin)
    starts_at = Date.add(Date.utc_today(), 10)

    for i <- 1..21 do
      assert {:ok, _} =
               Events.create_event(scope, %{title: "Event #{i}", starts_at: "#{starts_at}T18:00"})
    end

    %{entries: [last]} = Events.list_events_page(limit: 20, offset: 20)
    conn = log_in_user(conn, admin)
    {:ok, first, _} = live(conn, ~p"/dashboard/events?page=2")
    {:ok, second, _} = live(conn, ~p"/dashboard/events?page=2")

    first |> element("#delete-#{last.id}") |> render_click()
    assert_patch(first, ~p"/dashboard/events")
    assert_patch(second, ~p"/dashboard/events")
    refute has_element?(first, "#events-#{last.id}")
    refute has_element?(second, "#events-#{last.id}")
  end

  describe "admin event form" do
    test "admins can add an event", %{conn: conn} do
      admin = user_fixture() |> make_admin()
      conn = log_in_user(conn, admin)

      {:ok, view, _html} = live(conn, ~p"/dashboard/events/new?date=2026-12-01")

      view
      |> form("#event-form",
        event: %{title: "Quran class", kind: "community", starts_at: "2026-12-01T17:00"}
      )
      |> render_submit()

      assert_redirect(view, ~p"/calendar?date=2026-12-01&month=2026-12")

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
      {:ok, view, _html} = live(conn, ~p"/dashboard/events/#{event.id}/edit")

      view |> element("#delete-event") |> render_click()
      assert Events.list_events_between(~D[2026-12-02], ~D[2026-12-02]) == []
    end

    test "editing a concurrently deleted event shows an error", %{conn: conn} do
      admin = user_fixture() |> make_admin()
      scope = Scope.for_user(admin)
      {:ok, event} = Events.create_event(scope, %{title: "Event", starts_at: "2030-12-02T10:00"})
      {:ok, view, _} = conn |> log_in_user(admin) |> live(~p"/dashboard/events/#{event.id}/edit")

      assert {:ok, _} = Events.delete_event(scope, event)
      view |> form("#event-form", event: %{title: "Changed"}) |> render_submit()
      assert has_element?(view, "#flash-error", "This event no longer exists.")
    end

    test "regular users cannot open the form", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, _}} = live(conn, ~p"/dashboard/events/new")
    end
  end
end
