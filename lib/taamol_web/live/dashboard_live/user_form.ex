defmodule TaamolWeb.DashboardLive.UserForm do
  @moduledoc """
  Create (`/dashboard/users/new`) or edit (`/dashboard/users/:id/edit`) an
  account's name and email. New users get a sign-in link by email.
  """
  use TaamolWeb, :live_view

  alias Taamol.Accounts
  alias Taamol.Accounts.User

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @impl true
  def mount(params, _session, socket) do
    case load(socket, socket.assigns.live_action, params) do
      {:ok, user} ->
        {:ok,
         socket
         |> assign(
           user: user,
           page_title:
             if(socket.assigns.live_action == :new,
               do: gettext("New user"),
               else: gettext("Edit user")
             )
         )
         |> assign(:form, to_form(Accounts.change_user_as_admin(user)))}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("User not found."))
         |> push_navigate(to: ~p"/dashboard/users")}
    end
  end

  defp load(_socket, :new, _params), do: {:ok, %User{}}

  defp load(socket, :edit, %{"id" => id}),
    do: Accounts.get_user_for_admin(socket.assigns.current_scope, id)

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_user_as_admin(socket.assigns.user, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    scope = socket.assigns.current_scope

    case socket.assigns.live_action do
      :new ->
        with {:ok, user} <- Accounts.create_user_as_admin(scope, params) do
          {:ok, _} =
            Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

          {:ok, gettext("User created. A sign-in link was sent to %{email}.", email: user.email)}
        end

      :edit ->
        with {:ok, _user} <- Accounts.update_user_as_admin(scope, socket.assigns.user, params) do
          {:ok, gettext("User updated.")}
        end
    end
    |> case do
      {:ok, message} ->
        {:noreply, socket |> put_flash(:info, message) |> push_navigate(to: ~p"/dashboard/users")}

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
      active={:users}
      title={@page_title}
    >
      <div class="max-w-xl">
        <.link
          navigate={~p"/dashboard/users"}
          class="mb-4 inline-flex items-center gap-1.5 text-sm text-base-content/60 hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4 rtl:rotate-180" />{gettext("Users")}
        </.link>
        <Layouts.dashboard_heading
          title={@page_title}
          subtitle={
            if(@live_action == :new,
              do: gettext("The new user signs in with a link sent to their email."),
              else: gettext("Roles and statistics access are changed from the user list.")
            )
          }
        />

        <.form
          for={@form}
          id="user-form"
          phx-change="validate"
          phx-submit="save"
          class="rounded-2xl border border-base-300 bg-base-100 p-5"
        >
          <.input field={@form[:name]} type="text" label={gettext("Name")} required />
          <.input field={@form[:email]} type="email" label={gettext("Email")} required />
          <div class="mt-4 flex justify-end">
            <button
              type="submit"
              id="save-user"
              phx-disable-with={gettext("Saving…")}
              class="rounded-xl bg-primary px-6 py-2.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
            >
              {if(@live_action == :new, do: gettext("Create user"), else: gettext("Save"))}
            </button>
          </div>
        </.form>
      </div>
    </Layouts.dashboard>
    """
  end
end
