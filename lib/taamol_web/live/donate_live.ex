defmodule TaamolWeb.DonateLive do
  @moduledoc """
  `/donate`: give with Swish. Phones get a button that opens the Swish app
  with everything filled in; computers get a QR code to scan with the app.
  """
  use TaamolWeb, :live_view

  alias Taamol.{Donations, Settings}

  import TaamolWeb.DashboardComponents, only: [card: 1, info_card: 1]

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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={:donate}>
      <div id="donate" class="mx-auto max-w-7xl px-4 pt-6 sm:px-6 lg:px-8 lg:pt-10">
        <Layouts.dashboard_heading
          title={gettext("Support the community")}
          subtitle={
            gettext(
              "Your gift helps us run the centre, the weekend school, youth activities and the programmes during Muharram and Ramadan."
            )
          }
        />

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
          <div class="space-y-6">
            <.card id="donate-amounts" title={gettext("Choose an amount")}>
              <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <button
                  :for={amount <- @amounts}
                  type="button"
                  id={"amount-#{amount}"}
                  phx-click="pick"
                  phx-value-amount={amount}
                  aria-pressed={to_string(@amount == amount)}
                  class="rounded-xl border border-base-300 py-3 text-base font-bold tabular-nums transition hover:border-primary/40 hover:bg-base-200 active:scale-95 aria-pressed:border-primary aria-pressed:bg-primary/10 aria-pressed:text-primary"
                >
                  {gettext("%{amount} kr", amount: amount)}
                </button>
              </div>

              <.form
                for={@custom_form}
                id="custom-amount"
                phx-change="custom"
                phx-submit="custom"
                class="mt-5"
              >
                <div class="fieldset mb-2">
                  <label for="custom-amount-input" class="label mb-1">
                    {gettext("Or another amount")}
                  </label>
                  <div class="relative w-full sm:max-w-72">
                    <input
                      type="number"
                      id="custom-amount-input"
                      name={@custom_form[:amount].name}
                      value={@custom_form[:amount].value}
                      min="1"
                      max="100000"
                      step="1"
                      inputmode="numeric"
                      phx-debounce="300"
                      placeholder="250"
                      class="input w-full pe-12 tabular-nums [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
                    />
                    <span class="pointer-events-none absolute end-4 top-1/2 -translate-y-1/2 text-sm text-base-content/50">
                      {gettext("kr")}
                    </span>
                  </div>
                </div>
              </.form>
              <p class="text-xs text-base-content/50">
                {gettext("You can change the amount in Swish before you confirm.")}
              </p>
            </.card>

            <div class="grid gap-4 sm:grid-cols-3">
              <.info_card
                id="donate-number"
                icon="hero-device-phone-mobile"
                title={gettext("Swish number")}
              >
                <span id="swish-number" dir="ltr" class="font-medium tabular-nums text-base-content">
                  {Donations.format_number(@swish.number)}
                </span>
              </.info_card>
              <.info_card
                id="donate-message"
                icon="hero-chat-bubble-bottom-center-text"
                title={gettext("Message")}
              >
                <span dir="auto">{@swish.message}</span>
              </.info_card>
              <.info_card id="donate-contact" icon="hero-envelope" title={gettext("Contact us")}>
                <.link navigate={~p"/contact"} class="transition-colors hover:text-primary">
                  {gettext("Questions about giving? Write to us.")}
                </.link>
              </.info_card>
            </div>
          </div>

          <.card id="donate-pay" title={gettext("Pay with Swish")} class="lg:self-start">
            <div class="text-center">
              <p id="donate-amount" class="text-3xl font-bold tabular-nums">
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
                  width="208"
                  height="208"
                  class="mx-auto size-52 rounded-xl bg-white p-2.5 ring-1 ring-base-300"
                />
                <p class="mt-3 text-sm text-base-content/60">
                  {gettext("Scan the code with the Swish app on your phone.")}
                </p>
              </div>
            </div>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
