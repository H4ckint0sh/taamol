defmodule TaamolWeb.BookingHistoryTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.Bookings.{Audit, Booking, Service}
  alias Taamol.Repo

  test "only administrators can open history for all booking statuses", %{conn: conn} do
    member = user_fixture(%{name: "Member"})

    admin =
      user_fixture(%{name: "History admin"})
      |> Ecto.Changeset.change(role: :admin)
      |> Repo.update!()

    service =
      %Service{}
      |> Service.changeset(%{name_sv: "Test", name_fa: "Test", icon: "hero-heart"})
      |> Repo.insert!()

    booking =
      Repo.insert!(%Booking{
        user_id: member.id,
        service_id: service.id,
        status: :cancelled,
        starts_at: ~N[2026-12-01 10:00:00],
        ends_at: ~N[2026-12-01 11:00:00],
        contact_name: "Member",
        contact_phone: "0701234567"
      })

    event =
      Audit.record!(booking, Scope.for_user(admin), "proposed", %{
        new_starts_at: ~N[2026-12-02 12:00:00],
        new_ends_at: ~N[2026-12-02 13:00:00]
      })

    {:ok, view, _} = conn |> log_in_user(admin) |> live(~p"/dashboard/bookings?view=all")
    toggle = "#booking-history-toggle-#{booking.id}"
    assert has_element?(view, toggle)
    view |> element(toggle) |> render_click()
    assert has_element?(view, "#booking-history-#{booking.id}")
    assert has_element?(view, "#history-#{event.id}", "History admin")
    assert has_element?(view, "#history-#{event.id}", admin.email)
    assert has_element?(view, "#history-#{event.id}", "2026-12-02 12:00")
    assert has_element?(view, "#history-#{event.id} time[datetime]")
    view |> element(toggle) |> render_click()
    refute has_element?(view, "#booking-history-#{booking.id}")

    second_booking =
      Repo.insert!(%Booking{
        user_id: member.id,
        service_id: service.id,
        status: :cancelled,
        starts_at: ~N[2026-12-03 10:00:00],
        ends_at: ~N[2026-12-03 11:00:00],
        contact_name: "Member",
        contact_phone: "0701234567"
      })

    second_event = Audit.record!(second_booking, Scope.for_user(admin), "cancelled")
    send(view.pid, :bookings_changed)
    view |> element(toggle) |> render_click()
    view |> element("#booking-history-toggle-#{second_booking.id}") |> render_click()
    refute has_element?(view, "#booking-history-#{booking.id}")
    assert has_element?(view, "#history-#{second_event.id}")

    {:ok, member_view, _} =
      build_conn() |> log_in_user(member) |> live(~p"/dashboard/bookings?view=all")

    refute has_element?(member_view, toggle)
    render_click(member_view, "history", %{"id" => booking.id})
    refute has_element?(member_view, "#history-#{event.id}")
    refute has_element?(member_view, "#booking-history-#{booking.id}")
  end
end
