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

  defp memorial_service do
    service_fixture(%{
      name_sv: "Lokal för minnesceremoni (khatm)",
      resource: :premises,
      opens_at: ~T[08:00:00],
      closes_at: ~T[20:00:00],
      duration_minutes: 720
    })
  end

  defp request!(member, service, starts_at) do
    {:ok, booking} =
      Bookings.request_booking(Scope.for_user(member), service, starts_at, %{
        "contact_name" => member.name,
        "contact_phone" => "070 123 45 67"
      })

    booking
  end

  describe "availability" do
    test "memorial ceremonies reserve the entire day from 08:00 to 20:00", ctx do
      %{member: member, admin: admin, day: day, party: party} = ctx
      service = memorial_service()
      start = at(day, ~T[08:00:00])
      finish = at(day, ~T[20:00:00])

      assert [%{starts_at: ^start, ends_at: ^finish}] = Bookings.available_slots(service, day)
      assert %{free: 1, total: 1} = Bookings.availability(service, day, day)[day]

      assert {:error, :unavailable} =
               Bookings.request_booking(
                 Scope.for_user(member),
                 service,
                 at(day, ~T[08:30:00]),
                 %{}
               )

      booking = request!(member, service, start)
      assert booking.ends_at == finish

      assert {:error, :unavailable} =
               Bookings.propose_time(
                 Scope.for_user(admin),
                 booking,
                 at(Date.add(day, 1), ~T[09:00:00])
               )

      assert {:ok, _} = Bookings.accept_booking(Scope.for_user(admin), booking)
      assert Bookings.available_slots(service, day) == []

      refute Enum.any?(
               Bookings.available_slots(party, day),
               &(&1.starts_at == at(day, ~T[19:30:00]))
             )

      assert Enum.any?(
               Bookings.available_slots(party, day),
               &(&1.starts_at == at(day, ~T[20:00:00]))
             )
    end

    test "service hours must fit the booking duration", %{admin: admin, imam: imam} do
      scope = Scope.for_user(admin)

      assert {:error, changeset} =
               Bookings.update_service(scope, imam, %{opens_at: "20:00", closes_at: "08:00"})

      assert Keyword.has_key?(changeset.errors, :closes_at)

      assert {:error, changeset} =
               Bookings.update_service(scope, imam, %{opens_at: "08:00", closes_at: "08:30"})

      assert Keyword.has_key?(changeset.errors, :duration_minutes)

      assert {:ok, service} =
               Bookings.update_service(scope, imam, %{opens_at: "08:00", closes_at: "20:00"})

      assert service.opens_at == ~T[08:00:00]
      assert service.closes_at == ~T[20:00:00]
    end

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

    test "day status includes closed days and the booking horizon", %{imam: imam} do
      today = Date.utc_today()
      future = Date.add(today, 366)
      assert %{^today => false} = Bookings.bookable_days([imam], today, today)
      assert %{^future => false} = Bookings.bookable_days([imam], future, future)
      assert %{^today => false} = Bookings.bookable_days([], today, today)
    end
  end

  describe "booking from the calendar" do
    test "a memorial day is preselected and requested as 08:00–20:00", %{
      conn: conn,
      member: member,
      day: day
    } do
      service = memorial_service()
      conn = log_in_user(conn, member)

      {:ok, view, _} =
        live(
          conn,
          ~p"/calendar?mode=book&service=#{service.id}&month=#{Calendar.strftime(day, "%Y-%m")}"
        )

      view |> element("#day-cell-#{day}") |> render_click()
      assert has_element?(view, "#booking-time option[selected][value='08:00']", "08:00–20:00")
      refute has_element?(view, "#booking-time option[value='08:30']")

      view
      |> form("#booking-form", booking: %{contact_name: "Fatemeh", contact_phone: "0701234567"})
      |> render_submit()

      assert has_element?(view, "#booking-requested")

      assert [%{starts_at: start, ends_at: finish}] =
               Bookings.list_my_bookings(Scope.for_user(member))

      assert start == at(day, ~T[08:00:00])
      assert finish == at(day, ~T[20:00:00])
    end

    test "event changes do not reset a booking form", ctx do
      %{conn: conn, imam: imam, member: member, day: day, admin: admin} = ctx
      conn = log_in_user(conn, member)

      {:ok, view, _} =
        live(
          conn,
          ~p"/calendar?mode=book&service=#{imam.id}&date=#{Date.to_iso8601(day)}&month=#{Calendar.strftime(day, "%Y-%m")}"
        )

      view |> element("#day-cell-#{day}") |> render_click()
      assert has_element?(view, "#booking-dialog[role=dialog][aria-modal=true]")

      view
      |> form("#booking-form",
        service: imam.id,
        slot: "15:00",
        booking: %{contact_name: "Draft name", contact_phone: "bad"}
      )
      |> render_submit()

      assert has_element?(view, "#booking_contact_name[value='Draft name']")
      assert has_element?(view, "#booking_contact_phone[value='bad']")

      assert {:ok, _} =
               Taamol.Events.create_event(Scope.for_user(admin), %{
                 title: "Another event",
                 starts_at: "#{day}T18:00"
               })

      assert has_element?(view, "#booking_contact_name[value='Draft name']")
      assert has_element?(view, "#booking_contact_phone[value='bad']")
      assert has_element?(view, "#booking-time option[selected]", "15:00")
    end

    test "calendar controls switch modes and navigate dates", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/calendar?month=2026-06")

      assert has_element?(
               view,
               "#calendar-controls #calendar-mode.rounded-full #mode-events[aria-current=page]"
             )

      assert has_element?(view, "#calendar-mode-indicator[phx-hook=SegmentedIndicator]")
      assert has_element?(view, "#calendar-today.rounded-full")
      assert has_element?(view, "#calendar-prev.rounded-full")
      assert has_element?(view, "#calendar-next.rounded-full")

      view |> element("#mode-book") |> render_click()
      assert has_element?(view, "#mode-book[aria-current=page]")
      assert has_element?(view, "#booking-instructions")
      refute has_element?(view, "#booking-dialog")

      view |> element("#calendar-next") |> render_click()
      assert has_element?(view, "#day-cell-2026-07-15")
      assert has_element?(view, "#mode-book[aria-current=page]")

      view |> element("#calendar-today") |> render_click()
      assert has_element?(view, "#day-cell-#{Date.utc_today()}[aria-current=date]")

      view |> element("#mode-events") |> render_click()
      assert has_element?(view, "#mode-events[aria-current=page]")
      refute has_element?(view, "#booking-instructions")
    end

    test "members pick a service, a day and a time and send a request", ctx do
      %{conn: conn, imam: imam, member: member, day: day, admin: admin} = ctx
      conn = log_in_user(conn, member)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/calendar?mode=book&service=#{imam.id}&date=#{Date.to_iso8601(day)}&month=#{Calendar.strftime(day, "%Y-%m")}"
        )

      assert has_element?(view, "#day-availability-#{day}", "Available")

      view |> element("#day-cell-#{day}") |> render_click()
      assert has_element?(view, "#booking-dialog #booking-time option", "15:00–16:00")

      view
      |> form("#booking-form",
        service: imam.id,
        slot: "15:00",
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

      view |> element("#day-cell-#{day}") |> render_click()
      assert has_element?(view, "#booking-login")
      assert has_element?(view, "#booking-time option", "09:00")
      refute has_element?(view, "#send-booking")
    end

    test "all calendar days show availability, independent of the selected service", ctx do
      %{
        conn: conn,
        premises: premises,
        party: party,
        imam: imam,
        member: member,
        admin: admin,
        day: day
      } = ctx

      {:ok, premises} =
        Bookings.update_service(Scope.for_user(admin), premises, %{duration_minutes: 720})

      {:ok, _party} =
        Bookings.update_service(Scope.for_user(admin), party, %{duration_minutes: 720})

      booking = request!(member, premises, at(day, ~T[09:00:00]))
      {:ok, _} = Bookings.accept_booking(Scope.for_user(admin), booking)

      {:ok, view, _} =
        live(
          conn,
          ~p"/calendar?month=#{Calendar.strftime(day, "%Y-%m")}&date=#{Date.to_iso8601(day)}"
        )

      assert has_element?(view, "#day-availability-#{day}", "Available")
      assert has_element?(view, "#calendar-grid [id^=day-cell-]:has([id^=day-availability-])")

      refute has_element?(
               view,
               "#calendar-grid [id^=day-cell-]:not(:has([id^=day-availability-]))"
             )

      today = Date.utc_today()
      {:ok, today_view, _} = live(conn, ~p"/calendar?month=#{Calendar.strftime(today, "%Y-%m")}")
      assert has_element?(today_view, "#day-availability-#{today}", "Unavailable")

      view |> element("#mode-book") |> render_click()
      view |> element("#day-cell-#{day}") |> render_click()
      assert has_element?(view, "#booking-service option[selected][value='#{imam.id}']")

      view |> form("#booking-form", service: premises.id) |> render_change()
      assert has_element?(view, "#booking-unavailable")
      assert has_element?(view, "#day-availability-#{day}", "Available")
    end

    test "a day in an adjacent month opens the correct date and the dialog closes", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/calendar?mode=book&month=2026-06")
      view |> element("#day-cell-2026-07-01") |> render_click()
      assert has_element?(view, "#day-cell-2026-07-01[aria-current=date]")
      assert has_element?(view, "#booking-dialog", "July")
      view |> element("#booking-dialog-close") |> render_click()
      refute has_element?(view, "#booking-dialog")
      assert has_element?(view, "#day-cell-2026-07-01[aria-current=date]")
    end

    test "changing services preserves the draft and refreshes available times", ctx do
      %{conn: conn, imam: imam, premises: premises, member: member, day: day} = ctx

      {:ok, view, _} =
        conn
        |> log_in_user(member)
        |> live(~p"/calendar?mode=book&month=#{Calendar.strftime(day, "%Y-%m")}")

      view |> element("#day-cell-#{day}") |> render_click()

      view
      |> form("#booking-form",
        service: imam.id,
        slot: "15:00",
        booking: %{contact_name: "Draft name", contact_phone: "0701234567"}
      )
      |> render_change()

      view
      |> form("#booking-form",
        service: premises.id,
        slot: "15:00",
        booking: %{contact_name: "Draft name", contact_phone: "0701234567"}
      )
      |> render_change()

      assert has_element?(view, "#booking_contact_name[value='Draft name']")
      assert has_element?(view, "#booking-time option[selected]", "15:00–17:00")
    end

    test "availability updates while a booking dialog is open", ctx do
      %{
        conn: conn,
        imam: imam,
        premises: premises,
        party: party,
        member: member,
        admin: admin,
        day: day
      } = ctx

      scope = Scope.for_user(admin)
      {:ok, premises} = Bookings.update_service(scope, premises, %{duration_minutes: 720})
      {:ok, _} = Bookings.update_service(scope, party, %{duration_minutes: 720})
      {:ok, imam} = Bookings.update_service(scope, imam, %{duration_minutes: 720})
      {:ok, _} = Bookings.accept_booking(scope, request!(member, premises, at(day, ~T[09:00:00])))
      imam_booking = request!(member, imam, at(day, ~T[09:00:00]))

      {:ok, view, _} =
        conn
        |> log_in_user(member)
        |> live(~p"/calendar?mode=book&month=#{Calendar.strftime(day, "%Y-%m")}")

      view |> element("#day-cell-#{day}") |> render_click()

      view
      |> form("#booking-form",
        service: imam.id,
        slot: "09:00",
        booking: %{contact_name: "Draft name", contact_phone: "0701234567"}
      )
      |> render_change()

      {:ok, confirmed} = Bookings.accept_booking(scope, imam_booking)
      assert has_element?(view, "#day-availability-#{day}", "Unavailable")
      assert has_element?(view, "#booking-error", "Availability changed")
      assert has_element?(view, "#booking_contact_name[value='Draft name']")
      assert has_element?(view, "#booking-unavailable")

      {:ok, _} = Bookings.cancel_booking(Scope.for_user(member), confirmed)
      assert has_element?(view, "#day-availability-#{day}", "Available")
      assert has_element?(view, "#booking-time option", "09:00")
      assert has_element?(view, "#booking_contact_name[value='Draft name']")
    end

    test "rejects unavailable or deactivated services without losing the draft", ctx do
      %{conn: conn, imam: imam, member: member, admin: admin, day: day} = ctx

      {:ok, view, _} =
        conn
        |> log_in_user(member)
        |> live(~p"/calendar?mode=book&month=#{Calendar.strftime(day, "%Y-%m")}")

      view |> element("#day-cell-#{day}") |> render_click()

      render_submit(view, "request", %{
        "service" => imam.id,
        "slot" => "03:00",
        "booking" => %{"contact_name" => "Draft name", "contact_phone" => "0701234567"}
      })

      assert has_element?(view, "#booking-error", "no longer available")
      assert has_element?(view, "#booking_contact_name[value='Draft name']")
      assert Bookings.list_my_bookings(Scope.for_user(member)) == []

      assert {:ok, _} = Bookings.update_service(Scope.for_user(admin), imam, %{active: false})
      refute has_element?(view, "#booking-service option[value='#{imam.id}']")
      assert has_element?(view, "#booking-error", "Availability changed")
      assert has_element?(view, "#booking_contact_name[value='Draft name']")
    end

    test "confirmed bookings appear live in the event calendar", ctx do
      %{conn: conn, imam: imam, member: member, admin: admin, day: day} = ctx
      booking = request!(member, imam, at(day, ~T[10:00:00]))

      {:ok, view, _} =
        live(
          conn,
          ~p"/calendar?month=#{Calendar.strftime(day, "%Y-%m")}&date=#{Date.to_iso8601(day)}"
        )

      refute has_element?(view, "#day-booking-#{booking.id}")

      assert {:ok, confirmed} = Bookings.accept_booking(Scope.for_user(admin), booking)
      assert has_element?(view, "#day-booking-#{booking.id}")
      refute has_element?(view, "#day-booking-#{booking.id}", member.name)

      assert {:ok, _} = Bookings.cancel_booking(Scope.for_user(member), confirmed)
      refute has_element?(view, "#day-booking-#{booking.id}")
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
    test "booking views use a segmented control and switch filters", %{conn: conn, admin: admin} do
      {:ok, view, _} = conn |> log_in_user(admin) |> live(~p"/dashboard/bookings")

      assert has_element?(
               view,
               "#booking-views.rounded-full #booking-view-requests[aria-current=page]"
             )

      view |> element("#booking-view-upcoming") |> render_click()
      assert has_element?(view, "#booking-view-upcoming[aria-current=page]")
      refute has_element?(view, "#booking-view-requests[aria-current=page]")

      view |> element("#booking-view-mine") |> render_click()
      assert has_element?(view, "#booking-view-mine[aria-current=page]")
    end

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

      assert has_element?(view, "#service_opens_at[type=time]")
      assert has_element?(view, "#service_closes_at[type=time]")

      view
      |> form("#service-form",
        service: %{
          name_sv: "Koranläsning",
          name_fa: "قرآن‌خوانی",
          resource: "imam",
          duration_minutes: "90",
          icon: "hero-book-open",
          opens_at: "08:00",
          closes_at: "20:00"
        }
      )
      |> render_submit()

      assert Enum.any?(
               Bookings.list_services(),
               &(&1.name_sv == "Koranläsning" and &1.opens_at == ~T[08:00:00] and
                   &1.closes_at == ~T[20:00:00])
             )
    end
  end
end
