defmodule TaamolWeb.ContactLive do
  @moduledoc """
  `/contact`: send feedback, questions or anything else to the team. Messages
  land in the dashboard inbox and the administrators get an email.
  """
  use TaamolWeb, :live_view

  alias Taamol.Contact
  alias Taamol.Contact.Message

  import TaamolWeb.DashboardComponents, only: [card: 1]

  @impl true
  def mount(_params, _session, socket) do
    prefill =
      case socket.assigns.current_scope do
        %{user: user} -> %{"name" => user.name, "email" => user.email}
        _ -> %{}
      end

    {:ok,
     socket
     |> assign(
       page_title: gettext("Contact"),
       sent?: false,
       social_links: Taamol.Settings.social_links(),
       details: Taamol.Settings.contact_details()
     )
     |> assign(:form, to_form(Contact.change_message(%Message{}, prefill)))}
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    changeset = Contact.change_message(%Message{}, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("send", %{"message" => params} = all, socket) do
    case Contact.submit_message(socket.assigns.current_scope, params, all["website"]) do
      {:ok, _message} ->
        {:noreply, assign(socket, sent?: true)}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("You have sent several messages recently. Please try again later.")
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("again", _params, socket) do
    {:noreply,
     socket
     |> assign(sent?: false)
     |> assign(
       :form,
       to_form(
         Contact.change_message(%Message{}, %{
           "name" => socket.assigns.form[:name].value,
           "email" => socket.assigns.form[:email].value
         })
       )
     )}
  end

  defp topic_name(:feedback), do: gettext("Feedback")
  defp topic_name(:question), do: gettext("Question")
  defp topic_name(:events), do: gettext("Events and activities")
  defp topic_name(:other), do: gettext("Something else")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={:contact}>
      <div id="contact" class="mx-auto max-w-7xl px-4 pt-6 sm:px-6 lg:px-8 lg:pt-10">
        <Layouts.page_hero id="contact-hero" class="mb-6">
          <:title>{gettext("Get in touch")}</:title>
          <:subtitle>
            {gettext(
              "Feedback, a question or an idea for an activity? Write to us and we will get back to you."
            )}
          </:subtitle>
        </Layouts.page_hero>

        <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <.card id="contact-card">
            <%= if @sent? do %>
              <div id="contact-sent" class="py-12 text-center">
                <span class="mx-auto grid size-12 place-items-center rounded-full bg-success/15 text-success">
                  <.icon name="hero-check" class="size-6" />
                </span>
                <h2 class="mt-4 text-lg font-semibold">{gettext("Thank you for your message!")}</h2>
                <p class="mx-auto mt-1 max-w-sm text-sm text-base-content/60">
                  {gettext("We read every message and will answer by email as soon as we can.")}
                </p>
                <button
                  type="button"
                  phx-click="again"
                  class="mt-6 rounded-xl border border-base-300 px-5 py-2.5 text-sm font-semibold transition hover:bg-base-200"
                >
                  {gettext("Send another message")}
                </button>
              </div>
            <% else %>
              <.form for={@form} id="contact-form" phx-change="validate" phx-submit="send">
                <div class="grid gap-x-4 sm:grid-cols-2">
                  <.input
                    field={@form[:name]}
                    type="text"
                    label={gettext("Name")}
                    required
                    dir="auto"
                    placeholder={gettext("Your name")}
                  />
                  <.input
                    field={@form[:email]}
                    type="email"
                    label={gettext("Email")}
                    required
                    placeholder="namn@exempel.se"
                  />
                </div>
                <.input
                  field={@form[:topic]}
                  type="select"
                  label={gettext("Topic")}
                  options={Enum.map(Message.topics(), &{topic_name(&1), &1})}
                />
                <.input
                  field={@form[:message]}
                  type="textarea"
                  label={gettext("Message")}
                  rows="7"
                  dir="auto"
                  required
                  placeholder={gettext("Write your message…")}
                />
                <%!-- spam trap: hidden from people, filled in by bots --%>
                <div aria-hidden="true" class="sr-only">
                  <label for="contact-website">Website</label>
                  <input
                    type="text"
                    id="contact-website"
                    name="website"
                    tabindex="-1"
                    autocomplete="off"
                  />
                </div>
                <div class="mt-4 flex flex-wrap items-center justify-between gap-4">
                  <p class="text-xs text-base-content/50">
                    {gettext("We only use your email to answer you.")}
                  </p>
                  <button
                    type="submit"
                    id="send-message"
                    phx-disable-with={gettext("Sending…")}
                    class="inline-flex items-center gap-2 rounded-xl bg-primary px-6 py-2.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
                  >
                    <.icon name="hero-paper-airplane" class="size-4 rtl:-scale-x-100" />
                    {gettext("Send message")}
                  </button>
                </div>
              </.form>
            <% end %>
          </.card>

          <%!-- how else to reach us --%>
          <aside id="contact-details" class="space-y-4">
            <section
              :for={{key, value} <- @details}
              id={"contact-#{key}"}
              class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm"
            >
              <.section_heading
                icon={detail_icon(key)}
                title={detail_title(key)}
                description={detail_description(key)}
              />
              <div class="mt-4 text-base font-bold">
                <%= if href = detail_href(key, value) do %>
                  <a href={href} dir="ltr" class="break-words transition-colors hover:text-primary">
                    {value}
                  </a>
                <% else %>
                  <p
                    class="whitespace-pre-line leading-relaxed [unicode-bidi:plaintext] ltr:text-left rtl:text-right"
                    phx-no-format
                  >{value}</p>
                <% end %>
              </div>
            </section>

            <section
              :if={@social_links != []}
              id="contact-social"
              class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm"
            >
              <.section_heading
                icon="hero-user-group"
                title={gettext("Follow us")}
                description={gettext("Connect with us on social media.")}
              />
              <ul class="mt-4 flex flex-wrap gap-2">
                <li :for={{network, url} <- @social_links}>
                  <a
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer"
                    aria-label={TaamolWeb.SocialIcons.name(network)}
                    title={TaamolWeb.SocialIcons.name(network)}
                    class="grid size-9 place-items-center rounded-lg bg-base-200 text-base-content/70 transition hover:bg-primary hover:text-primary-content"
                  >
                    <TaamolWeb.SocialIcons.social_icon network={network} class="size-4" />
                  </a>
                </li>
              </ul>
            </section>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp detail_icon(:address), do: "hero-map-pin"
  defp detail_icon(:phone), do: "hero-phone"
  defp detail_icon(:email), do: "hero-envelope"
  defp detail_icon(:opening_hours), do: "hero-clock"

  defp detail_title(:address), do: gettext("Address")
  defp detail_title(:phone), do: gettext("Phone")
  defp detail_title(:email), do: gettext("Email")
  defp detail_title(:opening_hours), do: gettext("Opening hours")

  defp detail_description(:address), do: gettext("Visit us at this address.")
  defp detail_description(:phone), do: gettext("Call us at this number.")
  defp detail_description(:email), do: gettext("Email us at this address.")
  defp detail_description(:opening_hours), do: gettext("Our current opening hours.")

  defp detail_href(:phone, phone), do: "tel:" <> String.replace(phone, ~r/[^\d+]/, "")
  defp detail_href(:email, email), do: "mailto:" <> email
  defp detail_href(_key, _value), do: nil
end
