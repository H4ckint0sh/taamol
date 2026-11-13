defmodule TaamolWeb.DashboardLive.Bookings do
  @moduledoc """
  `/dashboard/bookings`. Members see their own bookings (answer an offered
  time, cancel). Administrators also see everyone's requests and can accept
  them, offer another time or decline them (`?view=requests|upcoming|all|mine`).
  """
  use TaamolWeb, :live_view

  import TaamolWeb.BookingComponents

  alias Taamol.{Accounts, Bookings}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Bookings"),
       admin?: Accounts.can?(socket.assigns.current_scope, :manage_bookings),
       open: nil,
       offer_date: nil,
       offer_slots: []
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    view =
      case {socket.assigns.admin?, params["view"]} do
        {true, "upcoming"} -> :upcoming
        {true, "all"} -> :all
        {true, "mine"} -> :mine
        {true, _} -> :requests
        {false, _} -> :mine
      end

    {:noreply, socket |> assign(view: view, open: nil) |> load()}
  end

  defp load(socket) do
    scope = socket.assigns.current_scope

    bookings =
      case socket.assigns.view do
        :mine -> Bookings.list_my_bookings(scope)
        :requests -> elem(Bookings.list_bookings(scope, :pending), 1)
        :upcoming -> elem(Bookings.list_bookings(scope, :upcoming), 1)
        :all -> elem(Bookings.list_bookings(scope, :all), 1)
      end

    socket
    |> assign(empty?: bookings == [])
    |> stream(:bookings, bookings, reset: true)
  end

  # --- members ---------------------------------------------------------------

  @impl true
  def handle_event("answer", %{"id" => id, "answer" => answer}, socket)
      when answer in ["accept", "decline"] do
    with {:ok, booking} <- Bookings.get_booking(socket.assigns.current_scope, id),
         {:ok, _} <-
           Bookings.respond_to_proposal(
             socket.assigns.current_scope,
             booking,
             String.to_existing_atom(answer)
           ) do
      message =
        if answer == "accept",
          do: gettext("Booking confirmed."),
          else: gettext("Booking cancelled.")

      {:noreply, socket |> put_flash(:info, message) |> load()}
    else
      {:error, :conflict} ->
        {:noreply,
         put_flash(socket, :error, gettext("That time was just taken. Please contact us."))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("The booking could not be updated."))}
    end
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    with {:ok, booking} <- Bookings.get_booking(socket.assigns.current_scope, id),
         {:ok, _} <- Bookings.cancel_booking(socket.assigns.current_scope, booking) do
      {:noreply, socket |> put_flash(:info, gettext("Booking cancelled.")) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("The booking could not be updated."))}
    end
  end

  # --- administrators --------------------------------------------------------

  def handle_event("open", %{"id" => id}, socket) do
    open = if socket.assigns.open == id, do: nil, else: id
    {:noreply, socket |> assign(open: open, offer_date: nil, offer_slots: []) |> load()}
  end

  def handle_event("offer-date", %{"offer" => %{"date" => date}} = params, socket) do
    with {:ok, booking} <-
           Bookings.get_booking(socket.assigns.current_scope, params["booking_id"]),
         {:ok, date} <- Date.from_iso8601(date) do
      {:noreply,
       socket
       |> assign(offer_date: date, offer_slots: Bookings.available_slots(booking.service, date))
       |> stream_insert(:bookings, booking)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("decide", %{"booking_id" => id, "decision" => decision} = params, socket) do
    scope = socket.assigns.current_scope
    message = params["message"]

    result =
      with {:ok, booking} <- Bookings.get_booking(scope, id) do
        case decision do
          "accept" ->
            Bookings.accept_booking(scope, booking, message)

          "decline" ->
            Bookings.decline_booking(scope, booking, message)

          "offer" ->
            case NaiveDateTime.from_iso8601((params["slot"] || "") <> ":00") do
              {:ok, starts_at} -> Bookings.propose_time(scope, booking, starts_at, message)
              _ -> {:error, :no_time}
            end
        end
      end

    case result do
      {:ok, booking} ->
        {:noreply,
         socket
         |> assign(open: nil)
         |> put_flash(:info, gettext("Done: %{status}.", status: status_name(booking.status)))
         |> load()}

      {:error, :conflict} ->
        {:noreply,
         put_flash(socket, :error, gettext("That time clashes with a confirmed booking."))}

      {:error, :no_time} ->
        {:noreply, put_flash(socket, :error, gettext("Choose a date and a time to offer."))}

      {:error, :unavailable} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("That time is no longer available. Please choose another time.")
         )}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("The booking could not be updated."))}
    end
  end

  defp tab_path(view), do: ~p"/dashboard/bookings?#{[view: view]}"

  defp open?(booking), do: booking.status in [:pending, :proposed, :confirmed]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      unread_messages={@unread_messages}
      active={:bookings}
      title={gettext("Bookings")}
    >
      <Layouts.dashboard_heading
        title={gettext("Bookings")}
        subtitle={
          if(@admin?,
            do: gettext("Answer booking requests for the premises, the imam and more."),
            else: gettext("Your booking requests and their status.")
          )
        }
      >
        <:actions>
          <.link
            navigate={~p"/calendar?#{[mode: "book"]}"}
            class="inline-flex items-center gap-1.5 rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-primary-content transition hover:opacity-85"
          >
            <.icon name="hero-plus" class="size-4" />{gettext("New booking")}
          </.link>
        </:actions>
      </Layouts.dashboard_heading>

      <.segmented_control
        :if={@admin?}
        id="booking-views"
        role="group"
        aria-label={gettext("Bookings")}
        class="mb-4"
      >
        <.link
          :for={
            {view, label, icon} <- [
              {:requests, gettext("Requests"), "hero-inbox-micro"},
              {:upcoming, gettext("Upcoming"), "hero-calendar-days-micro"},
              {:all, gettext("All"), "hero-queue-list-micro"},
              {:mine, gettext("My bookings"), "hero-bookmark-square-micro"}
            ]
          }
          id={"booking-view-#{view}"}
          patch={tab_path(view)}
          aria-current={if(@view == view, do: "page")}
          class={segmented_option_class()}
        >
          <.icon name={icon} class="size-4" />
          {label}
        </.link>
      </.segmented_control>

      <p
        :if={@empty?}
        id="bookings-empty"
        class="rounded-2xl border border-dashed border-base-300 p-10 text-center text-sm text-base-content/55"
      >
        {if(@view == :requests,
          do: gettext("No requests waiting."),
          else: gettext("No bookings yet.")
        )}
      </p>

      <ul id="bookings" phx-update="stream" class="space-y-3">
        <li
          :for={{dom_id, booking} <- @streams.bookings}
          id={dom_id}
          class="rounded-2xl border border-base-300 bg-base-100 p-4 sm:p-5"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="flex min-w-0 items-start gap-3">
              <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
                <.icon name={booking.service.icon} class="size-5" />
              </span>
              <div class="min-w-0">
                <p class="font-semibold">{service_name(booking.service)}</p>
                <p class="text-sm tabular-nums text-base-content/70">
                  {when_text(booking.starts_at, booking.ends_at)}
                </p>
                <p :if={@view != :mine} dir="auto" class="mt-0.5 text-sm text-base-content/60">
                  {booking.contact_name} · {booking.contact_phone} · {booking.user.email}
                </p>
              </div>
            </div>
            <.status_badge status={booking.status} />
          </div>

          <p :if={booking.guests} class="mt-2 text-sm text-base-content/60">
            {ngettext("%{count} guest", "%{count} guests", booking.guests)}
          </p>
          <p
            :if={booking.notes}
            dir="auto"
            class="mt-2 whitespace-pre-line rounded-xl bg-base-200/60 px-3 py-2 text-sm"
            phx-no-format
          >{booking.notes}</p>

          <%!-- another time offered --%>
          <div
            :if={booking.status == :proposed}
            id={"proposal-#{booking.id}"}
            class="mt-3 rounded-xl bg-info/10 p-3 text-sm"
          >
            <p class="font-semibold text-info">{gettext("New time offered")}</p>
            <p class="tabular-nums">
              {when_text(booking.proposed_starts_at, booking.proposed_ends_at)}
            </p>
            <p :if={booking.admin_message} dir="auto" class="mt-1 text-base-content/70">
              {booking.admin_message}
            </p>
            <div :if={@view == :mine} class="mt-3 flex flex-wrap gap-2">
              <button
                type="button"
                id={"accept-offer-#{booking.id}"}
                phx-click="answer"
                phx-value-id={booking.id}
                phx-value-answer="accept"
                class="rounded-full bg-primary px-4 py-1.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
              >
                {gettext("Accept the new time")}
              </button>
              <button
                type="button"
                id={"decline-offer-#{booking.id}"}
                phx-click="answer"
                phx-value-id={booking.id}
                phx-value-answer="decline"
                class="rounded-full border border-base-300 px-4 py-1.5 text-sm transition hover:bg-base-200"
              >
                {gettext("Decline")}
              </button>
            </div>
          </div>

          <p
            :if={booking.status in [:confirmed, :declined] && booking.admin_message}
            dir="auto"
            class="mt-2 text-sm text-base-content/70"
          >
            <span class="font-medium">{gettext("Message from us:")}</span> {booking.admin_message}
          </p>

          <%!-- member: cancel --%>
          <div :if={@view == :mine and open?(booking)} class="mt-3">
            <button
              type="button"
              id={"cancel-#{booking.id}"}
              phx-click="cancel"
              phx-value-id={booking.id}
              data-confirm={gettext("Cancel this booking?")}
              class="text-sm text-error hover:underline"
            >
              {gettext("Cancel booking")}
            </button>
          </div>

          <%!-- administrator: decide --%>
          <div
            :if={@admin? and @view != :mine and booking.status in [:pending, :proposed]}
            class="mt-3"
          >
            <% conflicts = Bookings.conflicts(booking) %>
            <p
              :if={conflicts != []}
              id={"conflict-#{booking.id}"}
              class="mb-2 flex items-center gap-1.5 rounded-xl bg-warning/10 px-3 py-2 text-sm text-warning"
            >
              <.icon name="hero-exclamation-triangle" class="size-4" />
              {gettext("Clashes with a confirmed booking at this time.")}
            </p>
            <button
              type="button"
              id={"respond-#{booking.id}"}
              phx-click="open"
              phx-value-id={booking.id}
              class="text-sm font-semibold text-primary hover:underline"
            >
              {if(@open == booking.id, do: gettext("Close"), else: gettext("Respond"))}
            </button>

            <div :if={@open == booking.id} id={"decide-#{booking.id}"} class="mt-3 space-y-3">
              <form id={"decide-form-#{booking.id}"} phx-submit="decide" class="space-y-3">
                <input type="hidden" name="booking_id" value={booking.id} />
                <.input
                  type="textarea"
                  id={"decision-message-#{booking.id}"}
                  name="message"
                  value=""
                  rows="2"
                  dir="auto"
                  placeholder={gettext("Message to the member (optional)")}
                  aria-label={gettext("Message to the member (optional)")}
                />
                <div class="flex flex-wrap gap-2">
                  <button
                    type="submit"
                    name="decision"
                    value="accept"
                    id={"accept-#{booking.id}"}
                    disabled={conflicts != []}
                    class="rounded-full bg-success px-4 py-1.5 text-sm font-semibold text-success-content transition hover:opacity-85 disabled:opacity-40"
                  >
                    {gettext("Accept")}
                  </button>
                  <button
                    type="submit"
                    name="decision"
                    value="decline"
                    id={"decline-#{booking.id}"}
                    class="rounded-full border border-base-300 px-4 py-1.5 text-sm transition hover:bg-base-200"
                  >
                    {gettext("Decline")}
                  </button>
                </div>

                <div class="rounded-xl border border-base-300 p-3">
                  <p class="text-sm font-semibold">{gettext("Offer another time")}</p>
                  <div class="mt-2 flex flex-wrap items-end gap-2">
                    <.input
                      type="date"
                      id={"offer-date-#{booking.id}"}
                      name="offer[date]"
                      value={@offer_date && Date.to_iso8601(@offer_date)}
                      phx-change="offer-date"
                      aria-label={gettext("Date")}
                      wrapper_class="mb-0"
                    />
                    <.input
                      :if={@offer_date}
                      type="select"
                      name="slot"
                      id={"offer-slot-#{booking.id}"}
                      value={nil}
                      aria-label={gettext("Time")}
                      options={
                        if @offer_slots == [] do
                          [{gettext("No free times"), ""}]
                        else
                          Enum.map(@offer_slots, fn slot ->
                            {time_range(slot.starts_at, slot.ends_at),
                             slot.starts_at |> NaiveDateTime.to_iso8601() |> String.slice(0, 16)}
                          end)
                        end
                      }
                      wrapper_class="mb-0"
                    />
                    <button
                      :if={@offer_date && @offer_slots != []}
                      type="submit"
                      name="decision"
                      value="offer"
                      id={"offer-#{booking.id}"}
                      class="rounded-full bg-info px-4 py-1.5 text-sm font-semibold text-info-content transition hover:opacity-85"
                    >
                      {gettext("Offer this time")}
                    </button>
                  </div>
                </div>
              </form>
            </div>
          </div>
        </li>
      </ul>
    </Layouts.dashboard>
    """
  end
end
