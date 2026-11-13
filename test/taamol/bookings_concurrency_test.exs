defmodule Taamol.BookingsConcurrencyTest do
  use ExUnit.Case, async: false

  import Taamol.AccountsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Taamol.Accounts.{Scope, User}
  alias Taamol.Bookings
  alias Taamol.Bookings.Service
  alias Taamol.Repo

  test "simultaneous approvals cannot confirm overlapping requests" do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    member = user_fixture()
    admin = user_fixture() |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

    service =
      %Service{}
      |> Service.changeset(%{
        name_sv: "Concurrent test",
        name_fa: "Concurrent test",
        resource: :other
      })
      |> Repo.insert!()

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete!(Repo.get!(User, member.id))
        Repo.delete!(Repo.get!(User, admin.id))
        Repo.delete!(Repo.get!(Service, service.id))
      end)
    end)

    start = NaiveDateTime.new!(Date.add(Date.utc_today(), 7), ~T[10:00:00])
    attrs = %{contact_name: "Member", contact_phone: "0701234567"}
    {:ok, first} = Bookings.request_booking(Scope.for_user(member), service, start, attrs)
    {:ok, second} = Bookings.request_booking(Scope.for_user(member), service, start, attrs)
    :ok = Sandbox.checkin(Repo)

    supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    tasks =
      for booking <- [first, second] do
        Task.Supervisor.async_nolink(supervisor, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})
            receive do: (:proceed -> Bookings.accept_booking(Scope.for_user(admin), booking))
          end)
        end)
      end

    pids =
      for _ <- tasks,
          do:
            (
              assert_receive {:ready, pid}
              pid
            )

    Enum.each(pids, &send(&1, :proceed))

    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, %{status: :confirmed}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :conflict}, &1)) == 1
  end
end
