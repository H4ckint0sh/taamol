defmodule TaamolWeb.DonateLive do
  @moduledoc """
  `/donate`: give with Swish. Phones get a button that opens the Swish app
  with everything filled in; computers get a QR code to scan with the app.
  """
  use TaamolWeb, :live_view

  alias Taamol.{Donations, Settings}

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
      <div id="donate" class="mx-auto max-w-5xl px-4 pt-8 sm:px-6 lg:px-8 lg:pt-14">
        <div class="mx-auto max-w-2xl text-center">
          <span class="mx-auto grid size-14 place-items-center rounded-2xl bg-rose-500/10 text-rose-500">
            <Layouts.donate_icon class="size-8" />
          </span>
          <h1 class="mt-4 text-3xl font-bold tracking-tight sm:text-4xl">
            {gettext("Support the community")}
          </h1>
          <p class="mt-3 text-base-content/65">
            {gettext(
              "Your gift helps us run the centre, the weekend school, youth activities and the programmes during Muharram and Ramadan."
            )}
          </p>
        </div>

        <div
          :if={is_nil(@swish)}
          id="donate-unavailable"
          class="mx-auto mt-10 max-w-md rounded-2xl border border-dashed border-base-300 p-8 text-center text-sm text-base-content/60"
        >
          {gettext("Online donations are not set up yet. Please contact us to give.")}
          <.link navigate={~p"/contact"} class="mt-3 block font-semibold text-primary hover:underline">
            {gettext("Contact us")}
          </.link>
        </div>

        <div
          :if={@swish}
          class="mt-10 grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.85fr)]"
        >
          <%!-- 1. choose an amount --%>
          <section class="rounded-3xl border border-base-300 bg-base-100 p-6 sm:p-8">
            <h2 class="flex items-center gap-2 font-semibold">
              <span class="grid size-6 place-items-center rounded-full bg-primary text-xs font-bold text-primary-content">
                1
              </span>
              {gettext("Choose an amount")}
            </h2>
            <div class="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
              <button
                :for={amount <- @amounts}
                type="button"
                id={"amount-#{amount}"}
                phx-click="pick"
                phx-value-amount={amount}
                aria-pressed={to_string(@amount == amount)}
                class="rounded-2xl border border-base-300 py-4 text-lg font-bold tabular-nums transition hover:border-primary/50 active:scale-95 aria-pressed:border-primary aria-pressed:bg-primary aria-pressed:text-primary-content aria-pressed:shadow-lg aria-pressed:shadow-primary/25"
              >
                {gettext("%{amount} kr", amount: amount)}
              </button>
            </div>
            <.form
              for={@custom_form}
              id="custom-amount"
              phx-change="custom"
              phx-submit="custom"
              class="mt-4"
            >
              <label for="custom-amount-input" class="text-sm text-base-content/65">
                {gettext("Or another amount")}
              </label>
              <div class="relative mt-1.5">
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
                  class="w-full rounded-2xl border border-base-300 bg-base-100 py-3 pe-12 ps-4 text-lg font-semibold tabular-nums outline-none transition focus:border-primary"
                />
                <span class="absolute end-4 top-1/2 -translate-y-1/2 text-sm text-base-content/50">
                  {gettext("kr")}
                </span>
              </div>
            </.form>

            <dl class="mt-6 space-y-2 rounded-2xl bg-base-200/70 p-4 text-sm">
              <div class="flex justify-between gap-4">
                <dt class="text-base-content/60">{gettext("Swish number")}</dt>
                <dd id="swish-number" class="font-semibold tabular-nums" dir="ltr">
                  {Donations.format_number(@swish.number)}
                </dd>
              </div>
              <div class="flex justify-between gap-4">
                <dt class="text-base-content/60">{gettext("Message")}</dt>
                <dd dir="auto" class="font-medium">{@swish.message}</dd>
              </div>
            </dl>
          </section>

          <%!-- 2. pay with Swish --%>
          <section class="rounded-3xl border border-base-300 bg-base-100 p-6 text-center sm:p-8">
            <h2 class="flex items-center justify-center gap-2 font-semibold">
              <span class="grid size-6 place-items-center rounded-full bg-primary text-xs font-bold text-primary-content">
                2
              </span>
              {gettext("Pay with Swish")}
            </h2>
            <p id="donate-amount" class="mt-1 text-3xl font-bold tabular-nums">
              {gettext("%{amount} kr", amount: @amount)}
            </p>

            <a
              id="open-swish"
              href={Donations.app_link(@swish, @amount)}
              class="mt-5 flex items-center justify-center gap-2 rounded-2xl bg-[#1a8c5c] px-5 py-3.5 font-semibold text-white shadow-lg shadow-[#1a8c5c]/25 transition hover:brightness-110 active:scale-[0.98] lg:hidden"
            >
              <.icon name="hero-device-phone-mobile" class="size-5" />
              {gettext("Open Swish")}
            </a>

            <div class="mt-5 hidden lg:block">
              <img
                id="swish-qr"
                src={~p"/donate/qr.png?#{[amount: @amount]}"}
                alt={gettext("Swish QR code for %{amount} kr", amount: @amount)}
                width="220"
                height="220"
                class="mx-auto size-56 rounded-2xl bg-white p-2 ring-1 ring-base-300"
              />
              <p class="mt-3 text-sm text-base-content/60">
                {gettext("Scan the code with the Swish app on your phone.")}
              </p>
            </div>

            <p class="mt-5 text-xs text-base-content/50">
              {gettext("You can change the amount in Swish before you confirm.")}
            </p>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
