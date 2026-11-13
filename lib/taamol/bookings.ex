defmodule Taamol.Bookings do
  @moduledoc """
  Booking the association's premises, the imam and other services, from the
  calendar.

  Availability is "smart": a time is free when it is within opening hours, far
  enough ahead, and doesn't overlap a confirmed booking or a resource-reserving
  event. Pending requests don't block a time; an administrator decides.
  """

  import Ecto.Query

  alias Taamol.Accounts
  alias Taamol.Accounts.{Scope, User}
  alias Taamol.Bookings.{Audit, Booking, Lock, Notifier, Service, Timezone}
  alias Taamol.Events.Event
  alias Taamol.Repo

  @opens ~T[09:00:00]
  @closes ~T[22:00:00]
  @step_minutes 30
  @min_notice_hours 24
  @max_days_ahead 365

  @doc "Subscribes to changes that affect calendar availability."
  def subscribe_availability, do: Phoenix.PubSub.subscribe(Taamol.PubSub, "bookings:availability")

  @doc "Subscribes a signed-in user to their booking changes, or all changes for administrators."
  def subscribe_changes(%Scope{user: %User{id: user_id}} = scope) do
    topic =
      if Accounts.admin?(scope) and match?(%User{role: :admin}, Repo.get(User, user_id)),
        do: "bookings:admins",
        else: "bookings:user:#{user_id}"

    Phoenix.PubSub.subscribe(Taamol.PubSub, topic)
  end

  def subscribe_changes(_scope), do: {:error, :forbidden}

  defp notify_bookings({:ok, %Booking{user_id: user_id}} = result) do
    :ok = Phoenix.PubSub.broadcast(Taamol.PubSub, "bookings:admins", :bookings_changed)
    :ok = Phoenix.PubSub.broadcast(Taamol.PubSub, "bookings:user:#{user_id}", :bookings_changed)
    result
  end

  defp notify_bookings(result), do: result

  defp notify_availability({:ok, _} = result) do
    :ok =
      Phoenix.PubSub.broadcast_from(
        Taamol.PubSub,
        self(),
        "bookings:availability",
        :booking_availability_changed
      )

    result
  end

  defp notify_availability(result), do: result

  ## Services

  @doc "Bookable services in display order (`active_only: false` for all)."
  def list_services(opts \\ []) do
    Service
    |> then(fn q ->
      if Keyword.get(opts, :active_only, true), do: where(q, [s], s.active), else: q
    end)
    |> order_by([s], asc: s.position, asc: s.name_sv)
    |> Repo.all()
  end

  def get_service(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Service, uuid)
      :error -> nil
    end
  end

  def change_service(%Service{} = service, attrs \\ %{}), do: Service.changeset(service, attrs)

  def create_service(scope, attrs) do
    as_admin(scope, fn _ ->
      Repo.transact(fn ->
        Lock.acquire()
        %Service{} |> Service.changeset(attrs) |> Repo.insert()
      end)
    end)
    |> notify_availability()
  end

  def update_service(scope, %Service{} = service, attrs) do
    as_admin(scope, fn _ ->
      Repo.transact(fn ->
        Lock.acquire()
        service = Repo.get!(Service, service.id)
        changeset = Service.changeset(service, attrs)

        with {:ok, updated} <- Repo.update(changeset) do
          resource_changed? = updated.resource != service.resource

          conflict? =
            resource_changed? and
              from(b in Booking, where: b.service_id == ^updated.id and b.status == :confirmed)
              |> Repo.all()
              |> Enum.any?(fn booking -> conflicts(booking) != [] end)

          if conflict? do
            {:error,
             Ecto.Changeset.add_error(changeset, :resource, "conflicts with a booking or event")}
          else
            if resource_changed? and updated.resource == :imam do
              from(b in Booking, where: b.service_id == ^updated.id)
              |> Repo.update_all(set: [private_calendar: true])
            end

            {:ok, updated}
          end
        end
      end)
    end)
    |> notify_availability()
  end

  ## Availability

  @doc "Default service hours and the minimum booking notice."
  def rules, do: %{opens: @opens, closes: @closes, min_notice_hours: @min_notice_hours}

  @doc "Free start times for a service on a date: `[%{starts_at:, ends_at:}]`."
  def available_slots(%Service{} = service, %Date{} = date) do
    availability_data(service, date, date)[date].slots
  end

  @doc """
  Per-day availability for a range (for the calendar grid):
  `%{date => %{free: n, total: n}}`. Closed or past days have `total: 0`.
  """
  def availability(%Service{} = service, %Date{} = from, %Date{} = to) do
    Map.new(availability_data(service, from, to), fn {date, data} ->
      {date, %{free: length(data.slots), total: data.total}}
    end)
  end

  defp availability_data(service, from, to) do
    utc_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    local_now = Timezone.local(utc_now)
    earliest = NaiveDateTime.add(utc_now, @min_notice_hours * 3600)
    earliest_local = Timezone.local(earliest)
    latest = Date.add(NaiveDateTime.to_date(local_now), @max_days_ahead)
    dates = Date.range(from, to)
    starts = Map.new(dates, fn date -> {date, day_starts(service, date)} end)

    eligible =
      starts
      |> Map.values()
      |> List.flatten()
      |> Timezone.eligible(earliest, service.duration_minutes * 60)

    blocking = blocking_bookings(service, from, to) ++ blocking_events(service.resource, from, to)

    Map.new(dates, fn date ->
      day_starts = Map.fetch!(starts, date)
      total = if bookable_day?(date, earliest_local, latest), do: length(day_starts), else: 0
      slots = slots_for_day(service, date, day_starts, blocking, eligible, latest)
      {date, %{slots: slots, total: total}}
    end)
  end

  @doc "Whether at least one active service has an available time on each day."
  def bookable_days(services, %Date{} = from, %Date{} = to) when is_list(services) do
    Enum.reduce(
      Enum.filter(services, & &1.active),
      Map.new(Date.range(from, to), &{&1, false}),
      fn service, days ->
        Enum.reduce(availability(service, from, to), days, fn {date, %{free: free}}, acc ->
          Map.update!(acc, date, &(&1 or free > 0))
        end)
      end
    )
  end

  defp slots_for_day(service, date, starts, blocking, eligible, latest) do
    for starts_at <- starts,
        ends_at = NaiveDateTime.add(starts_at, service.duration_minutes * 60),
        Date.compare(date, latest) != :gt,
        MapSet.member?(eligible, starts_at),
        not Enum.any?(blocking, &overlaps?(&1, starts_at, ends_at)) do
      %{starts_at: starts_at, ends_at: ends_at}
    end
  end

  # every start time from opening until the booking would end after closing
  defp day_starts(service, date) do
    first = NaiveDateTime.new!(date, service.opens_at)

    last =
      NaiveDateTime.add(
        NaiveDateTime.new!(date, service.closes_at),
        -service.duration_minutes * 60
      )

    if NaiveDateTime.compare(first, last) == :gt do
      []
    else
      count = div(NaiveDateTime.diff(last, first, :minute), @step_minutes)
      for i <- 0..count, do: NaiveDateTime.add(first, i * @step_minutes * 60)
    end
  end

  defp bookable_day?(date, earliest_local, latest) do
    Date.compare(date, NaiveDateTime.to_date(earliest_local)) != :lt and
      Date.compare(date, latest) != :gt
  end

  defp overlaps?(%{starts_at: s, ends_at: e}, starts_at, ends_at),
    do: NaiveDateTime.compare(s, ends_at) == :lt and NaiveDateTime.compare(e, starts_at) == :gt

  # confirmed bookings of the same resource that could overlap the dates
  defp blocking_bookings(%Service{} = service, from, to) do
    from_dt = NaiveDateTime.new!(Date.add(from, -1), ~T[00:00:00])
    to_dt = NaiveDateTime.new!(Date.add(to, 1), ~T[23:59:59])

    from(b in Booking,
      join: s in assoc(b, :service),
      where: b.status == :confirmed and b.starts_at < ^to_dt and b.ends_at > ^from_dt,
      select: %{id: b.id, starts_at: b.starts_at, ends_at: b.ends_at}
    )
    |> same_resource(service)
    |> Repo.all()
  end

  defp same_resource(query, %Service{resource: :other, id: id}),
    do: where(query, [b, _s], b.service_id == ^id)

  defp same_resource(query, %Service{resource: resource}),
    do: where(query, [_b, s], s.resource == ^resource)

  defp blocking_events(:other, _from, _to), do: []

  defp blocking_events(resource, from, to) do
    from_dt = NaiveDateTime.new!(from, ~T[00:00:00])
    to_dt = NaiveDateTime.new!(Date.add(to, 1), ~T[00:00:00])

    from(e in Event,
      where:
        e.booking_resource == ^resource and e.starts_at < ^to_dt and
          coalesce(e.ends_at, e.starts_at) >= ^from_dt
    )
    |> Repo.all()
    |> Enum.map(fn event ->
      {starts_at, ends_at} = Event.booking_interval(event)
      %{id: event.id, starts_at: starts_at, ends_at: ends_at}
    end)
  end

  @doc "Confirmed bookings and resource-reserving events overlapping a time."
  def conflicts(%Booking{} = booking, starts_at \\ nil, ends_at \\ nil) do
    booking = Repo.preload(booking, :service)
    starts_at = starts_at || booking.starts_at
    ends_at = ends_at || booking.ends_at

    from = NaiveDateTime.to_date(starts_at)
    to = NaiveDateTime.to_date(ends_at)

    bookings =
      booking.service
      |> blocking_bookings(from, to)
      |> Enum.reject(&(&1.id == booking.id))

    (bookings ++ blocking_events(booking.service.resource, from, to))
    |> Enum.filter(&overlaps?(&1, starts_at, ends_at))
  end

  @doc "Whether a resource-reserving event conflicts with an existing booking or event."
  def resource_conflict?(resource, starts_at, ends_at, event_id \\ nil) do
    from = NaiveDateTime.to_date(starts_at)
    to = NaiveDateTime.to_date(ends_at)
    service = %Service{resource: resource}

    entries =
      blocking_bookings(service, from, to) ++
        Enum.reject(blocking_events(resource, from, to), &(&1.id == event_id))

    Enum.any?(entries, &overlaps?(&1, starts_at, ends_at))
  end

  ## Members

  @doc "A changeset for the request form."
  def change_request(attrs \\ %{}, service \\ nil),
    do: Booking.request_changeset(%Booking{}, attrs, service)

  @doc """
  Requests a booking. The start time must be one of `available_slots/2`.
  Administrators are emailed.
  """
  def request_booking(
        %Scope{user: %User{id: user_id}} = scope,
        %Service{} = service,
        %NaiveDateTime{} = starts_at,
        attrs
      ) do
    result =
      Repo.transact(fn ->
        Lock.acquire()
        service = get_service(service.id)

        slot =
          if service && service.active do
            Enum.find(
              available_slots(service, NaiveDateTime.to_date(starts_at)),
              &(&1.starts_at == starts_at)
            )
          end

        if slot do
          %Booking{
            user_id: user_id,
            service_id: service.id,
            private_calendar: service.resource == :imam,
            starts_at: slot.starts_at,
            ends_at: slot.ends_at
          }
          |> Booking.request_changeset(attrs, service)
          |> Repo.insert()
          |> record_action(scope, "requested")
        else
          {:error, :unavailable}
        end
      end)

    with {:ok, booking} <- result do
      booking = Repo.preload(booking, [:service, :user])
      Notifier.new_request(admin_emails(), booking)
      notify_bookings({:ok, booking})
    end
  end

  def request_booking(_scope, _service, _starts_at, _attrs), do: {:error, :forbidden}

  @doc "The member's own bookings, upcoming first, then the rest."
  def list_my_bookings(%Scope{user: %User{id: user_id}}) do
    Repo.all(
      from b in Booking,
        where: b.user_id == ^user_id,
        order_by: [desc: b.starts_at],
        preload: [:service]
    )
  end

  def list_my_bookings(_), do: []

  @doc "Accepts or declines the other time an administrator offered."
  def respond_to_proposal(
        %Scope{user: %User{id: user_id}} = scope,
        %Booking{status: :proposed, user_id: user_id} = booking,
        :accept
      ) do
    mutate_booking(booking, fn current ->
      cond do
        current.user_id != user_id or current.status != :proposed ->
          {:error, :invalid_state}

        conflicts(current, current.proposed_starts_at, current.proposed_ends_at) != [] ->
          {:error, :conflict}

        not slot_still_valid?(current, current.proposed_starts_at, current.proposed_ends_at) ->
          {:error, :unavailable}

        true ->
          details =
            time_change(
              current.starts_at,
              current.ends_at,
              current.proposed_starts_at,
              current.proposed_ends_at
            )

          current
          |> Ecto.Changeset.change(
            status: :confirmed,
            starts_at: current.proposed_starts_at,
            ends_at: current.proposed_ends_at,
            proposed_starts_at: nil,
            proposed_ends_at: nil
          )
          |> Repo.update()
          |> record_action(scope, "proposal_accepted", details)
      end
    end)
    |> notify_admins(:accepted_proposal)
    |> notify_bookings()
    |> notify_availability()
  end

  def respond_to_proposal(
        %Scope{user: %User{id: user_id}} = scope,
        %Booking{status: :proposed, user_id: user_id} = booking,
        :decline
      ) do
    mutate_booking(booking, fn current ->
      if current.user_id == user_id and current.status == :proposed do
        current
        |> Ecto.Changeset.change(status: :cancelled)
        |> Repo.update()
        |> record_action(scope, "proposal_declined")
      else
        {:error, :invalid_state}
      end
    end)
    |> notify_admins(:declined_proposal)
    |> notify_bookings()
  end

  def respond_to_proposal(_scope, _booking, _answer), do: {:error, :forbidden}

  @doc "Cancels the member's own open booking."
  def cancel_booking(
        %Scope{user: %User{id: user_id}} = scope,
        %Booking{user_id: user_id, status: status} = booking
      )
      when status in [:pending, :proposed, :confirmed] do
    mutate_booking(booking, fn current ->
      if current.user_id == user_id and current.status in [:pending, :proposed, :confirmed] do
        current
        |> Ecto.Changeset.change(status: :cancelled)
        |> Repo.update()
        |> record_action(scope, "cancelled")
      else
        {:error, :invalid_state}
      end
    end)
    |> notify_admins(:cancelled)
    |> notify_bookings()
    |> notify_availability()
  end

  def cancel_booking(_scope, _booking), do: {:error, :forbidden}

  ## Administrators

  @doc """
  Bookings for administrators. `:filter` is `:pending` (requests and offered
  times waiting for an answer), `:upcoming` (confirmed, from today) or `:all`.
  """
  def list_bookings(scope, filter \\ :pending) do
    as_admin(scope, fn _ ->
      today = NaiveDateTime.new!(Date.utc_today(), ~T[00:00:00])

      query =
        case filter do
          :pending ->
            from b in Booking,
              where: b.status in [:pending, :proposed],
              order_by: [asc: b.starts_at]

          :upcoming ->
            from b in Booking,
              where: b.status == :confirmed and b.starts_at >= ^today,
              order_by: [asc: b.starts_at]

          _ ->
            from b in Booking, order_by: [desc: b.inserted_at]
        end

      {:ok, query |> preload([:service, :user]) |> Repo.all()}
    end)
  end

  @doc "Number of requests waiting for an administrator (0 for others)."
  def pending_count(scope) do
    if Accounts.can?(scope, :manage_bookings),
      do: Repo.aggregate(from(b in Booking, where: b.status == :pending), :count),
      else: 0
  end

  @doc "Gets a booking the scope may see (its owner or an administrator)."
  def get_booking(%Scope{user: %User{id: user_id}} = scope, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Booking{} = booking <- Repo.get(Booking, uuid) |> Repo.preload([:service, :user]),
         true <- booking.user_id == user_id or Accounts.can?(scope, :manage_bookings) do
      {:ok, booking}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_booking(_scope, _id), do: {:error, :not_found}

  @doc "Confirms a request (refused if it would clash with a confirmed booking)."
  def accept_booking(scope, booking, message \\ nil)

  def accept_booking(scope, %Booking{status: status} = booking, message)
      when status in [:pending, :proposed] do
    as_admin(scope, fn admin ->
      mutate_booking(booking, fn current ->
        cond do
          current.status not in [:pending, :proposed] ->
            {:error, :invalid_state}

          conflicts(current) != [] ->
            {:error, :conflict}

          not slot_still_valid?(current, current.starts_at, current.ends_at) ->
            {:error, :unavailable}

          true ->
            current
            |> Ecto.Changeset.change(
              decided(admin,
                status: :confirmed,
                admin_message: blank_to_nil(message),
                proposed_starts_at: nil,
                proposed_ends_at: nil
              )
            )
            |> Repo.update()
            |> record_action(scope, "confirmed")
        end
      end)
    end)
    |> notify_member(:confirmed)
    |> notify_bookings()
    |> notify_availability()
  end

  def accept_booking(_scope, %Booking{}, _message), do: {:error, :invalid_state}

  @doc "Offers the member another start time (must be free)."
  def propose_time(scope, booking, starts_at, message \\ nil)

  def propose_time(
        scope,
        %Booking{status: status} = booking,
        %NaiveDateTime{} = starts_at,
        message
      )
      when status in [:pending, :proposed] do
    as_admin(scope, fn admin ->
      mutate_booking(booking, fn current ->
        current = Repo.preload(current, :service)
        ends_at = NaiveDateTime.add(starts_at, current.service.duration_minutes * 60)

        cond do
          current.status not in [:pending, :proposed] ->
            {:error, :invalid_state}

          conflicts(current, starts_at, ends_at) != [] ->
            {:error, :conflict}

          not slot_available?(current, starts_at, ends_at) ->
            {:error, :unavailable}

          true ->
            current
            |> Ecto.Changeset.change(
              decided(admin,
                status: :proposed,
                proposed_starts_at: starts_at,
                proposed_ends_at: ends_at,
                admin_message: blank_to_nil(message)
              )
            )
            |> Repo.update()
            |> record_action(
              scope,
              "proposed",
              time_change(current.starts_at, current.ends_at, starts_at, ends_at)
            )
        end
      end)
    end)
    |> notify_member(:proposed)
    |> notify_bookings()
  end

  def propose_time(_scope, %Booking{}, %NaiveDateTime{}, _message), do: {:error, :invalid_state}

  @doc "Declines a request with an optional message."
  def decline_booking(scope, booking, message \\ nil)

  def decline_booking(scope, %Booking{status: status} = booking, message)
      when status in [:pending, :proposed, :confirmed] do
    as_admin(scope, fn admin ->
      mutate_booking(booking, fn current ->
        if current.status in [:pending, :proposed, :confirmed] do
          current
          |> Ecto.Changeset.change(
            decided(admin, status: :declined, admin_message: blank_to_nil(message))
          )
          |> Repo.update()
          |> record_action(scope, "declined")
        else
          {:error, :invalid_state}
        end
      end)
    end)
    |> notify_member(:declined)
    |> notify_bookings()
    |> notify_availability()
  end

  def decline_booking(_scope, %Booking{}, _message), do: {:error, :invalid_state}

  @doc "Confirmed bookings visible to the scope in a date range, for the calendar."
  def confirmed_between(scope, %Date{} = from, %Date{} = to) do
    from_dt = NaiveDateTime.new!(from, ~T[00:00:00])
    to_dt = NaiveDateTime.new!(Date.add(to, 1), ~T[00:00:00])

    query =
      from b in Booking,
        where: b.status == :confirmed and b.starts_at < ^to_dt and b.ends_at > ^from_dt,
        order_by: [asc: b.starts_at],
        preload: [:service, :user]

    query =
      case scope do
        %Scope{user: %User{id: id, role: :admin}} ->
          if match?(%User{role: :admin}, Repo.get(User, id)),
            do: query,
            else: where(query, [b], not b.private_calendar or b.user_id == ^id)

        %Scope{user: %User{id: id}} ->
          where(query, [b], not b.private_calendar or b.user_id == ^id)

        _ ->
          where(query, [b], not b.private_calendar)
      end

    Repo.all(query)
  end

  ## Helpers

  defp mutate_booking(booking, fun) do
    Repo.transact(fn ->
      Lock.acquire()

      case Repo.get(Booking, booking.id) do
        nil -> {:error, :not_found}
        current -> fun.(current)
      end
    end)
  end

  defp record_action(result, scope, action, details \\ %{})

  defp record_action({:ok, booking} = result, scope, action, details) do
    details =
      Map.merge(
        %{
          starts_at: booking.starts_at,
          ends_at: booking.ends_at,
          proposed_starts_at: booking.proposed_starts_at,
          proposed_ends_at: booking.proposed_ends_at
        },
        details
      )

    Audit.record!(booking, scope, action, details)
    result
  end

  defp record_action(error, _scope, _action, _details), do: error

  defp slot_available?(booking, starts_at, ends_at) do
    service = get_service(booking.service_id)

    service && service.active &&
      Enum.any?(available_slots(service, NaiveDateTime.to_date(starts_at)), fn slot ->
        slot.starts_at == starts_at and slot.ends_at == ends_at
      end)
  end

  defp slot_still_valid?(booking, starts_at, ends_at) do
    service = get_service(booking.service_id)
    utc_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    service && service.active &&
      ends_at == NaiveDateTime.add(starts_at, service.duration_minutes * 60) &&
      starts_at in day_starts(service, NaiveDateTime.to_date(starts_at)) &&
      MapSet.member?(
        Timezone.eligible([starts_at], utc_now, service.duration_minutes * 60),
        starts_at
      )
  end

  defp time_change(old_start, old_end, new_start, new_end) do
    %{
      "old_starts_at" => NaiveDateTime.to_iso8601(old_start),
      "old_ends_at" => NaiveDateTime.to_iso8601(old_end),
      "new_starts_at" => NaiveDateTime.to_iso8601(new_start),
      "new_ends_at" => NaiveDateTime.to_iso8601(new_end)
    }
  end

  defp decided(admin, changes),
    do: Keyword.merge(changes, decided_by_id: admin.id, decided_at: DateTime.utc_now(:second))

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(text), do: if(String.trim(text) == "", do: nil, else: String.trim(text))

  defp notify_member({:ok, booking}, event) do
    booking = Repo.preload(booking, [:service, :user], force: true)
    Notifier.to_member(booking, event)
    {:ok, booking}
  end

  defp notify_member(error, _event), do: error

  defp notify_admins({:ok, booking}, event) do
    booking = Repo.preload(booking, [:service, :user], force: true)
    Notifier.to_admins(admin_emails(), booking, event)
    {:ok, booking}
  end

  defp notify_admins(error, _event), do: error

  defp admin_emails, do: Repo.all(from u in User, where: u.role == :admin, select: u.email)

  # re-reads the role so a demoted admin's old session can't act
  defp as_admin(%Scope{user: %User{id: id}}, fun) do
    case Repo.get(User, id) do
      %User{role: :admin} = admin -> fun.(admin)
      _ -> {:error, :forbidden}
    end
  end

  defp as_admin(_scope, _fun), do: {:error, :forbidden}
end
