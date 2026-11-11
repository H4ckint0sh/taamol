defmodule TaamolWeb.AdminAccessLive do
  use TaamolWeb, :live_view

  alias Taamol.Accounts
  alias TaamolWeb.UserAuth

  @impl true
  def mount(_params, _session, socket) do
    case Accounts.list_users(socket.assigns.current_scope) do
      {:ok, users} -> {:ok, stream(socket, :users, users)}
      {:error, :forbidden} -> {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="access-management" class="space-y-6">
        <div>
          <p class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
            {gettext("Administration")}
          </p>
          <h1 class="mt-2 text-3xl font-semibold tracking-tight">{gettext("Access management")}</h1>
          <p class="mt-2 text-sm text-base-content/70">
            {gettext(
              "Administrators can manage access. Dashboard access can be granted only to administrators. Changing access signs the affected user out."
            )}
          </p>
        </div>
        <div id="access-users" phx-update="stream" class="space-y-3">
          <article
            :for={{id, user} <- @streams.users}
            id={id}
            class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm"
          >
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div class="min-w-0">
                <h2 class="truncate font-semibold">{user.name}</h2>
                <p class="break-all text-sm text-base-content/70">{user.email}</p>
                <p class="mt-2 text-xs font-medium uppercase tracking-wide text-base-content/60">
                  {if user.role == :admin, do: gettext("Administrator"), else: gettext("User")}
                  <span :if={user.role == :admin}>
                    · {if user.can_view_dashboard,
                      do: gettext("Dashboard allowed"),
                      else: gettext("Dashboard denied")}
                  </span>
                </p>
              </div>
              <div class="flex flex-wrap gap-2">
                <button
                  :if={user.role == :user}
                  id={"promote-#{user.id}"}
                  type="button"
                  phx-click="update_access"
                  phx-value-id={user.id}
                  phx-value-action="promote"
                  data-confirm={gettext("Make this user an administrator?")}
                  class="rounded-lg border border-base-300 px-3 py-2 text-sm font-medium hover:bg-base-200 transition"
                >{gettext("Make admin")}</button>
                <button
                  :if={user.role == :admin && user.id != @current_scope.user.id}
                  id={"demote-#{user.id}"}
                  type="button"
                  phx-click="update_access"
                  phx-value-id={user.id}
                  phx-value-action="demote"
                  data-confirm={gettext("Remove this user's administrator access?")}
                  class="rounded-lg border border-base-300 px-3 py-2 text-sm font-medium hover:bg-base-200 transition"
                >{gettext("Remove admin")}</button>
                <button
                  :if={user.role == :admin}
                  id={"dashboard-#{user.id}"}
                  type="button"
                  phx-click="update_access"
                  phx-value-id={user.id}
                  phx-value-action={
                    if user.can_view_dashboard, do: "revoke_dashboard", else: "grant_dashboard"
                  }
                  class="rounded-lg border border-base-300 px-3 py-2 text-sm font-medium hover:bg-base-200 transition"
                >{if user.can_view_dashboard,
                  do: gettext("Revoke dashboard"),
                  else: gettext("Grant dashboard")}</button>
              </div>
            </div>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("update_access", %{"id" => id, "action" => action}, socket)
      when action in ["promote", "demote", "grant_dashboard", "revoke_dashboard"] do
    case Accounts.update_user_access(socket.assigns.current_scope, id, action) do
      {:ok, {user, tokens}} ->
        UserAuth.disconnect_sessions(tokens)

        {:noreply,
         socket |> stream_insert(:users, user) |> put_flash(:info, gettext("Access updated."))}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You are not authorized to manage access."))
         |> redirect(to: ~p"/")}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, gettext("Access could not be updated. Refresh and try again."))}
    end
  end

  def handle_event("update_access", _params, socket) do
    {:noreply, put_flash(socket, :error, gettext("Invalid access change."))}
  end
end
