defmodule TaamolWeb.DashboardLive.Users do
  @moduledoc """
  `/dashboard/users`: search, filter and manage accounts (administrators).
  `?search=…&role=admin&page=2` drive the table.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.DashboardComponents

  alias Taamol.Accounts
  alias TaamolWeb.UserAuth

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) && Accounts.subscribe_users(socket.assigns.current_scope) != :ok do
      {:ok, push_navigate(socket, to: ~p"/dashboard")}
    else
      {:ok, assign(socket, page_title: gettext("Users"))}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      "search" => params["search"] || "",
      "role" => if(params["role"] in ["user", "admin"], do: params["role"], else: "")
    }

    page = page_param(params)

    {:noreply,
     socket
     |> assign(filters: filters, filter_form: to_form(filters), page: page)
     |> refresh_users()}
  end

  @impl true
  def handle_info(:users_changed, socket), do: {:noreply, refresh_users(socket)}

  defp refresh_users(socket) do
    filters = socket.assigns.filters
    page = socket.assigns.page

    opts = [
      search: filters["search"],
      role: role_atom(filters["role"]),
      limit: @per_page,
      offset: (page - 1) * @per_page
    ]

    case Accounts.list_users_page(socket.assigns.current_scope, opts) do
      {:ok, %{entries: users, total: total}} ->
        last_page = max(div(total + @per_page - 1, @per_page), 1)

        if page > last_page do
          push_patch(socket, to: list_path(filters, last_page), replace: true)
        else
          socket
          |> assign(total: total)
          |> stream(:users, users, reset: true)
        end

      {:error, :forbidden} ->
        push_navigate(socket, to: ~p"/dashboard")
    end
  end

  defp role_atom("admin"), do: :admin
  defp role_atom("user"), do: :user
  defp role_atom(_), do: nil

  defp list_path(filters, page) do
    query =
      filters
      |> Map.put("page", page)
      |> Enum.reject(fn {_k, v} -> v in ["", 1, nil] end)

    ~p"/dashboard/users?#{query}"
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.take(params, ["search", "role"])
    {:noreply, push_patch(socket, to: list_path(filters, 1))}
  end

  def handle_event("access", %{"id" => id, "action" => action}, socket)
      when action in ["promote", "demote", "grant_dashboard", "revoke_dashboard"] do
    case Accounts.update_user_access(socket.assigns.current_scope, id, action) do
      {:ok, {_user, tokens}} ->
        UserAuth.disconnect_sessions(tokens)

        {:noreply, socket |> refresh_users() |> put_flash(:info, gettext("Access updated."))}

      {:error, :cannot_demote_self} ->
        {:noreply, put_flash(socket, :error, gettext("You can't remove your own admin access."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Access could not be updated."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Accounts.delete_user_as_admin(socket.assigns.current_scope, id) do
      {:ok, {_user, tokens}} ->
        UserAuth.disconnect_sessions(tokens)

        {:noreply,
         socket
         |> refresh_users()
         |> put_flash(:info, gettext("User deleted."))}

      {:error, :cannot_delete_self} ->
        {:noreply, put_flash(socket, :error, gettext("You can't delete your own account here."))}

      {:error, :has_content} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("This user has written articles or comments and can't be deleted.")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("The user could not be deleted."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      unread_messages={@unread_messages}
      pending_bookings={@pending_bookings}
      active={:users}
      title={gettext("Users")}
    >
      <Layouts.dashboard_heading
        title={gettext("Users")}
        subtitle={ngettext("%{count} account", "%{count} accounts", @total)}
      >
        <:actions>
          <.link
            id="new-user"
            navigate={~p"/dashboard/users/new"}
            class="inline-flex items-center gap-1.5 rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-primary-content transition hover:opacity-85"
          >
            <.icon name="hero-plus" class="size-4" />{gettext("New user")}
          </.link>
        </:actions>
      </Layouts.dashboard_heading>

      <.card padded={false}>
        <.form
          for={@filter_form}
          id="users-filter"
          phx-change="filter"
          phx-submit="filter"
          class="flex flex-wrap items-center gap-3 px-5 py-4"
        >
          <.input
            id="users-search"
            type="search"
            name="search"
            value={@filters["search"]}
            phx-debounce="300"
            placeholder={gettext("Search name or email")}
            aria-label={gettext("Search name or email")}
            wrapper_class="mb-0 min-w-56 flex-1"
          />
          <.input
            id="users-role"
            type="select"
            name="role"
            value={@filters["role"]}
            aria-label={gettext("All roles")}
            options={[
              {gettext("All roles"), ""},
              {gettext("Administrators"), "admin"},
              {gettext("Users"), "user"}
            ]}
            wrapper_class="mb-0"
          />
        </.form>

        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="border-y border-base-300 bg-base-200/50 text-xs text-base-content/60">
              <tr>
                <th class="px-5 py-2.5 text-start font-medium">{gettext("User")}</th>
                <th class="px-5 py-2.5 text-start font-medium">{gettext("Role")}</th>
                <th class="hidden px-5 py-2.5 text-start font-medium md:table-cell">
                  {gettext("Status")}
                </th>
                <th class="hidden px-5 py-2.5 text-start font-medium lg:table-cell">
                  {gettext("Joined")}
                </th>
                <th class="px-5 py-2.5 text-end font-medium">{gettext("Actions")}</th>
              </tr>
            </thead>
            <tbody id="users" phx-update="stream" class="divide-y divide-base-300/70">
              <tr id="users-empty" class="hidden only:table-row">
                <td colspan="5" class="px-5 py-10 text-center text-base-content/55">
                  {gettext("No users found.")}
                </td>
              </tr>
              <tr :for={{id, user} <- @streams.users} id={id} class="transition hover:bg-base-200/40">
                <td class="px-5 py-3">
                  <div class="flex items-center gap-3">
                    <Layouts.avatar user={user} />
                    <div class="min-w-0">
                      <p dir="auto" class="truncate font-medium">{user.name}</p>
                      <p class="truncate text-xs text-base-content/55">{user.email}</p>
                    </div>
                  </div>
                </td>
                <td class="px-5 py-3">
                  <span class={[
                    "rounded-md px-2 py-0.5 text-xs font-medium",
                    if(user.role == :admin,
                      do: "bg-primary/12 text-primary",
                      else: "bg-base-200 text-base-content/70"
                    )
                  ]}>
                    {if(user.role == :admin, do: gettext("Administrator"), else: gettext("User"))}
                  </span>
                  <span
                    :if={user.role == :admin && user.can_view_dashboard}
                    class="ms-1 text-xs text-base-content/55"
                  >
                    · {gettext("Statistics")}
                  </span>
                </td>
                <td class="hidden px-5 py-3 md:table-cell">
                  <span
                    :if={user.confirmed_at}
                    class="inline-flex items-center gap-1 text-xs text-success"
                  >
                    <.icon name="hero-check-circle-micro" class="size-3.5" />{gettext("Confirmed")}
                  </span>
                  <span
                    :if={!user.confirmed_at}
                    class="inline-flex items-center gap-1 text-xs text-base-content/55"
                  >
                    <.icon name="hero-clock-micro" class="size-3.5" />{gettext("Invited")}
                  </span>
                </td>
                <td class="hidden px-5 py-3 text-base-content/60 lg:table-cell">
                  {TaamolWeb.NewsComponents.format_date(user.inserted_at)}
                </td>
                <td class="px-5 py-3">
                  <.row_actions user={user} current_user_id={@current_scope.user.id} />
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.pagination
          page={@page}
          per_page={20}
          total={@total}
          path={fn page -> list_path(@filters, page) end}
        />
      </.card>
    </Layouts.dashboard>
    """
  end

  attr :user, :map, required: true
  attr :current_user_id, :string, required: true

  # "⋮" menu with the account actions
  defp row_actions(assigns) do
    ~H"""
    <div class="group/actions relative flex justify-end">
      <button
        type="button"
        id={"actions-#{@user.id}"}
        aria-haspopup="true"
        aria-label={gettext("Actions")}
        class="grid size-8 place-items-center rounded-lg text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
      >
        <.icon name="hero-ellipsis-vertical" class="size-5" />
      </button>
      <div class="invisible absolute end-0 top-full z-20 w-56 pt-1 opacity-0 transition group-focus-within/actions:visible group-focus-within/actions:opacity-100 group-hover/actions:visible group-hover/actions:opacity-100">
        <div class="rounded-xl border border-base-300 bg-base-100 p-1 text-start shadow-xl shadow-base-content/10">
          <.link
            id={"edit-#{@user.id}"}
            navigate={~p"/dashboard/users/#{@user.id}/edit"}
            class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
          >
            <.icon name="hero-pencil-square" class="size-4 text-base-content/50" />{gettext("Edit")}
          </.link>
          <.action_button
            :if={@user.role == :user}
            id={"promote-#{@user.id}"}
            user={@user}
            action="promote"
            icon="hero-shield-check"
            confirm={gettext("Make this user an administrator?")}
          >
            {gettext("Make admin")}
          </.action_button>
          <.action_button
            :if={@user.role == :admin && @user.id != @current_user_id}
            id={"demote-#{@user.id}"}
            user={@user}
            action="demote"
            icon="hero-shield-exclamation"
            confirm={gettext("Remove this user's administrator access?")}
          >
            {gettext("Remove admin")}
          </.action_button>
          <.action_button
            :if={@user.role == :admin}
            id={"dashboard-#{@user.id}"}
            user={@user}
            action={if(@user.can_view_dashboard, do: "revoke_dashboard", else: "grant_dashboard")}
            icon="hero-chart-bar"
          >
            {if(@user.can_view_dashboard,
              do: gettext("Hide statistics"),
              else: gettext("Show statistics")
            )}
          </.action_button>
          <button
            :if={@user.id != @current_user_id}
            type="button"
            id={"delete-#{@user.id}"}
            phx-click="delete"
            phx-value-id={@user.id}
            data-confirm={gettext("Delete this account? This can't be undone.")}
            class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-error hover:bg-error/10"
          >
            <.icon name="hero-trash" class="size-4" />{gettext("Delete")}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :user, :map, required: true
  attr :action, :string, required: true
  attr :icon, :string, required: true
  attr :confirm, :string, default: nil
  slot :inner_block, required: true

  defp action_button(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-click="access"
      phx-value-id={@user.id}
      phx-value-action={@action}
      data-confirm={@confirm}
      class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
    >
      <.icon name={@icon} class="size-4 text-base-content/50" />{render_slot(@inner_block)}
    </button>
    """
  end
end
