defmodule Taamol.Bookings.AuditTest do
  use Taamol.DataCase, async: true

  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.Bookings.{Audit, AuditEvent, Booking, Service}
  alias Taamol.Repo

  setup do
    member = user_fixture()
    admin = user_fixture(%{name: "Original administrator"}) |> admin!()
    service = service!()
    booking = booking!(member, service)
    %{member: member, admin: admin, booking: booking}
  end

  test "records ordered snapshots, only retaining permitted times", ctx do
    %{admin: admin, member: member, booking: booking} = ctx
    scope = Scope.for_user(admin)

    first =
      Audit.record!(booking, Scope.for_user(member), "requested", %{
        starts_at: ~N[2026-12-01 10:00:00],
        notes: "must not be stored",
        contact_phone: "private"
      })

    second =
      Audit.record!(booking, scope, :proposed, %{
        new_starts_at: ~N[2026-12-02 12:00:00],
        new_ends_at: "2026-12-02T13:00:00",
        message: "private"
      })

    assert first.details == %{"starts_at" => "2026-12-01T10:00:00"}

    assert second.details == %{
             "new_starts_at" => "2026-12-02T12:00:00",
             "new_ends_at" => "2026-12-02T13:00:00"
           }

    assert %DateTime{time_zone: "Etc/UTC"} = second.inserted_at
    assert {:ok, [^second, ^first]} = Audit.list_for_booking(scope, booking)
    assert second.actor_name == "Original administrator"

    admin |> Ecto.Changeset.change(name: "New name") |> Repo.update!()

    assert {:ok, [%{actor_name: "Original administrator"} | _]} =
             Audit.list_for_booking(scope, booking)

    Repo.delete!(admin)
    event = Repo.get!(AuditEvent, second.id)
    assert event.actor_id == nil
    assert event.actor_name == "Original administrator"
  end

  test "requires a currently authorized administrator, not stale or forged roles", ctx do
    %{admin: admin, member: member, booking: booking} = ctx
    assert {:error, :forbidden} = Audit.list_for_booking(nil, booking)
    assert {:error, :forbidden} = Audit.list_for_booking(Scope.for_user(member), booking)

    assert {:error, :forbidden} =
             Audit.list_for_booking(Scope.for_user(%{member | role: :admin}), booking)

    admin |> Ecto.Changeset.change(role: :user) |> Repo.update!()
    assert {:error, :forbidden} = Audit.list_for_booking(Scope.for_user(admin), booking)
  end

  test "event changes and direct deletion are rejected while booking deletion remains possible",
       %{admin: admin, booking: booking} do
    event = Audit.record!(booking, Scope.for_user(admin), "confirmed")

    assert_raise Postgrex.Error, ~r/immutable/, fn ->
      Repo.transaction(
        fn -> event |> Ecto.Changeset.change(action: "declined") |> Repo.update!() end,
        mode: :savepoint
      )
    end

    assert_raise Postgrex.Error, ~r/immutable/, fn ->
      Repo.transaction(fn -> Repo.delete!(event) end, mode: :savepoint)
    end

    Repo.delete!(booking)
    refute Repo.get(AuditEvent, event.id)
  end

  test "recording participates in the caller's transaction", %{admin: admin, booking: booking} do
    assert {:error, :rollback} =
             Repo.transaction(fn ->
               Audit.record!(booking, Scope.for_user(admin), "confirmed")
               Repo.rollback(:rollback)
             end)

    assert {:ok, []} = Audit.list_for_booking(Scope.for_user(admin), booking)
  end

  defp admin!(user), do: user |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

  defp service! do
    %Service{}
    |> Service.changeset(%{name_sv: "Test", name_fa: "Test", icon: "hero-heart"})
    |> Repo.insert!()
  end

  defp booking!(user, service) do
    Repo.insert!(%Booking{
      user_id: user.id,
      service_id: service.id,
      starts_at: ~N[2026-12-01 10:00:00],
      ends_at: ~N[2026-12-01 11:00:00],
      contact_name: "Member",
      contact_phone: "0701234567"
    })
  end
end
