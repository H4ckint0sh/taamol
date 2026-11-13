defmodule TaamolWeb.EventEditorComponent do
  @moduledoc false
  use TaamolWeb, :live_component

  import TaamolWeb.CalendarComponents, only: [kind_name: 1]

  alias Taamol.Events
  alias Taamol.Events.Event

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn -> to_form(Events.change_event(assigns.event)) end)
     |> assign_new(:error, fn -> nil end)}
  end

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    changeset = Events.change_event(socket.assigns.event, params)
    {:noreply, assign(socket, form: to_form(%{changeset | action: :validate}), error: nil)}
  end

  def handle_event("save", %{"event" => params}, socket) do
    %{current_scope: scope, event: event} = socket.assigns

    result =
      if event.id,
        do: Events.update_event(scope, event, params),
        else: Events.create_event(scope, params)

    case result do
      {:ok, event} ->
        send(self(), {:event_editor, :saved, event})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        if Keyword.has_key?(changeset.errors, :id) do
          show_error(socket, gettext("This event no longer exists."))
        else
          {:noreply, assign(socket, form: to_form(changeset), error: nil)}
        end

      {:error, :forbidden} ->
        show_error(socket, gettext("You are not allowed to do that."))
    end
  end

  def handle_event("delete", _params, socket) do
    case Events.delete_event(socket.assigns.current_scope, socket.assigns.event) do
      {:ok, event} ->
        send(self(), {:event_editor, :deleted, event})
        {:noreply, socket}

      {:error, _} ->
        show_error(socket, gettext("The event could not be deleted."))
    end
  end

  defp show_error(socket, message) do
    send(self(), {:event_editor, :error, message})
    {:noreply, assign(socket, :error, message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"#{@id}-editor"}>
      <div
        :if={@dialog}
        id="event-dialog-backdrop"
        class="fixed inset-0 z-[60] flex items-end justify-center bg-black/55 p-3 backdrop-blur-sm sm:items-center sm:p-6"
      >
        <.focus_wrap
          id="event-dialog"
          role="dialog"
          aria-modal="true"
          aria-labelledby="event-dialog-title"
          phx-mounted={JS.focus(to: "#event-dialog-close")}
          phx-window-keydown={JS.push("close-event") |> JS.focus(to: @focus_return)}
          phx-key="Escape"
          phx-click-away="close-event"
          class="max-h-[calc(100dvh-1.5rem)] w-full max-w-lg overflow-y-auto rounded-3xl border border-base-300 bg-base-100 shadow-2xl sm:max-h-[calc(100dvh-3rem)]"
        >
          <div class="flex items-start justify-between gap-4 border-b border-base-300 bg-base-200/40 p-5 sm:p-6">
            <div class="flex min-w-0 items-center gap-3">
              <span class="grid size-11 shrink-0 place-items-center rounded-2xl bg-primary/10 text-primary">
                <.icon name="hero-calendar-days" class="size-6" />
              </span>
              <h2 id="event-dialog-title" class="text-xl font-bold">
                {if(@event.id, do: gettext("Edit event"), else: gettext("Add event"))}
              </h2>
            </div>
            <button
              type="button"
              id="event-dialog-close"
              phx-click={JS.push("close-event") |> JS.focus(to: @focus_return)}
              aria-label={gettext("Close")}
              class="grid size-10 shrink-0 place-items-center rounded-full text-base-content/60 transition hover:bg-base-200 hover:text-base-content focus-visible:outline-2 focus-visible:outline-primary"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <div class="p-5 sm:p-6">
            <.event_form form={@form} event={@event} error={@error} target={@myself} />
          </div>
        </.focus_wrap>
      </div>
      <.event_form :if={!@dialog} form={@form} event={@event} error={@error} target={@myself} />
    </div>
    """
  end

  attr :form, :any, required: true
  attr :event, Event, required: true
  attr :error, :string, default: nil
  attr :target, :any, required: true

  defp event_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="event-form"
      phx-change="validate"
      phx-submit="save"
      phx-target={@target}
      class="space-y-1"
    >
      <p
        :if={@error}
        id="event-form-error"
        role="alert"
        class="mb-4 rounded-xl bg-error/10 p-3 text-sm text-error"
      >
        {@error}
      </p>
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
          :if={@event.id}
          type="button"
          id="delete-event"
          phx-click="delete"
          phx-target={@target}
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
    """
  end
end
