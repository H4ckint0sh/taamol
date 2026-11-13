defmodule TaamolWeb.PrayerTimesLive do
  use TaamolWeb, :live_view

  alias Taamol.{Accounts, CitySearch, PrayTime, PrayerSettings}

  @impl true
  def mount(_params, _session, socket) do
    saved = socket.assigns.current_scope && socket.assigns.current_scope.user.prayer_settings
    attrs = saved || %{"method" => Taamol.Settings.get(:prayer_method)}

    {:ok,
     socket
     |> assign(
       page_title: gettext("Prayer times"),
       city_search_form: to_form(%{"query" => ""}, as: :city_search),
       city_search_state: :idle,
       cities_by_id: %{},
       date_edited?: false
     )
     |> stream(:cities, [])
     |> assign_calculation(PrayerSettings.changeset(attrs))}
  end

  @impl true
  def handle_event("calculate", %{"prayer" => attrs} = params, socket) do
    attrs =
      if params["_target"] in [["prayer", "latitude"], ["prayer", "longitude"]] do
        Map.merge(attrs, %{"city" => "", "timezone" => ""})
      else
        attrs
      end

    socket =
      if params["_target"] == ["prayer", "date"],
        do: assign(socket, date_edited?: true),
        else: socket

    {:noreply, assign_calculation(socket, PrayerSettings.changeset(attrs), :validate)}
  end

  def handle_event("city-today", %{"timezone" => timezone, "date" => date}, socket)
      when is_binary(timezone) and is_binary(date) do
    current_timezone = Ecto.Changeset.get_field(socket.assigns.form.source, :timezone)

    if not socket.assigns.date_edited? and timezone == current_timezone and
         match?({:ok, _}, Date.from_iso8601(date)) do
      attrs = Map.put(current_params(socket), "date", date)
      {:noreply, assign_calculation(socket, PrayerSettings.changeset(attrs))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("search-cities", %{"city_search" => %{"query" => query}}, socket)
      when is_binary(query) do
    query = String.trim(query)

    if socket.assigns.city_search_state == :loading and String.length(query) in 3..100 and
         query == String.trim(socket.assigns.city_search_form[:query].value || "") do
      language = Gettext.get_locale(TaamolWeb.Gettext)

      {:noreply,
       socket
       |> assign(city_search_state: :loading, cities_by_id: %{})
       |> stream(:cities, [], reset: true)
       |> start_async(:city_search, fn -> CitySearch.search(query, language) end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("city-query-changed", %{"query" => query}, socket) when is_binary(query) do
    query = String.slice(query, 0, 100)
    state = if String.length(String.trim(query)) >= 3, do: :loading, else: :idle

    {:noreply,
     socket
     |> cancel_async(:city_search)
     |> assign(
       city_search_form: to_form(%{"query" => query}, as: :city_search),
       city_search_state: state,
       cities_by_id: %{}
     )
     |> stream(:cities, [], reset: true)}
  end

  def handle_event("close-city-search", _, socket) do
    {:noreply,
     socket
     |> cancel_async(:city_search)
     |> assign(city_search_state: :idle, cities_by_id: %{})
     |> stream(:cities, [], reset: true)}
  end

  def handle_event("select-city", %{"id" => id}, socket) do
    case socket.assigns.cities_by_id[id] do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Please search for the city again."))}

      city ->
        attrs =
          current_params(socket)
          |> Map.merge(%{
            "city" => city.name,
            "timezone" => city.timezone,
            "latitude" => city.latitude,
            "longitude" => city.longitude
          })

        {:noreply,
         socket
         |> assign(
           city_search_form: to_form(%{"query" => ""}, as: :city_search),
           city_search_state: :idle,
           cities_by_id: %{}
         )
         |> stream(:cities, [], reset: true)
         |> assign_calculation(PrayerSettings.changeset(attrs), :validate)}
    end
  end

  def handle_event("manual-location", _, socket) do
    attrs = Map.merge(current_params(socket), %{"city" => "", "timezone" => ""})
    {:noreply, assign_calculation(socket, PrayerSettings.changeset(attrs), :validate)}
  end

  def handle_event("site-preset", _, socket) do
    attrs =
      socket
      |> current_params()
      |> Map.take(~w(city timezone latitude longitude utc_offset date))
      |> Map.put("method", Taamol.Settings.get(:prayer_method))

    {:noreply, assign_calculation(socket, PrayerSettings.changeset(attrs), :validate)}
  end

  def handle_event("save", %{"prayer" => attrs}, socket) do
    case Accounts.update_prayer_settings(socket.assigns.current_scope, attrs) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign_calculation(PrayerSettings.changeset(attrs))
         |> put_flash(:info, gettext("Prayer time preferences saved."))}

      {:error, %Ecto.Changeset{data: %PrayerSettings{}} = changeset} ->
        {:noreply, assign_calculation(socket, changeset, :validate)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save your preferences."))}
    end
  end

  @impl true
  def handle_async(:city_search, {:ok, {:ok, cities}}, socket) do
    {:noreply,
     socket
     |> assign(
       city_search_state: if(cities == [], do: :empty, else: :results),
       cities_by_id: Map.new(cities, &{Integer.to_string(&1.id), &1})
     )
     |> stream(:cities, cities, reset: true)}
  end

  def handle_async(:city_search, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:city_search, _error, socket) do
    {:noreply, assign(socket, city_search_state: :error, cities_by_id: %{})}
  end

  defp current_params(socket), do: socket.assigns.form.source.params || %{}

  defp assign_calculation(socket, changeset, action \\ nil) do
    {result, timezone, format} =
      case Ecto.Changeset.apply_action(changeset, :validate) do
        {:ok, settings} ->
          calculator = PrayerSettings.calculator(settings)

          calculator =
            if settings.timezone, do: PrayTime.format(calculator, "x"), else: calculator

          {PrayTime.times(calculator, settings.date), settings.timezone, settings.format}

        {:error, _} ->
          {nil, nil, nil}
      end

    assign(socket,
      form: to_form(changeset, as: :prayer, action: action),
      times: result,
      city_timezone: timezone,
      time_format: format,
      city_selected?: not is_nil(Ecto.Changeset.get_field(changeset, :timezone))
    )
  end

  defp prayers do
    [
      {:fajr, gettext("Fajr")},
      {:sunrise, gettext("Sunrise")},
      {:dhuhr, gettext("Dhuhr")},
      {:asr, gettext("Asr")},
      {:sunset, gettext("Sunset")},
      {:maghrib, gettext("Maghrib")},
      {:isha, gettext("Isha")},
      {:midnight, gettext("Midnight")}
    ]
  end

  defp tune_fields do
    [
      {:tune_fajr, gettext("Fajr")},
      {:tune_sunrise, gettext("Sunrise")},
      {:tune_dhuhr, gettext("Dhuhr")},
      {:tune_asr, gettext("Asr")},
      {:tune_sunset, gettext("Sunset")},
      {:tune_maghrib, gettext("Maghrib")},
      {:tune_isha, gettext("Isha")},
      {:tune_midnight, gettext("Midnight")}
    ]
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :field_class,
        "block h-10 w-full min-w-0 rounded-xl border border-base-300 bg-base-100 px-3 text-sm text-base-content shadow-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/10"
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div id="prayer-times-page" class="mx-auto max-w-7xl px-4 pt-6 sm:px-6 lg:px-8 lg:pt-10">
        <Layouts.page_hero id="prayer-times-hero">
          <:title>{gettext("Prayer times")}</:title>
          <:subtitle>
            {gettext(
              "Calculate prayer times for a place and date, using the settings that are right for you."
            )}
          </:subtitle>
        </Layouts.page_hero>

        <.form
          for={@form}
          id="prayer-settings-form"
          phx-change="calculate"
          phx-submit="save"
          class="mt-8 grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]"
        >
          <div class="space-y-5">
            <section
              id="prayer-location"
              class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm sm:p-6"
            >
              <.section_heading
                icon="hero-map-pin"
                title={gettext("Place and date")}
                description={
                  gettext("Search for a city or enter coordinates and UTC offset manually.")
                }
              />
              <div class="mt-5 grid gap-x-4 sm:grid-cols-2">
                <div id="city-search" phx-hook="CitySearch" class="relative">
                  <.input
                    id="city-search-input"
                    field={@city_search_form[:query]}
                    type="search"
                    label={gettext("Find a city")}
                    placeholder={gettext("For example, Stockholm")}
                    class={@field_class}
                    maxlength="100"
                    autocomplete="off"
                    phx-change="search-cities"
                    phx-debounce="350"
                    role="combobox"
                    aria-autocomplete="list"
                    aria-controls="city-search-results"
                    aria-expanded={to_string(@city_search_state != :idle)}
                  />
                  <div
                    id="city-search-popup"
                    class={[
                      "absolute inset-x-0 top-full z-30 mt-1 overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-xl shadow-base-content/10",
                      @city_search_state == :idle && "hidden"
                    ]}
                  >
                    <p
                      :if={@city_search_state == :loading}
                      id="city-search-loading"
                      role="status"
                      class="px-4 py-4 text-sm text-base-content/60"
                    >
                      {gettext("Searching for cities...")}
                    </p>
                    <p
                      :if={@city_search_state == :empty}
                      id="city-search-empty"
                      role="status"
                      class="px-4 py-4 text-sm text-base-content/60"
                    >
                      {gettext("No cities found. Try another name.")}
                    </p>
                    <p
                      :if={@city_search_state == :error}
                      id="city-search-error"
                      role="alert"
                      class="px-4 py-4 text-sm text-error"
                    >
                      {gettext("City search is unavailable. Please try again.")}
                    </p>
                    <ul
                      id="city-search-results"
                      phx-update="stream"
                      role="listbox"
                      aria-label={gettext("City search results")}
                      class="max-h-64 overflow-y-auto p-1.5"
                    >
                      <li :for={{id, city} <- @streams.cities} id={id} role="presentation">
                        <button
                          type="button"
                          role="option"
                          aria-selected="false"
                          id={"select-city-#{city.id}"}
                          phx-click="select-city"
                          phx-value-id={city.id}
                          class="flex w-full items-center gap-3 rounded-xl px-3 py-3 text-start transition hover:bg-base-200 focus-visible:bg-base-200 focus-visible:outline-2 focus-visible:outline-primary"
                        >
                          <span class="grid size-9 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary">
                            <.icon name="hero-map-pin" class="size-4" />
                          </span>
                          <span class="min-w-0 flex-1">
                            <span class="block text-sm font-semibold">{city.name}</span>
                            <span class="block text-xs text-base-content/55">{city.timezone}</span>
                          </span>
                          <.icon
                            name="hero-arrow-up-left"
                            class="size-4 shrink-0 text-base-content/35"
                          />
                        </button>
                      </li>
                    </ul>
                  </div>
                </div>
                <.input
                  field={@form[:date]}
                  type="date"
                  label={gettext("Date")}
                  class={@field_class}
                  required
                />
              </div>
              <p class="mt-1 text-xs text-base-content/55">
                {gettext("Enter at least 3 characters. City searches are sent to Open-Meteo.")}
              </p>
              <p :if={!@city_selected?} class="mt-2 text-xs text-base-content/55">
                {gettext(
                  "Enter coordinates and the UTC offset for the selected date, including daylight saving time if applicable."
                )}
              </p>
              <div
                :if={@city_selected?}
                id="selected-city"
                phx-hook="CityToday"
                data-timezone={@form[:timezone].value}
                data-auto-date={to_string(!@date_edited?)}
                class="mt-4 flex flex-wrap items-center justify-between gap-2 rounded-xl bg-primary/10 px-4 py-3 text-sm"
              >
                <span class="font-semibold text-primary">
                  <.icon name="hero-map-pin" class="size-4" />
                  {@form[:city].value} · {@form[:timezone].value}
                </span>
                <button
                  id="manual-location"
                  type="button"
                  phx-click="manual-location"
                  class="font-semibold text-primary hover:underline"
                >
                  {gettext("Use manual offset")}
                </button>
              </div>
              <.input field={@form[:city]} type="hidden" />
              <.input field={@form[:timezone]} type="hidden" />
              <p class="mt-2 text-xs text-base-content/55">
                {gettext(
                  "These preferences apply to this calculator. The site prayer widget uses your device location and the site method."
                )}
              </p>
              <div class="mt-4 grid gap-x-4 sm:grid-cols-2">
                <.input
                  field={@form[:latitude]}
                  type="number"
                  step="any"
                  min="-89.999999"
                  max="89.999999"
                  label={gettext("Latitude")}
                  class={@field_class}
                  required
                />
                <.input
                  field={@form[:longitude]}
                  type="number"
                  step="any"
                  min="-180"
                  max="180"
                  label={gettext("Longitude")}
                  class={@field_class}
                  required
                />
                <.input
                  :if={!@city_selected?}
                  field={@form[:utc_offset]}
                  type="number"
                  step="any"
                  min="-12"
                  max="14"
                  label={gettext("UTC offset (hours)")}
                  class={@field_class}
                  required
                />
                <.input :if={@city_selected?} field={@form[:utc_offset]} type="hidden" />
              </div>
            </section>

            <section
              id="prayer-calculation"
              class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm sm:p-6"
            >
              <.section_heading
                icon="hero-cog-6-tooth"
                title={gettext("Calculation")}
                description={
                  gettext(
                    "Leave custom angles and midnight empty to use the selected method's defaults. Angles are in degrees; append “min” for a time interval."
                  )
                }
              >
                <:actions>
                  <button
                    id="site-prayer-preset"
                    type="button"
                    phx-click="site-preset"
                    class="rounded-full bg-primary/10 px-3 py-1.5 text-xs font-bold text-primary transition hover:bg-primary/20 active:scale-95"
                  >
                    {gettext("Use site preset")}
                  </button>
                </:actions>
              </.section_heading>
              <div class="mt-4 grid gap-x-4 sm:grid-cols-2">
                <.input
                  field={@form[:method]}
                  type="select"
                  label={gettext("Calculation method")}
                  class={@field_class}
                  options={Enum.map(Taamol.Settings.SiteSetting.prayer_methods(), &{&1, &1})}
                />
                <.input
                  field={@form[:high_lats]}
                  type="select"
                  label={gettext("High latitude adjustment")}
                  class={@field_class}
                  options={[
                    {gettext("None"), "None"},
                    {gettext("Middle of the night"), "NightMiddle"},
                    {gettext("One seventh of the night"), "OneSeventh"},
                    {gettext("Angle based"), "AngleBased"}
                  ]}
                />
                <.input
                  field={@form[:fajr]}
                  type="number"
                  step="any"
                  min="0.01"
                  max="90"
                  label={gettext("Fajr angle")}
                  placeholder={gettext("Method default")}
                  class={@field_class}
                />
                <.input
                  field={@form[:isha]}
                  type="text"
                  label={gettext("Isha angle or minutes")}
                  placeholder={gettext("Method default")}
                  class={@field_class}
                />
                <.input
                  field={@form[:maghrib]}
                  type="text"
                  label={gettext("Maghrib angle or minutes")}
                  placeholder={gettext("Method default")}
                  class={@field_class}
                />
                <.input
                  field={@form[:dhuhr]}
                  type="number"
                  min="-180"
                  max="180"
                  label={gettext("Dhuhr offset (minutes)")}
                  class={@field_class}
                  required
                />
                <.input
                  field={@form[:asr]}
                  type="text"
                  label={gettext("Asr shadow factor")}
                  class={@field_class}
                />
                <.input
                  field={@form[:midnight]}
                  type="select"
                  label={gettext("Midnight")}
                  class={@field_class}
                  options={[
                    {gettext("Method default"), ""},
                    {gettext("Standard"), "Standard"},
                    {"Jafari", "Jafari"}
                  ]}
                />
                <.input
                  field={@form[:iterations]}
                  type="number"
                  min="1"
                  max="10"
                  label={gettext("Calculation iterations")}
                  class={@field_class}
                  required
                />
                <.input
                  field={@form[:rounding]}
                  type="select"
                  label={gettext("Rounding")}
                  class={@field_class}
                  options={[
                    {gettext("Nearest minute"), "nearest"},
                    {gettext("Up"), "up"},
                    {gettext("Down"), "down"},
                    {gettext("None"), "none"}
                  ]}
                />
                <.input
                  field={@form[:format]}
                  type="select"
                  label={gettext("Time format")}
                  class={@field_class}
                  options={[
                    {"24-hour", "24h"},
                    {"12-hour AM/PM", "12h"},
                    {"12-hour", "12H"},
                    {gettext("Unix milliseconds"), "x"},
                    {gettext("Unix seconds"), "X"}
                  ]}
                />
              </div>
              <p class="mt-2 text-xs text-base-content/55">
                {gettext("Asr accepts Standard, Hanafi, or a positive shadow factor.")}
              </p>
            </section>

            <section
              id="prayer-tuning"
              class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm sm:p-6"
            >
              <.section_heading
                icon="hero-adjustments-horizontal"
                title={gettext("Fine-tune times")}
                description={gettext("Adjust each time by a number of minutes.")}
              />
              <div class="mt-4 grid gap-x-4 sm:grid-cols-2">
                <.input
                  :for={{field, label} <- tune_fields()}
                  field={@form[field]}
                  type="number"
                  icon="hero-clock"
                  min="-180"
                  max="180"
                  label={label}
                  class={@field_class}
                  required
                />
              </div>
            </section>
          </div>

          <aside class="space-y-4 lg:sticky lg:top-24">
            <section
              id="prayer-results"
              class="rounded-2xl border border-primary/15 bg-gradient-to-br from-primary/[0.06] via-base-100 to-base-100 p-5 shadow-sm"
            >
              <.section_heading
                icon="hero-clock"
                title={gettext("Prayer schedule")}
                description={gettext("Times update as you edit")}
              />
              <div :if={@times} class="mt-4 divide-y divide-base-300/70">
                <div
                  :for={{key, label} <- prayers()}
                  id={"result-#{key}"}
                  class="flex items-center justify-between gap-4 py-3 text-sm"
                >
                  <span class="text-base-content/70">{label}</span>
                  <span
                    :if={@city_timezone}
                    id={"city-time-#{key}"}
                    phx-hook="CityPrayerTime"
                    phx-update="ignore"
                    data-timestamp={Map.fetch!(@times, key)}
                    data-timezone={@city_timezone}
                    data-format={@time_format}
                    data-error={gettext("Time zone unavailable")}
                    class="font-bold tabular-nums"
                  >{gettext("Loading...")}</span>
                  <span :if={!@city_timezone} class="font-bold tabular-nums">{Map.fetch!(@times, key)}</span>
                </div>
              </div>
              <p :if={!@times} id="prayer-invalid" class="mt-4 text-sm text-error">
                {gettext("Please correct the settings to calculate prayer times.")}
              </p>
              <p class="mt-3 text-xs leading-relaxed text-base-content/55">
                {gettext("A dash means a time cannot be calculated for this location and date.")}
              </p>
              <p :if={@city_timezone} class="mt-2 text-xs text-base-content/55">
                {gettext("City times use the selected time zone, including daylight saving time.")}
              </p>
            </section>

            <%= if @current_scope do %>
              <button
                id="save-prayer-settings"
                type="submit"
                class="flex w-full items-center justify-center gap-2 rounded-xl bg-primary px-4 py-3 text-sm font-bold text-primary-content transition hover:opacity-85 active:scale-[0.98]"
              >
                <.icon name="hero-bookmark" class="size-4" />
                {gettext("Save to my account")}
              </button>
              <p class="text-center text-xs text-base-content/55">
                {gettext("Your date is not saved. Find these preferences from account settings.")}
              </p>
            <% else %>
              <div class="rounded-2xl border border-base-300 bg-base-100 p-4 text-sm text-base-content/70">
                {gettext("Want to keep these settings?")}
                <.link navigate={~p"/users/log-in"} class="font-semibold text-primary hover:underline">{gettext(
                  "Log in"
                )}</.link>
                {gettext("to save them to your account.")}
              </div>
            <% end %>
          </aside>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
