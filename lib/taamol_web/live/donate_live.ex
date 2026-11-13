defmodule TaamolWeb.DonateLive do
  @moduledoc """
  `/donate`: give with Swish. Phones get a button that opens the Swish app
  with everything filled in; computers get a QR code to scan with the app.
  """
  use TaamolWeb, :live_view

  alias Taamol.{Donations, Settings}

  import TaamolWeb.DashboardComponents, only: [card: 1]

  @amounts [100, 200, 500, 1000]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Donate"),
       swish: Settings.swish(),
       amounts: @amounts,
       amount: 200,
       custom_form: to_form(%{"amount" => ""}, as: :custom)
     )}
  end

  @impl true
  def handle_event("pick", %{"amount" => amount}, socket) do
    {:noreply, assign_amount(socket, amount)}
  end

  def handle_event("custom", %{"custom" => %{"amount" => amount}}, socket) do
    {:noreply,
     socket
     |> assign(custom_form: to_form(%{"amount" => amount}, as: :custom))
     |> assign_amount(amount)}
  end

  defp assign_amount(socket, value) do
    case Integer.parse(to_string(value)) do
      {amount, ""} when amount in 1..100_000 -> assign(socket, amount: amount)
      _ -> socket
    end
  end

  defp causes do
    [
      %{
        key: "centre",
        icon: "hero-building-library",
        image: ~p"/images/donate/centre.jpg",
        title: gettext("Our centre"),
        text: gettext("Keeping the hussainiya open for prayers, gatherings and lectures.")
      },
      %{
        key: "school",
        icon: "hero-academic-cap",
        image: ~p"/images/donate/school.jpg",
        title: gettext("Weekend school"),
        text: gettext("Quran, faith and Persian classes for children and teenagers.")
      },
      %{
        key: "youth",
        icon: "hero-user-group",
        image: ~p"/images/donate/youth.jpg",
        title: gettext("Youth activities"),
        text: gettext("Programmes, sports and meeting places for young people.")
      },
      %{
        key: "programmes",
        icon: "hero-moon",
        image: ~p"/images/donate/programmes.jpg",
        title: gettext("Muharram and Ramadan"),
        text: gettext("Majlis, iftars and nazri during the holy months.")
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={:donate}>
      <div id="donate" class="mx-auto max-w-7xl px-4 pt-6 sm:px-6 lg:px-8 lg:pt-10">
        <%!-- what a gift supports --%>
        <section id="donate-causes" class="mb-12">
          <Layouts.page_hero id="donate-hero">
            <:title>
              {gettext("Support")}
              {gettext("where it matters most.")}
            </:title>
            <:subtitle>
              {gettext(
                "Your gift helps us run the centre, the weekend school, youth activities and the programmes during Muharram and Ramadan."
              )}
            </:subtitle>
          </Layouts.page_hero>

          <ul class="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <li
              :for={cause <- causes()}
              id={"cause-#{cause.key}"}
              class="group relative isolate flex min-h-72 flex-col overflow-hidden rounded-2xl bg-zinc-900 p-6 text-white"
            >
              <img
                src={cause.image}
                alt=""
                loading="lazy"
                class="absolute inset-0 -z-20 size-full object-cover transition duration-500 group-hover:scale-105"
              />
              <%!-- a soft dark fade behind the text --%>
              <div
                aria-hidden="true"
                class="absolute inset-0 -z-10 bg-gradient-to-t from-black/80 via-black/30 to-black/0"
              />
              <span class="grid size-10 place-items-center rounded-lg bg-white/15 text-white ring-1 ring-white/25 backdrop-blur-sm">
                <.icon name={cause.icon} class="size-5" />
              </span>
              <div class="mt-auto pt-10">
                <h2 class="text-lg font-bold">{cause.title}</h2>
                <p class="mt-2 min-h-[2lh] text-sm leading-relaxed text-white/80">{cause.text}</p>
              </div>
            </li>
          </ul>
        </section>

        <div
          :if={is_nil(@swish)}
          id="donate-unavailable"
          class="rounded-2xl border border-dashed border-base-300 bg-base-100 p-10 text-center text-sm text-base-content/60"
        >
          {gettext("Online donations are not set up yet. Please contact us to give.")}
          <.link navigate={~p"/contact"} class="mt-3 block font-semibold text-primary hover:underline">
            {gettext("Contact us")}
          </.link>
        </div>

        <div :if={@swish} class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <.card id="donate-amounts" title={gettext("Choose an amount")}>
            <div class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_auto]">
              <div>
                <.segmented_control
                  id="donate-amount-options"
                  role="group"
                  aria-label={gettext("Choose an amount")}
                >
                  <button
                    :for={amount <- @amounts}
                    type="button"
                    id={"amount-#{amount}"}
                    phx-click="pick"
                    phx-value-amount={amount}
                    aria-pressed={to_string(@amount == amount)}
                    class={segmented_option_class()}
                  >
                    {gettext("%{amount} kr", amount: amount)}
                  </button>
                </.segmented_control>

                <.form
                  for={@custom_form}
                  id="custom-amount"
                  phx-change="custom"
                  phx-submit="custom"
                  class="mt-5"
                >
                  <.input
                    field={@custom_form[:amount]}
                    type="number"
                    id="custom-amount-input"
                    icon="hero-banknotes"
                    label={"#{gettext("Or another amount")} (#{gettext("kr")})"}
                    min="1"
                    max="100000"
                    step="1"
                    inputmode="numeric"
                    phx-debounce="300"
                    placeholder="250"
                    wrapper_class="sm:max-w-72"
                  />
                </.form>
                <p class="text-xs text-base-content/50">
                  {gettext("You can change the amount in Swish before you confirm.")}
                </p>
              </div>

              <%!-- pay: QR code on computers, the Swish app button on phones --%>
              <div
                id="donate-pay"
                class="text-center lg:border-s lg:border-base-300 lg:ps-8"
              >
                <p class="text-xs font-medium text-base-content/55">{gettext("Pay with Swish")}</p>
                <p id="donate-amount" class="mt-1 text-3xl font-bold tabular-nums">
                  {gettext("%{amount} kr", amount: @amount)}
                </p>

                <a
                  id="open-swish"
                  href={Donations.app_link(@swish, @amount)}
                  class="mt-4 flex items-center justify-center gap-2 rounded-xl bg-[#1a8c5c] px-5 py-2.5 text-sm font-semibold text-white transition hover:opacity-85 lg:hidden"
                >
                  <.icon name="hero-device-phone-mobile" class="size-5" />
                  {gettext("Open Swish")}
                </a>

                <div class="mt-4 hidden lg:block">
                  <img
                    id="swish-qr"
                    src={~p"/donate/qr.png?#{[amount: @amount]}"}
                    alt={gettext("Swish QR code for %{amount} kr", amount: @amount)}
                    width="176"
                    height="176"
                    class="mx-auto size-44 rounded-xl bg-white p-2 ring-1 ring-base-300"
                  />
                  <p class="mx-auto mt-3 max-w-56 text-xs text-base-content/60">
                    {gettext("Scan the code with the Swish app on your phone.")}
                  </p>
                </div>
              </div>
            </div>
          </.card>

          <aside id="donate-details" class="grid gap-4 sm:grid-cols-3 lg:grid-cols-1 lg:content-start">
            <section
              id="donate-number"
              class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm"
            >
              <.section_heading
                icon="hero-device-phone-mobile"
                title={gettext("Swish number")}
                description={gettext("Use this number when donating with Swish.")}
              />
              <p class="mt-4 text-base font-bold tabular-nums">
                <span id="swish-number" dir="ltr">{Donations.format_number(@swish.number)}</span>
              </p>
            </section>
            <section
              id="donate-message"
              class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm"
            >
              <.section_heading
                icon="hero-chat-bubble-bottom-center-text"
                title={gettext("Message")}
                description={gettext("Include this message with your donation.")}
              />
              <p dir="auto" class="mt-4 text-base font-bold">{@swish.message}</p>
            </section>
            <section
              id="donate-contact"
              class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm"
            >
              <.section_heading
                icon="hero-envelope"
                title={gettext("Contact us")}
                description={gettext("We're here to help with your donation.")}
              />
              <.link
                navigate={~p"/contact"}
                class="mt-4 inline-flex text-sm font-semibold text-primary transition hover:opacity-75"
              >
                {gettext("Questions about giving? Write to us.")}
              </.link>
            </section>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
