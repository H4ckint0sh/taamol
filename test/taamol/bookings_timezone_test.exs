defmodule Taamol.Bookings.TimezoneTest do
  use Taamol.DataCase, async: true

  alias Taamol.Bookings.Timezone

  test "uses Stockholm time and a full 24 hours across daylight saving changes" do
    before_spring_change = ~N[2026-03-28 10:00:00]
    earliest = NaiveDateTime.add(before_spring_change, 24 * 3600)
    starts = [~N[2026-03-29 11:30:00], ~N[2026-03-29 12:00:00]]

    assert Timezone.local(before_spring_change) == ~N[2026-03-28 11:00:00.000000]
    assert Timezone.eligible(starts, earliest) == MapSet.new([~N[2026-03-29 12:00:00]])

    before_fall_change = ~N[2026-10-24 10:00:00]
    earliest = NaiveDateTime.add(before_fall_change, 24 * 3600)
    starts = [~N[2026-10-25 10:30:00], ~N[2026-10-25 11:00:00]]
    assert Timezone.eligible(starts, earliest) == MapSet.new([~N[2026-10-25 11:00:00]])
  end

  test "does not offer nonexistent or ambiguous local times" do
    starts = [~N[2026-03-29 02:30:00], ~N[2026-10-25 02:30:00], ~N[2026-10-25 03:00:00]]

    assert Timezone.eligible(starts, ~N[2026-01-01 00:00:00]) ==
             MapSet.new([~N[2026-10-25 03:00:00]])
  end

  test "does not offer intervals with ambiguous ends or altered duration at clock changes" do
    starts = [
      ~N[2026-03-29 00:30:00],
      ~N[2026-03-29 01:30:00],
      ~N[2026-03-29 03:30:00],
      ~N[2026-10-25 01:30:00],
      ~N[2026-10-25 03:30:00]
    ]

    assert Timezone.eligible(starts, ~N[2026-01-01 00:00:00], 2 * 3600) ==
             MapSet.new([~N[2026-03-29 03:30:00], ~N[2026-10-25 03:30:00]])
  end
end
