defmodule Taamol.Bookings.Timezone do
  @moduledoc false

  alias Taamol.Repo

  @zone "Europe/Stockholm"

  def local(utc) do
    %{rows: [[local]]} =
      Repo.query!(
        "SELECT ($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE $2",
        [utc, @zone]
      )

    local
  end

  def eligible(starts, earliest_utc, duration_seconds \\ 0) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT local_time
        FROM unnest($1::timestamp[]) AS t(local_time)
        CROSS JOIN LATERAL (
          SELECT local_time + $4 * interval '1 second' AS local_end
        ) AS duration
        CROSS JOIN LATERAL (
          SELECT local_time AT TIME ZONE $2 AS instant,
                 local_end AT TIME ZONE $2 AS end_instant
        ) AS utc
        WHERE instant >= ($3::timestamp AT TIME ZONE 'UTC')
          AND instant AT TIME ZONE $2 = local_time
          AND (instant - interval '1 hour') AT TIME ZONE $2 <> local_time
          AND (instant + interval '1 hour') AT TIME ZONE $2 <> local_time
          AND end_instant AT TIME ZONE $2 = local_end
          AND (end_instant - interval '1 hour') AT TIME ZONE $2 <> local_end
          AND (end_instant + interval '1 hour') AT TIME ZONE $2 <> local_end
          AND end_instant - instant = $4 * interval '1 second'
        """,
        [starts, @zone, earliest_utc, duration_seconds]
      )

    MapSet.new(rows, fn [local] -> NaiveDateTime.truncate(local, :second) end)
  end
end
