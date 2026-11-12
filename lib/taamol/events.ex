defmodule Taamol.Events do
  @moduledoc """
  The calendar: Taamol community events stored in the database, merged with
  Shia holidays and historical days computed from the Hijri calendar.
  """

  import Ecto.Query

  alias Taamol.Accounts.{Helpers, Scope, User}
  alias Taamol.Events.{Event, Holidays, Hijri}
  alias Taamol.Repo

  @doc """
  A calendar entry: either a computed holiday or a stored event.

    * `:source` - `:holiday` or `:event`
    * `:key` - holiday key (holidays only)
    * `:event` - the `%Event{}` (events only)
    * `:kind` - `:community`, `:celebration`, `:mourning` or `:observance`
    * `:first_day` / `:last_day` - the dates it covers
    * `:starts_at` / `:ends_at` / `:all_day` - times (events only)
  """
  def entries_between(%Date{} = from, %Date{} = to) do
    holidays =
      for holiday <- Holidays.between(from, to) do
        %{
          id: "holiday-#{holiday.key}-#{Date.to_iso8601(holiday.date)}",
          source: :holiday,
          key: holiday.key,
          event: nil,
          kind: holiday.kind,
          first_day: holiday.date,
          last_day: holiday.date,
          starts_at: nil,
          ends_at: nil,
          all_day: true
        }
      end

    events =
      for event <- list_events_between(from, to) do
        %{
          id: "event-#{event.id}",
          source: :event,
          key: nil,
          event: event,
          kind: event.kind,
          first_day: NaiveDateTime.to_date(event.starts_at),
          last_day: NaiveDateTime.to_date(event.ends_at || event.starts_at),
          starts_at: event.starts_at,
          ends_at: event.ends_at,
          all_day: event.all_day
        }
      end

    Enum.sort_by(holidays ++ events, &sort_key/1)
  end

  @doc "Entries grouped by every day they cover: `%{Date => [entry]}`."
  def entries_by_day(%Date{} = from, %Date{} = to) do
    for entry <- entries_between(from, to),
        day <- Date.range(max_date(entry.first_day, from), min_date(entry.last_day, to)),
        reduce: %{} do
      acc -> Map.update(acc, day, [entry], &(&1 ++ [entry]))
    end
  end

  @doc "The next entries from `today` on (looks ahead `:days`, default 120)."
  def upcoming(opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())
    days = Keyword.get(opts, :days, 120)

    today
    |> entries_between(Date.add(today, days))
    |> Enum.filter(&(Date.compare(&1.last_day, today) != :lt))
    |> Enum.take(Keyword.get(opts, :limit, 5))
  end

  @doc "Stored events overlapping the given dates (inclusive)."
  def list_events_between(%Date{} = from, %Date{} = to) do
    from_dt = NaiveDateTime.new!(from, ~T[00:00:00])
    to_dt = NaiveDateTime.new!(Date.add(to, 1), ~T[00:00:00])

    Repo.all(
      from e in Event,
        where: e.starts_at < ^to_dt and coalesce(e.ends_at, e.starts_at) >= ^from_dt,
        order_by: [asc: e.starts_at, asc: e.id]
    )
  end

  @doc """
  Stored events for the dashboard table. `:when` is `:upcoming` (default,
  soonest first) or `:past` (latest first). Returns `%{entries:, total:}`.
  """
  def list_events_page(opts \\ []) do
    now = NaiveDateTime.utc_now()

    query =
      case Keyword.get(opts, :when, :upcoming) do
        :past ->
          from e in Event,
            where: coalesce(e.ends_at, e.starts_at) < ^now,
            order_by: [desc: e.starts_at]

        _ ->
          from e in Event,
            where: coalesce(e.ends_at, e.starts_at) >= ^now,
            order_by: [asc: e.starts_at]
      end

    entries =
      query
      |> limit(^Keyword.get(opts, :limit, 20))
      |> offset(^Keyword.get(opts, :offset, 0))
      |> Repo.all()

    %{entries: entries, total: Repo.aggregate(exclude(query, :order_by), :count)}
  end

  @doc "Gets an event. Raises if it doesn't exist."
  def get_event!(id), do: Repo.get!(Event, id)

  @doc "Returns a changeset for the event form."
  def change_event(%Event{} = event, attrs \\ %{}), do: Event.changeset(event, attrs)

  @doc "Creates an event. Administrators only."
  def create_event(scope, attrs) do
    as_admin(scope, fn admin ->
      %Event{creator_id: admin.id}
      |> Event.changeset(attrs)
      |> Repo.insert()
    end)
  end

  @doc "Updates an event. Administrators only."
  def update_event(scope, %Event{} = event, attrs) do
    as_admin(scope, fn _admin ->
      event
      |> Event.changeset(attrs)
      |> Repo.update()
    end)
  end

  @doc "Deletes an event. Administrators only."
  def delete_event(scope, %Event{} = event) do
    as_admin(scope, fn _admin -> Repo.delete(event) end)
  end

  @doc "The Hijri date for a Gregorian date."
  defdelegate hijri(date), to: Hijri, as: :from_date

  # re-checks the role in the database so a revoked admin can't keep editing
  defp as_admin(%Scope{user: %User{id: user_id}}, fun) do
    Repo.transact(fn ->
      case Helpers.find_admin_with_lock(user_id) do
        nil -> {:error, :forbidden}
        admin -> fun.(admin)
      end
    end)
  end

  defp as_admin(_scope, _fun), do: {:error, :forbidden}

  # all-day items first, then by start time; holidays before events on ties
  defp sort_key(entry) do
    time =
      if entry.all_day || is_nil(entry.starts_at),
        do: ~T[00:00:00],
        else: NaiveDateTime.to_time(entry.starts_at)

    {Date.to_gregorian_days(entry.first_day), if(entry.all_day, do: 0, else: 1),
     Time.to_erl(time), if(entry.source == :holiday, do: 0, else: 1)}
  end

  defp max_date(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)
  defp min_date(a, b), do: if(Date.compare(a, b) == :gt, do: b, else: a)
end
