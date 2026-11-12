defmodule Taamol.EventsTest do
  use Taamol.DataCase, async: true

  import Taamol.AccountsFixtures

  alias Taamol.Accounts.Scope
  alias Taamol.Events

  defp admin_scope do
    user_fixture() |> Ecto.Changeset.change(role: :admin) |> Repo.update!() |> Scope.for_user()
  end

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{"title" => "Majlis", "kind" => "community", "starts_at" => "2026-11-20T18:00"},
      overrides
    )
  end

  test "admins can create, update and delete events" do
    scope = admin_scope()

    assert {:ok, event} = Events.create_event(scope, attrs())
    assert event.starts_at == ~N[2026-11-20 18:00:00]
    assert event.creator_id == scope.user.id

    assert {:ok, event} = Events.update_event(scope, event, %{"title" => "Updated"})
    assert event.title == "Updated"

    assert {:ok, _} = Events.delete_event(scope, event)
    assert Events.list_events_between(~D[2026-11-01], ~D[2026-11-30]) == []
  end

  test "non-admins and stale admin scopes are refused" do
    user = user_fixture()
    assert {:error, :forbidden} = Events.create_event(Scope.for_user(user), attrs())
    assert {:error, :forbidden} = Events.create_event(nil, attrs())
    # role changed in memory only: the database still says :user
    assert {:error, :forbidden} =
             Events.create_event(Scope.for_user(%{user | role: :admin}), attrs())
  end

  test "validates the end is after the start" do
    assert {:error, changeset} =
             Events.create_event(admin_scope(), attrs(%{"ends_at" => "2026-11-20T17:00"}))

    assert %{ends_at: [_]} = errors_on(changeset)
  end

  test "merges holidays and events, including multi-day events" do
    scope = admin_scope()

    {:ok, _} =
      Events.create_event(
        scope,
        attrs(%{
          "title" => "Camp",
          "starts_at" => "2026-06-24T10:00",
          "ends_at" => "2026-06-26T12:00"
        })
      )

    by_day = Events.entries_by_day(~D[2026-06-24], ~D[2026-06-26])
    assert Enum.any?(by_day[~D[2026-06-25]], &(&1.source == :holiday and &1.key == :ashura))

    for day <- [~D[2026-06-24], ~D[2026-06-25], ~D[2026-06-26]] do
      assert Enum.any?(by_day[day], &(&1.source == :event and &1.event.title == "Camp"))
    end
  end

  test "upcoming lists what comes next" do
    upcoming = Events.upcoming(today: ~D[2026-06-20], limit: 3)
    assert length(upcoming) == 3
    assert Enum.any?(upcoming, &(&1.key == :ashura))
    assert Enum.all?(upcoming, &(Date.compare(&1.first_day, ~D[2026-06-20]) != :lt))
  end
end
