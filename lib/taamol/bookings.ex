defmodule Taamol.Bookings do
  @moduledoc """
  Booking the association's premises, the imam and other services, from the
  calendar.

  Availability is "smart": a time is free when it is within opening hours, far
  enough ahead, and doesn't overlap a **confirmed** booking of the same
  resource (the premises, the imam; "other" services only clash with
  themselves). Pending requests don't block a time; an administrator decides:
  accept, offer another time, or decline.
  """

  import Ecto.Query

  alias Taamol.Accounts
  alias Taamol.Accounts.{Scope, User}
  alias Taamol.Bookings.{Booking, Notifier, Service}
  alias Taamol.Repo

  @opens ~T[09:00:00]
  @closes ~T[22:00:00]
  @step_minutes 30
  @min_notice_hours 24
  @max_days_ahead 365

  @doc "Subscribes to changes that affect calendar availability."
  def subscribe_availability, do: Phoenix.PubSub.subscribe(Taamol.PubSub, "bookings:availability")

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
    as_admin(scope, fn _ -> %Service{} |> Service.changeset(attrs) |> Repo.insert() end)
    |> notify_availability()
  end

  def update_service(scope, %Service{} = service, attrs) do
    as_admin(scope, fn _ -> service |> Service.changeset(attrs) |> Repo.update() end)
    |> notify_availability()
  end

  ## Availability

  @doc "Default service hours and the minimum booking notice."
  def rules, do: %{opens: @opens, closes: @closes, min_notice_hours: @min_notice_hours}

  @doc "Free start times for a service on a date: `[%{starts_at:, ends_at:}]`."
  def available_slots(%Service{} = service, %Date{} = date) do
    blocking = blocking_bookings(service, date, date)
    slots_for_day(service, date, blocking, now())
  end

  @doc """
  Per-day availability for a range (for the calendar grid):
  `%{date => %{free: n, total: n}}`. Closed or past days have `total: 0`.
  """
  def availability(%Service{} = service, %Date{} = from, %Date{} = to) do
    blocking = blocking_bookings(service, from, to)
    now = now()

    Map.new(Date.range(from, to), fn date ->
      total = if bookable_day?(date, now), do: length(day_starts(service, date)), else: 0
      {date, %{free: length(slots_for_day(service, date, blocking, now)), total: total}}
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

  defp slots_for_day(service, date, blocking, now) do
    earliest = NaiveDateTime.add(now, @min_notice_hours * 3600)

    latest =
      NaiveDateTime.new!(Date.add(NaiveDateTime.to_date(now), @max_days_ahead), ~T[23:59:59])

    for starts_at <- day_starts(service, date),
        ends_at = NaiveDateTime.add(starts_at, service.duration_minutes * 60),
        NaiveDateTime.compare(starts_at, earliest) != :lt,
        NaiveDateTime.compare(starts_at, latest) != :gt,
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

  defp bookable_day?(date, now) do
    Date.compare(date, NaiveDateTime.to_date(NaiveDateTime.add(now, @min_notice_hours * 3600))) !=
      :lt
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

  @doc "Confirmed bookings that overlap a time (for the admin's clash warning)."
  def conflicts(%Booking{} = booking, starts_at \\ nil, ends_at \\ nil) do
    booking = Repo.preload(booking, :service)
    starts_at = starts_at || booking.starts_at
    ends_at = ends_at || booking.ends_at

    booking.service
    |> blocking_bookings(NaiveDateTime.to_date(starts_at), NaiveDateTime.to_date(ends_at))
    |> Enum.filter(&(&1.id != booking.id and overlaps?(&1, starts_at, ends_at)))
  end

  # community time; the server runs in UTC, the 24-hour notice absorbs the offset
  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  ## Members

  @doc "A changeset for the request form."
  def change_request(attrs \\ %{}), do: Booking.request_changeset(%Booking{}, attrs)

  @doc """
  Requests a booking. The start time must be one of `available_slots/2`.
  Administrators are emailed.
  """
  def request_booking(
        %Scope{user: %User{id: user_id}},
        %Service{} = service,
        %NaiveDateTime{} = starts_at,
        attrs
      ) do
    slot =
      Enum.find(
        available_slots(service, NaiveDateTime.to_date(starts_at)),
        &(&1.starts_at == starts_at)
      )

    if slot do
      result =
        %Booking{
          user_id: user_id,
          service_id: service.id,
          starts_at: slot.starts_at,
          ends_at: slot.ends_at
        }
        |> Booking.request_changeset(attrs)
        |> Repo.insert()

      with {:ok, booking} <- result do
        booking = Repo.preload(booking, [:service, :user])
        Notifier.new_request(admin_emails(), booking)
        {:ok, booking}
      end
    else
      {:error, :unavailable}
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
        %Scope{user: %User{id: user_id}},
        %Booking{status: :proposed, user_id: user_id} = booking,
        :accept
      ) do
    if conflicts(booking, booking.proposed_starts_at, booking.proposed_ends_at) == [] do
      booking
      |> Ecto.Changeset.change(
        status: :confirmed,
        starts_at: booking.proposed_starts_at,
        ends_at: booking.proposed_ends_at,
        proposed_starts_at: nil,
        proposed_ends_at: nil
      )
      |> Repo.update()
      |> notify_admins(:accepted_proposal)
      |> notify_availability()
    else
      {:error, :conflict}
    end
  end

  def respond_to_proposal(
        %Scope{user: %User{id: user_id}},
        %Booking{status: :proposed, user_id: user_id} = booking,
        :decline
      ) do
    booking
    |> Ecto.Changeset.change(status: :cancelled)
    |> Repo.update()
    |> notify_admins(:declined_proposal)
  end

  def respond_to_proposal(_scope, _booking, _answer), do: {:error, :forbidden}

  @doc "Cancels the member's own open booking."
  def cancel_booking(
        %Scope{user: %User{id: user_id}},
        %Booking{user_id: user_id, status: status} = booking
      )
      when status in [:pending, :proposed, :confirmed] do
    booking
    |> Ecto.Changeset.change(status: :cancelled)
    |> Repo.update()
    |> notify_admins(:cancelled)
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
  def accept_booking(scope, %Booking{status: status} = booking, message \\ nil)
      when status in [:pending, :proposed] do
    as_admin(scope, fn admin ->
      if conflicts(booking) == [] do
        booking
        |> Ecto.Changeset.change(
          decided(admin,
            status: :confirmed,
            admin_message: blank_to_nil(message),
            proposed_starts_at: nil,
            proposed_ends_at: nil
          )
        )
        |> Repo.update()
        |> notify_member(:confirmed)
      else
        {:error, :conflict}
      end
    end)
    |> notify_availability()
  end

  @doc "Offers the member another start time (must be free)."
  def propose_time(
        scope,
        %Booking{status: status} = booking,
        %NaiveDateTime{} = starts_at,
        message \\ nil
      )
      when status in [:pending, :proposed] do
    as_admin(scope, fn admin ->
      booking = Repo.preload(booking, :service, force: true)
      ends_at = NaiveDateTime.add(starts_at, booking.service.duration_minutes * 60)

      cond do
        conflicts(booking, starts_at, ends_at) != [] ->
          {:error, :conflict}

        not Enum.any?(
          available_slots(booking.service, NaiveDateTime.to_date(starts_at)),
          &(&1.starts_at == starts_at)
        ) ->
          {:error, :unavailable}

        true ->
          booking
          |> Ecto.Changeset.change(
            decided(admin,
              status: :proposed,
              proposed_starts_at: starts_at,
              proposed_ends_at: ends_at,
              admin_message: blank_to_nil(message)
            )
          )
          |> Repo.update()
          |> notify_member(:proposed)
      end
    end)
  end

  @doc "Declines a request with an optional message."
  def decline_booking(scope, %Booking{status: status} = booking, message \\ nil)
      when status in [:pending, :proposed, :confirmed] do
    as_admin(scope, fn admin ->
      booking
      |> Ecto.Changeset.change(
        decided(admin, status: :declined, admin_message: blank_to_nil(message))
      )
      |> Repo.update()
      |> notify_member(:declined)
    end)
    |> notify_availability()
  end

  @doc "Confirmed bookings in a date range, for the calendar."
  def confirmed_between(%Date{} = from, %Date{} = to) do
    from_dt = NaiveDateTime.new!(from, ~T[00:00:00])
    to_dt = NaiveDateTime.new!(Date.add(to, 1), ~T[00:00:00])

    Repo.all(
      from b in Booking,
        where: b.status == :confirmed and b.starts_at < ^to_dt and b.ends_at > ^from_dt,
        order_by: [asc: b.starts_at],
        preload: [:service, :user]
    )
  end

  ## Helpers

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
