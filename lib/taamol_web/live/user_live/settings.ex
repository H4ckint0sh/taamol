defmodule TaamolWeb.UserLive.Settings do
  use TaamolWeb, :live_view

  on_mount {TaamolWeb.UserAuth, :require_sudo_mode}

  alias Taamol.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      unread_messages={@unread_messages}
      pending_bookings={@pending_bookings}
      active={:account}
      title={gettext("Account settings")}
    >
      <div class="max-w-2xl space-y-4">
        <Layouts.dashboard_heading
          title={gettext("Account Settings")}
          subtitle={gettext("Manage your name, email address and password settings")}
        />

        <.form
          for={@name_form}
          id="name_form"
          action={~p"/users/update-name"}
          method="post"
          phx-change="validate_name"
          phx-submit="update_name"
          phx-trigger-action={@trigger_name_submit}
        >
          <.input
            field={@name_form[:name]}
            type="text"
            label={gettext("Full Name")}
            autocomplete="name"
            required
          />
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save name")}
          </.button>
        </.form>

        <div class="divider" />

        <section
          id="account-prayer-settings"
          class="rounded-2xl border border-base-300 bg-base-100 p-5"
        >
          <h2 class="font-semibold">{gettext("Prayer time preferences")}</h2>
          <p class="mt-1 text-sm text-base-content/60">
            {gettext("Choose your location and calculation settings, and save them to your account.")}
          </p>
          <.link
            id="account-prayer-settings-link"
            navigate={~p"/prayer-times"}
            class="mt-3 inline-flex items-center gap-1 text-sm font-semibold text-primary hover:underline"
          >
            {gettext("Edit prayer time preferences")}
            <.icon name="hero-arrow-right" class="size-4 rtl:rotate-180" />
          </.link>
        </section>

        <div class="divider" />

        <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
          <.input
            field={@email_form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.button variant="primary" phx-disable-with={gettext("Changing...")}>{gettext(
            "Change Email"
          )}</.button>
        </.form>

        <div class="divider" />

        <.form
          for={@password_form}
          id="password_form"
          action={~p"/users/update-password"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <input
            name={@password_form[:email].name}
            type="hidden"
            id="hidden_user_email"
            spellcheck="false"
            value={@current_email}
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label={gettext("New password")}
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label={gettext("Confirm new password")}
            autocomplete="new-password"
            spellcheck="false"
          />
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save Password")}
          </.button>
        </.form>
      </div>
    </Layouts.dashboard>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, gettext("Email changed successfully."))

        {:error, _} ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    name_changeset = Accounts.change_user_name(user)
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:name_form, to_form(name_changeset))
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_name_submit, false)
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_name", %{"user" => user_params}, socket) do
    name_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_name(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, name_form: name_form)}
  end

  def handle_event("update_name", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user, -10) do
      case Accounts.change_user_name(user, user_params) do
        %{valid?: true} = changeset ->
          {:noreply, assign(socket, trigger_name_submit: true, name_form: to_form(changeset))}

        changeset ->
          {:noreply, assign(socket, name_form: to_form(changeset, action: :update))}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("You must re-authenticate to access this page."))
       |> redirect(to: ~p"/users/log-in")}
    end
  end

  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = gettext("A link to confirm your email change has been sent to the new address.")
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
