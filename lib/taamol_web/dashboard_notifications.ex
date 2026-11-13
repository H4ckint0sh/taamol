defmodule TaamolWeb.DashboardNotifications do
  @moduledoc "Keeps dashboard notification counts current across LiveView sessions."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Taamol.{Accounts, Bookings, Contact}

  def on_mount(:default, _params, _session, socket) do
    scope = socket.assigns.current_scope

    socket =
      if connected?(socket) and Accounts.can?(scope, :manage_messages) do
        case Contact.subscribe_messages(scope) do
          :ok ->
            attach_hook(socket, :contact_notifications, :handle_info, &handle_message_change/2)

          {:error, :forbidden} ->
            socket
        end
      else
        socket
      end

    socket =
      if connected?(socket) do
        :ok = Bookings.subscribe_changes(scope)
        attach_hook(socket, :booking_notifications, :handle_info, &handle_booking_change/2)
      else
        socket
      end

    {:cont,
     socket
     |> assign(:unread_messages, Contact.unread_count(scope))
     |> assign(:pending_bookings, Bookings.pending_count(scope))}
  end

  defp handle_booking_change(:bookings_changed, socket) do
    socket =
      assign(socket, :pending_bookings, Bookings.pending_count(socket.assigns.current_scope))

    if socket.view == TaamolWeb.DashboardLive.Bookings,
      do: {:cont, socket},
      else: {:halt, socket}
  end

  defp handle_booking_change(_, socket), do: {:cont, socket}

  defp handle_message_change(:contact_messages_changed, socket) do
    socket = assign(socket, :unread_messages, Contact.unread_count(socket.assigns.current_scope))

    if socket.view == TaamolWeb.DashboardLive.Messages,
      do: {:cont, socket},
      else: {:halt, socket}
  end

  defp handle_message_change(_, socket), do: {:cont, socket}
end
