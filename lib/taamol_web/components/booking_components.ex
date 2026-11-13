defmodule TaamolWeb.BookingComponents do
  @moduledoc "Shared pieces for bookings: names in the current language, statuses, times."
  use TaamolWeb, :html

  alias Taamol.Bookings.Service

  @doc "The service's name in the current language."
  def service_name(%Service{name_fa: fa, name_sv: sv}) do
    if Gettext.get_locale(TaamolWeb.Gettext) == "fa", do: fa, else: sv
  end

  @doc "The service's description in the current language (may be nil)."
  def service_description(%Service{description_fa: fa, description_sv: sv}) do
    if Gettext.get_locale(TaamolWeb.Gettext) == "fa", do: fa || sv, else: sv || fa
  end

  def resource_name(:premises), do: gettext("Premises")
  def resource_name(:imam), do: gettext("Imam")
  def resource_name(:other), do: gettext("Other")

  def status_name(:pending), do: gettext("Waiting for answer")
  def status_name(:confirmed), do: gettext("Confirmed")
  def status_name(:proposed), do: gettext("New time offered")
  def status_name(:declined), do: gettext("Declined")
  def status_name(:cancelled), do: gettext("Cancelled")

  @doc "\"18:00–20:00\"."
  def time_range(starts_at, ends_at),
    do: "#{Calendar.strftime(starts_at, "%H:%M")}–#{Calendar.strftime(ends_at, "%H:%M")}"

  @doc "\"20 November 2026, 18:00–20:00\"."
  def when_text(starts_at, ends_at) do
    date = NaiveDateTime.to_date(starts_at)

    "#{date.day} #{TaamolWeb.NewsComponents.month_name(date.month)} #{date.year}, #{time_range(starts_at, ends_at)}"
  end

  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium",
      @status == :pending && "bg-warning/15 text-warning",
      @status == :confirmed && "bg-success/15 text-success",
      @status == :proposed && "bg-info/15 text-info",
      @status in [:declined, :cancelled] && "bg-base-200 text-base-content/60"
    ]}>
      <.icon
        name={
          case @status do
            :pending -> "hero-clock-micro"
            :confirmed -> "hero-check-circle-micro"
            :proposed -> "hero-arrow-path-micro"
            _ -> "hero-x-circle-micro"
          end
        }
        class="size-3.5"
      />
      {status_name(@status)}
    </span>
    """
  end
end
