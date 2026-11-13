defmodule TaamolWeb.DashboardLive.BookingServices do
  @moduledoc """
  `/dashboard/booking-services`: what members can book (administrators).
  Services that share a resource (the premises, the imam) can't be booked at
  the same time.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.BookingComponents

  alias Taamol.Bookings
  alias Taamol.Bookings.Service

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Booking services"))
     |> assign_services()
     |> edit(%Service{})}
  end

  defp assign_services(socket),
    do: assign(socket, services: Bookings.list_services(active_only: false))

  defp edit(socket, service),
    do: assign(socket, editing: service, form: to_form(Bookings.change_service(service)))

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, edit(socket, Bookings.get_service(id) || %Service{})}
  end

  def handle_event("new", _params, socket), do: {:noreply, edit(socket, %Service{})}

  def handle_event("validate", %{"service" => params}, socket) do
    changeset = Bookings.change_service(socket.assigns.editing, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"service" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.editing do
        %Service{id: nil} -> Bookings.create_service(scope, params)
        service -> Bookings.update_service(scope, service, params)
      end

    case result do
      {:ok, _service} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Service saved."))
         |> assign_services()
         |> edit(%Service{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, :forbidden} ->
        {:noreply, push_navigate(socket, to: ~p"/dashboard")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      unread_messages={@unread_messages}
      active={:booking_services}
      title={gettext("Booking services")}
    >
      <Layouts.dashboard_heading
        title={gettext("Booking services")}
        subtitle={gettext("What members can book from the calendar.")}
      />

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_24rem]">
        <ul id="services" class="space-y-3">
          <li
            :for={service <- @services}
            id={"service-#{service.id}"}
            class="flex items-start gap-3 rounded-2xl border border-base-300 bg-base-100 p-4"
          >
            <span class={[
              "grid size-10 shrink-0 place-items-center rounded-xl",
              if(service.active,
                do: "bg-primary/10 text-primary",
                else: "bg-base-200 text-base-content/40"
              )
            ]}>
              <.icon name={service.icon} class="size-5" />
            </span>
            <div class="min-w-0 flex-1">
              <p class="font-semibold">
                {service.name_sv}
                <span :if={!service.active} class="ms-1 text-xs font-normal text-base-content/50">
                  ({gettext("hidden")})
                </span>
              </p>
              <p dir="rtl" class="text-sm text-base-content/70">{service.name_fa}</p>
              <p class="mt-1 text-xs text-base-content/55">
                {resource_name(service.resource)} · {ngettext(
                  "%{count} minute",
                  "%{count} minutes",
                  service.duration_minutes
                )}
              </p>
            </div>
            <button
              type="button"
              id={"edit-service-#{service.id}"}
              phx-click="edit"
              phx-value-id={service.id}
              class="text-sm font-medium text-primary hover:underline"
            >
              {gettext("Edit")}
            </button>
          </li>
          <li
            :if={@services == []}
            class="rounded-2xl border border-dashed border-base-300 p-8 text-center text-sm text-base-content/55"
          >
            {gettext("No services yet.")}
          </li>
        </ul>

        <section class="rounded-2xl border border-base-300 bg-base-100 p-5 lg:sticky lg:top-24 lg:self-start">
          <div class="mb-3 flex items-center justify-between">
            <h2 class="font-semibold">
              {if(@editing.id, do: gettext("Edit service"), else: gettext("New service"))}
            </h2>
            <button
              :if={@editing.id}
              type="button"
              phx-click="new"
              class="text-sm text-base-content/60 hover:underline"
            >
              {gettext("New service")}
            </button>
          </div>
          <.form for={@form} id="service-form" phx-change="validate" phx-submit="save">
            <.input field={@form[:name_sv]} type="text" label={gettext("Name (Swedish)")} required />
            <.input
              field={@form[:name_fa]}
              type="text"
              label={gettext("Name (Persian)")}
              dir="rtl"
              required
            />
            <.input
              field={@form[:description_sv]}
              type="textarea"
              rows="2"
              label={gettext("Description (Swedish)")}
            />
            <.input
              field={@form[:description_fa]}
              type="textarea"
              rows="2"
              dir="rtl"
              label={gettext("Description (Persian)")}
            />
            <div class="grid grid-cols-2 gap-x-3">
              <.input
                field={@form[:resource]}
                type="select"
                label={gettext("Uses")}
                options={Enum.map(Service.resources(), &{resource_name(&1), &1})}
              />
              <.input
                field={@form[:duration_minutes]}
                type="number"
                label={gettext("Minutes")}
                min="30"
                max="720"
                step="30"
              />
              <.input
                field={@form[:icon]}
                type="select"
                label={gettext("Icon")}
                options={Enum.map(Service.icons(), &{String.replace_prefix(&1, "hero-", ""), &1})}
              />
              <.input field={@form[:position]} type="number" label={gettext("Order")} />
            </div>
            <div class="grid grid-cols-2 gap-x-3">
              <.input field={@form[:opens_at]} type="time" label={gettext("Available from")} required />
              <.input
                field={@form[:closes_at]}
                type="time"
                label={gettext("Available until")}
                required
              />
            </div>
            <.input field={@form[:active]} type="checkbox" label={gettext("Can be booked")} />
            <p class="mb-3 text-xs text-base-content/55">
              {gettext(
                "Services that use the same premises or the imam can't be booked at the same time."
              )}
            </p>
            <button
              type="submit"
              id="save-service"
              phx-disable-with={gettext("Saving…")}
              class="w-full rounded-xl bg-primary py-2.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
            >
              {gettext("Save service")}
            </button>
          </.form>
        </section>
      </div>
    </Layouts.dashboard>
    """
  end
end
