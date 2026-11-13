defmodule TaamolWeb.DashboardLive.EventForm do
  @moduledoc """
  Admin form to add, edit and delete calendar events
  (`/dashboard/events/new?date=2026-11-20`, `/dashboard/events/:id/edit`).
  """
  use TaamolWeb, :live_view

  alias Taamol.Events
  alias Taamol.Events.Event

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    date =
      case Date.from_iso8601(params["date"] || "") do
        {:ok, date} -> date
        _ -> Date.utc_today()
      end

    event = %Event{starts_at: NaiveDateTime.new!(date, ~T[18:00:00])}

    socket
    |> assign(page_title: gettext("Add event"), event: event)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    event = Events.get_event!(id)

    socket
    |> assign(page_title: gettext("Edit event"), event: event)
  end

  @impl true
  def handle_info({:event_editor, action, event}, socket) when action in [:saved, :deleted] do
    message = if action == :saved, do: gettext("Event saved."), else: gettext("Event deleted.")
    {:noreply, socket |> put_flash(:info, message) |> push_navigate(to: calendar_path(event))}
  end

  def handle_info({:event_editor, :error, message}, socket),
    do: {:noreply, put_flash(socket, :error, message)}

  defp calendar_path(%Event{starts_at: starts_at}) do
    date = NaiveDateTime.to_date(starts_at)
    ~p"/calendar?#{[month: Calendar.strftime(date, "%Y-%m"), date: Date.to_iso8601(date)]}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      unread_messages={@unread_messages}
      active={:events}
      title={@page_title}
    >
      <div class="max-w-2xl">
        <.link
          navigate={~p"/dashboard/events"}
          class="mb-4 inline-flex items-center gap-1.5 text-sm text-base-content/60 transition-colors hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4 rtl:rotate-180" />
          {gettext("Calendar events")}
        </.link>

        <Layouts.dashboard_heading title={@page_title} />

        <div class="rounded-2xl border border-base-300 bg-base-100 p-5">
          <.live_component
            module={TaamolWeb.EventEditorComponent}
            id="event-page"
            event={@event}
            current_scope={@current_scope}
            dialog={false}
            focus_return={nil}
          />
        </div>
      </div>
    </Layouts.dashboard>
    """
  end
end
