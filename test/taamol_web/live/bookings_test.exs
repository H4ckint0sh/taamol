defmodule TaamolWeb.BookingsTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.{Bookings, Repo}
  alias Taamol.Bookings.Service

  setup do
    premises =
      service_fixture(%{name_sv: "Lokal för khatm", resource: :premises, duration_minutes: 120})

    party =
      service_fixture(%{name_sv: "Lokal för fest", resource: :premises, duration_minutes: 120})

    imam = service_fixture(%{name_sv: "Imam för nikah", resource: :imam, duration_minutes: 60})
    member = user_fixture(%{name: "Fatemeh"})
    admin = user_fixture() |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

    %{
      premises: premises,
      party: party,
      imam: imam,
      member: member,
      admin: admin,
      day: Date.add(Date.utc_today(), 7)
    }
  end

  defp service_fixture(attrs) do
    %Service{}
    |> Service.changeset(Map.merge(%{name_fa: "سرویس", icon: "hero-heart"}, attrs))
    |> Repo.insert!()
  end

  defp at(day, time), do: NaiveDateTime.new!(day, time)

  defp request!(member, service, starts_at) do
    {:ok, booking} =
      Bookings.request_booking(Scope.for_user(member), service, starts_at, %{
        "contact_name" => member.name,
        "contact_phone" => "070 123 45 67"
      })

    booking
  end

  describe "availability" do
    test "follows opening hours and needs a day's notice", %{premises: premises, day: day} do
      slots = Bookings.available_slots(premises, day)
      assert hd(slots).starts_at == at(day, ~T[09:00:00])
      # a 2-hour booking must end by 22:00
      assert List.last(slots).starts_at == at(day, ~T[20:00:00])
      assert Bookings.available_slots(premises, Date.utc_today()) == []

      assert %{total: 0} =
               Bookings.availability(premises, Date.utc_today(), Date.utc_today())[
                 Date.utc_today()
               ]
    end

    test "confirmed bookings block the same resource only", ctx do
      %{premises: premises, party: party, imam: imam, member: member, admin: admin, day: day} =
        ctx

      booking = request!(member, premises, at(day, ~T[12:00:00]))

      # a pending request doesn't block
      assert Enum.any?(
               Bookings.available_slots(party, day),
               &(&1.starts_at == at(day, ~T[12:00:00]))
             )

      {:ok, _} = Bookings.accept_booking(Scope.for_user(admin), booking)
      starts = Enum.map(Bookings.available_slots(party, day), & &1.starts_at)
      # the party hall uses the same premises: 10:30–13:30 starts now overlap
      refute at(day, ~T[11:00:00]) in starts
      refute at(day, ~T[13:30:00]) in starts
      assert at(day, ~T[14:00:00]) in starts
      # the imam is a different resource
      assert Enum.any?(
               Bookings.available_slots(imam, day),
               &(&1.starts_at == at(day, ~T[12:00:00]))
             )
    end

    test "requests must be for a free time", %{premises: premises, member: member, day: day} do
      assert {:error, :unavailable} =
               Bookings.request_booking(
                 Scope.for_user(member),
                 premises,
                 at(day, ~T[06:00:00]),
                 %{}
               )
    end
  end

  describe "booking from the calendar" do
    test "members pick a service, a day and a time and send a request", ctx do
      %{conn: conn, imam: imam, member: member, day: day, admin: admin} = ctx
      conn = log_in_user(conn, member)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/calendar?mode=book&service=#{imam.id}&date=#{Date.to_iso8601(day)}&month=#{Calendar.strftime(day, "%Y-%m")}"
        )

      assert has_element?(view, "#day-cell-#{day}", "free")

      view |> element("#slot-1500") |> render_click()
      assert has_element?(view, "#booking-request", "15:00–16:00")

      view
      |> form("#booking-form",
        booking: %{contact_name: "Fatemeh", contact_phone: "070 123 45 67", guests: "20"}
      )
      |> render_submit()

      assert has_element?(view, "#booking-requested")

      assert [%{status: :pending, guests: 20} = booking] =
               Bookings.list_my_bookings(Scope.for_user(member))

      assert booking.starts_at == at(day, ~T[15:00:00])
      admin_email = admin.email
      assert_received {:email, %{to: [{"", ^admin_email}]}}
    end

    test "guests see free times but must log in to book", %{
      conn: conn,
      premises: premises,
      day: day
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/calendar?mode=book&service=#{premises.id}&date=#{Date.to_iso8601(day)}&month=#{Calendar.strftime(day, "%Y-%m")}"
        )

      view |> element("#slot-0900") |> render_click()
      assert has_element?(view, "#booking-login")
      refute has_element?(view, "#booking-form")
    end

    test "confirmed bookings show in the calendar without personal details", ctx do
      %{conn: conn, premises: premises, member: member, admin: admin, day: day} = ctx
      booking = request!(member, premises, at(day, ~T[18:00:00]))
      {:ok, _} = Bookings.accept_booking(Scope.for_user(admin), booking)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/calendar?date=#{Date.to_iso8601(day)}&month=#{Calendar.strftime(day, "%Y-%m")}"
        )

      assert has_element?(view, "#day-booking-#{booking.id}", "Lokal för khatm")
      refute has_element?(view, "#day-booking-#{booking.id}", "Fatemeh")

      {:ok, view, _html} =
        build_conn()
        |> log_in_user(member)
        |> live(
          ~p"/calendar?date=#{Date.to_iso8601(day)}&month=#{Calendar.strftime(day, "%Y-%m")}"
        )

      assert has_element?(view, "#day-booking-#{booking.id}", "Fatemeh")
    end
  end

  describe "deciding" do
    test "admins accept, refuse clashes and decline", ctx do
      %{conn: conn, premises: premises, party: party, member: member, admin: admin, day: day} =
        ctx

      first = request!(member, premises, at(day, ~T[12:00:00]))
      clash = request!(member, party, at(day, ~T[12:30:00]))

      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/dashboard/bookings")
      assert has_element?(view, "#pending-bookings", "2")

      view |> element("#respond-#{first.id}") |> render_click()

      view
      |> form("#decide-form-#{first.id}", %{"message" => "Welcome"})
      |> render_submit(%{"decision" => "accept"})

      assert %{status: :confirmed, admin_message: "Welcome"} = Repo.reload!(first)

      assert {:error, :conflict} =
               Bookings.accept_booking(Scope.for_user(admin), Repo.reload!(clash))

      assert has_element?(view, "#conflict-#{clash.id}")

      view |> element("#respond-#{clash.id}") |> render_click()
      view |> form("#decide-form-#{clash.id}") |> render_submit(%{"decision" => "decline"})
      assert %{status: :declined} = Repo.reload!(clash)
    end

    test "admins offer another time and the member accepts it", ctx do
      %{conn: conn, imam: imam, member: member, admin: admin, day: day} = ctx
      booking = request!(member, imam, at(day, ~T[10:00:00]))
      new_day = Date.add(day, 1)

      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/dashboard/bookings")
      view |> element("#respond-#{booking.id}") |> render_click()

      view
      |> element("#offer-date-#{booking.id}")
      |> render_change(%{
        "booking_id" => booking.id,
        "offer" => %{"date" => Date.to_iso8601(new_day)}
      })

      assert has_element?(view, "#offer-slot-#{booking.id} option", "14:00–15:00")

      view
      |> form("#decide-form-#{booking.id}", %{"slot" => "#{new_day}T14:00"})
      |> render_submit(%{"decision" => "offer"})

      assert %{status: :proposed, proposed_starts_at: proposed} = Repo.reload!(booking)
      assert proposed == at(new_day, ~T[14:00:00])

      {:ok, mine, _html} = build_conn() |> log_in_user(member) |> live(~p"/dashboard/bookings")
      assert has_element?(mine, "#proposal-#{booking.id}")
      mine |> element("#accept-offer-#{booking.id}") |> render_click()

      assert %{status: :confirmed, starts_at: ^proposed, proposed_starts_at: nil} =
               Repo.reload!(booking)
    end

    test "members cancel, and only admins can decide", ctx do
      %{conn: conn, premises: premises, member: member, day: day} = ctx
      booking = request!(member, premises, at(day, ~T[16:00:00]))

      assert {:error, :forbidden} = Bookings.accept_booking(Scope.for_user(member), booking)

      {:ok, view, _html} = conn |> log_in_user(member) |> live(~p"/dashboard/bookings")
      refute has_element?(view, "#respond-#{booking.id}")
      view |> element("#cancel-#{booking.id}") |> render_click()
      assert %{status: :cancelled} = Repo.reload!(booking)
    end

    test "only admins manage booking services", %{conn: conn, member: member, admin: admin} do
      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(member) |> live(~p"/dashboard/booking-services")

      {:ok, view, _html} =
        build_conn() |> log_in_user(admin) |> live(~p"/dashboard/booking-services")

      view
      |> form("#service-form",
        service: %{
          name_sv: "Koranläsning",
          name_fa: "قرآن‌خوانی",
          resource: "imam",
          duration_minutes: "90",
          icon: "hero-book-open"
        }
      )
      |> render_submit()

      assert Enum.any?(Bookings.list_services(), &(&1.name_sv == "Koranläsning"))
    end
  end
end
