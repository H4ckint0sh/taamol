defmodule TaamolWeb.EventLive.Form do
  @moduledoc """
  Admin form to add, edit and delete calendar events
  (`/admin/events/new?date=2026-11-20`, `/admin/events/:id/edit`).
  """
  use TaamolWeb, :live_view

  import TaamolWeb.CalendarComponents, only: [kind_name: 1]

  alias Taamol.Events
  alias Taamol.Events.Event

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
    |> assign_form(Events.change_event(event))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    event = Events.get_event!(id)

    socket
    |> assign(page_title: gettext("Edit event"), event: event)
    |> assign_form(Events.change_event(event))
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    changeset = Events.change_event(socket.assigns.event, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"event" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.live_action do
        :new -> Events.create_event(scope, params)
        :edit -> Events.update_event(scope, socket.assigns.event, params)
      end

    case result do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Event saved."))
         |> push_navigate(to: calendar_path(event))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You are not allowed to do that."))
         |> push_navigate(to: ~p"/calendar")}
    end
  end

  def handle_event("delete", _params, socket) do
    case Events.delete_event(socket.assigns.current_scope, socket.assigns.event) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Event deleted."))
         |> push_navigate(to: calendar_path(event))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("The event could not be deleted."))}
    end
  end

  defp calendar_path(%Event{starts_at: starts_at}) do
    date = NaiveDateTime.to_date(starts_at)
    ~p"/calendar?#{[month: Calendar.strftime(date, "%Y-%m"), date: Date.to_iso8601(date)]}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:calendar}>
      <.link
        navigate={~p"/calendar"}
        class="inline-flex items-center gap-1.5 text-sm text-base-content/60 transition-colors hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="size-4 rtl:rotate-180" />
        {gettext("Calendar")}
      </.link>

      <h1 class="text-2xl font-bold tracking-tight">{@page_title}</h1>

      <.form
        for={@form}
        id="event-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-1 rounded-2xl border border-base-300 bg-base-100 p-5"
      >
        <.input field={@form[:title]} type="text" label={gettext("Title")} required />
        <.input
          field={@form[:kind]}
          type="select"
          label={gettext("Type")}
          options={Enum.map(Event.kinds(), &{kind_name(&1), &1})}
        />
        <.input field={@form[:all_day]} type="checkbox" label={gettext("All day")} />
        <div class="grid gap-x-4 sm:grid-cols-2">
          <.input field={@form[:starts_at]} type="datetime-local" label={gettext("Starts")} required />
          <.input field={@form[:ends_at]} type="datetime-local" label={gettext("Ends (optional)")} />
        </div>
        <.input field={@form[:location]} type="text" label={gettext("Location")} />
        <.input field={@form[:description]} type="textarea" label={gettext("Description")} rows="5" />

        <div class="flex items-center justify-between gap-3 pt-3">
          <button
            :if={@live_action == :edit}
            type="button"
            id="delete-event"
            phx-click="delete"
            data-confirm={gettext("Delete this event?")}
            class="rounded-xl px-4 py-2.5 text-sm font-semibold text-error transition hover:bg-error/10"
          >
            {gettext("Delete")}
          </button>
          <button
            type="submit"
            id="save-event"
            phx-disable-with={gettext("Saving…")}
            class="ms-auto rounded-xl bg-primary px-6 py-2.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
          >
            {gettext("Save event")}
          </button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
