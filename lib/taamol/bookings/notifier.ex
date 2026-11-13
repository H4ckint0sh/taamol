defmodule Taamol.Bookings.Notifier do
  @moduledoc "Booking emails to members and administrators."

  import Swoosh.Email

  alias Taamol.Mailer

  def new_request([], _booking), do: :ok

  def new_request(admin_emails, booking) do
    deliver(admin_emails, "New booking request: #{booking.service.name_sv}", """
    #{booking.contact_name} (#{booking.user.email}, #{booking.contact_phone}) asks to book
    #{booking.service.name_sv} on #{when_text(booking.starts_at, booking.ends_at)}.
    Guests: #{booking.guests || "-"}
    #{location_text(booking)}

    #{booking.notes}

    Accept it, offer another time or decline it in the dashboard under Bookings.
    """)
  end

  def to_admins([], _booking, _event), do: :ok

  def to_admins(admin_emails, booking, event) do
    {subject, text} =
      case event do
        :accepted_proposal -> {"Booking time accepted", "accepted the time you offered"}
        :declined_proposal -> {"Booking time declined", "declined the time you offered"}
        :cancelled -> {"Booking cancelled", "cancelled their booking"}
      end

    deliver(admin_emails, "#{subject}: #{booking.service.name_sv}", """
    #{booking.contact_name} (#{booking.user.email}) #{text}:
    #{booking.service.name_sv}, #{when_text(booking.starts_at, booking.ends_at)}.
    """)
  end

  def to_member(booking, event) do
    {subject, body} =
      case event do
        :confirmed ->
          {"Your booking is confirmed",
           "Your booking of #{booking.service.name_sv} on #{when_text(booking.starts_at, booking.ends_at)} is confirmed."}

        :proposed ->
          {"Another time is offered for your booking",
           "We can't do the time you asked for, but we can offer #{when_text(booking.proposed_starts_at, booking.proposed_ends_at)}. Accept or decline it in your dashboard under Bookings."}

        :declined ->
          {"Your booking request was declined",
           "We are sorry, we can't accept your booking of #{booking.service.name_sv} on #{when_text(booking.starts_at, booking.ends_at)}."}
      end

    message =
      if booking.admin_message, do: "\n\nMessage from us:\n#{booking.admin_message}", else: ""

    deliver([booking.user.email], subject, "Hi #{booking.contact_name},\n\n#{body}#{message}\n")
  end

  defp when_text(starts_at, ends_at) do
    "#{Calendar.strftime(starts_at, "%Y-%m-%d %H:%M")}–#{Calendar.strftime(ends_at, "%H:%M")}"
  end

  defp location_text(%{location_type: :association}), do: "Location: association premises"
  defp location_text(%{location_type: :other, address: address}), do: "Location: #{address}"
  defp location_text(_booking), do: ""

  defp deliver(to, subject, body) do
    new()
    |> to(to)
    |> from({"Taamol", "contact@example.com"})
    |> subject(subject)
    |> text_body(body)
    |> Mailer.deliver()

    :ok
  end
end
