defmodule TaamolWeb.DashboardLive.SiteSettings do
  @moduledoc """
  `/dashboard/settings`: site-wide settings (administrators).
  """
  use TaamolWeb, :live_view

  alias Taamol.Settings
  alias Taamol.Settings.SiteSetting

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Site settings"))
     |> assign(:form, to_form(Settings.change()))}
  end

  @impl true
  def handle_event("validate", %{"site_setting" => params}, socket) do
    {:noreply, assign(socket, form: to_form(Settings.change(params), action: :validate))}
  end

  def handle_event("save", %{"site_setting" => params}, socket) do
    case Settings.update(socket.assigns.current_scope, params) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> assign(form: to_form(Settings.change()))
         |> put_flash(:info, gettext("Settings saved."))}

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
      active={:site_settings}
      title={gettext("Site settings")}
    >
      <div class="max-w-2xl">
        <Layouts.dashboard_heading
          title={gettext("Site settings")}
          subtitle={gettext("These settings apply to the whole site.")}
        />

        <.form
          for={@form}
          id="site-settings-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <section class="rounded-2xl border border-base-300 bg-base-100 p-5">
            <h2 class="font-semibold">{gettext("Calendar")}</h2>
            <p class="mb-4 mt-1 text-sm text-base-content/60">
              {gettext(
                "Hijri dates follow the Umm al-Qura calendar. If the new moon is sighted a day earlier or later where the community lives, shift all Hijri dates and holidays here."
              )}
            </p>
            <.input
              field={@form[:hijri_adjustment_days]}
              type="select"
              label={gettext("Hijri date adjustment")}
              options={[
                {gettext("2 days earlier"), -2},
                {gettext("1 day earlier"), -1},
                {gettext("No adjustment"), 0},
                {gettext("1 day later"), 1},
                {gettext("2 days later"), 2}
              ]}
            />
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100 p-5">
            <h2 class="font-semibold">{gettext("Prayer times")}</h2>
            <p class="mb-4 mt-1 text-sm text-base-content/60">
              {gettext("The calculation method used for the prayer times shown on the site.")}
            </p>
            <.input
              field={@form[:prayer_method]}
              type="select"
              label={gettext("Calculation method")}
              options={Enum.map(SiteSetting.prayer_methods(), &{prayer_method_name(&1), &1})}
            />
          </section>

          <section id="donation-settings" class="rounded-2xl border border-base-300 bg-base-100 p-5">
            <h2 class="font-semibold">{gettext("Donations")}</h2>
            <p class="mb-4 mt-1 text-sm text-base-content/60">
              {gettext(
                "Visitors donate with Swish: the app opens with your number, the amount and the message filled in. Leave the number empty to hide donations."
              )}
            </p>
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input
                field={@form[:swish_number]}
                type="text"
                label={gettext("Swish number")}
                placeholder="123 456 78 90"
                inputmode="numeric"
              />
              <.input
                field={@form[:swish_message]}
                type="text"
                label={gettext("Message in Swish")}
                placeholder={gettext("Gift to Taamol")}
                maxlength="50"
              />
            </div>
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100 p-5">
            <h2 class="font-semibold">{gettext("Social media")}</h2>
            <p class="mb-4 mt-1 text-sm text-base-content/60">
              {gettext("Links shown as icons in the site footer. Leave a field empty to hide it.")}
            </p>
            <div class="space-y-1">
              <div :for={network <- TaamolWeb.SocialIcons.networks()} class="flex items-start gap-3">
                <span class="mt-7 grid size-9 shrink-0 place-items-center rounded-full border border-base-300 text-base-content/70">
                  <TaamolWeb.SocialIcons.social_icon network={network} class="size-4" />
                </span>
                <div class="flex-1">
                  <.input
                    field={@form[:"#{network}_url"]}
                    type="url"
                    label={TaamolWeb.SocialIcons.name(network)}
                    placeholder="https://"
                  />
                </div>
              </div>
            </div>
          </section>

          <div class="flex justify-end">
            <button
              type="submit"
              id="save-settings"
              phx-disable-with={gettext("Saving…")}
              class="rounded-xl bg-primary px-6 py-2.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
            >
              {gettext("Save settings")}
            </button>
          </div>
        </.form>
      </div>
    </Layouts.dashboard>
    """
  end

  defp prayer_method_name("MWL"), do: "Muslim World League"
  defp prayer_method_name("ISNA"), do: "Islamic Society of North America"
  defp prayer_method_name("Egypt"), do: "Egyptian General Authority of Survey"
  defp prayer_method_name("Makkah"), do: "Umm al-Qura, Makkah"
  defp prayer_method_name("Karachi"), do: "University of Islamic Sciences, Karachi"
  defp prayer_method_name("Tehran"), do: "Institute of Geophysics, University of Tehran"
  defp prayer_method_name("Jafari"), do: "Shia Ithna Ashari (Jafari)"
  defp prayer_method_name("France"), do: "Union des Organisations Islamiques de France"
  defp prayer_method_name("Russia"), do: "Spiritual Administration of Muslims of Russia"
  defp prayer_method_name("Singapore"), do: "Majlis Ugama Islam Singapura"
end
