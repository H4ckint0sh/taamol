defmodule TaamolWeb.ContactLive do
  @moduledoc """
  `/contact`: send feedback, questions or anything else to the team. Messages
  land in the dashboard inbox and the administrators get an email.
  """
  use TaamolWeb, :live_view

  alias Taamol.Contact
  alias Taamol.Contact.Message

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
       social_links: Taamol.Settings.social_links()
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
      <div id="contact" class="mx-auto max-w-5xl px-4 pt-8 sm:px-6 lg:px-8 lg:pt-14">
        <div class="max-w-2xl">
          <h1 class="text-3xl font-bold tracking-tight sm:text-4xl">{gettext("Get in touch")}</h1>
          <p class="mt-3 text-base-content/65">
            {gettext(
              "Feedback, a question or an idea for an activity? Write to us and we will get back to you."
            )}
          </p>
        </div>

        <div class="mt-8 grid gap-6 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <section class="rounded-3xl border border-base-300 bg-base-100 p-6 sm:p-8">
            <%= if @sent? do %>
              <div id="contact-sent" class="py-10 text-center">
                <span class="mx-auto grid size-14 place-items-center rounded-full bg-success/15 text-success">
                  <.icon name="hero-check" class="size-7" />
                </span>
                <h2 class="mt-4 text-xl font-bold">{gettext("Thank you for your message!")}</h2>
                <p class="mt-2 text-sm text-base-content/65">
                  {gettext("We read every message and will answer by email as soon as we can.")}
                </p>
                <button
                  type="button"
                  phx-click="again"
                  class="mt-6 rounded-full border border-base-300 px-5 py-2 text-sm font-medium transition hover:bg-base-200"
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
                  />
                  <.input field={@form[:email]} type="email" label={gettext("Email")} required />
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
                  rows="6"
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
                <div class="mt-4 flex items-center justify-between gap-4">
                  <p class="text-xs text-base-content/50">
                    {gettext("We only use your email to answer you.")}
                  </p>
                  <button
                    type="submit"
                    id="send-message"
                    phx-disable-with={gettext("Sending…")}
                    class="inline-flex items-center gap-2 rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
                  >
                    <.icon name="hero-paper-airplane" class="size-4 rtl:-scale-x-100" />
                    {gettext("Send message")}
                  </button>
                </div>
              </.form>
            <% end %>
          </section>

          <aside class="space-y-4">
            <section
              :if={@social_links != []}
              class="rounded-3xl border border-base-300 bg-base-100 p-5"
            >
              <h2 class="text-sm font-semibold">{gettext("Follow us")}</h2>
              <ul class="mt-3 space-y-1">
                <li :for={{network, url} <- @social_links}>
                  <a
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="flex items-center gap-3 rounded-xl px-2 py-1.5 text-sm transition hover:bg-base-200"
                  >
                    <span class="grid size-8 place-items-center rounded-full border border-base-300 text-base-content/70">
                      <TaamolWeb.SocialIcons.social_icon network={network} class="size-4" />
                    </span>
                    {TaamolWeb.SocialIcons.name(network)}
                  </a>
                </li>
              </ul>
            </section>

            <.link
              navigate={~p"/donate"}
              class="group block rounded-3xl bg-linear-to-br from-rose-500 to-primary p-5 text-white shadow-lg shadow-primary/20 transition hover:brightness-105"
            >
              <.icon name="hero-heart-solid" class="size-6" />
              <p class="mt-3 font-semibold">{gettext("Support the community")}</p>
              <p class="mt-1 text-sm text-white/85">{gettext("Give a gift with Swish.")}</p>
              <span class="mt-3 inline-flex items-center gap-1 text-sm font-semibold">
                {gettext("Donate")}
                <.icon
                  name="hero-arrow-right-micro"
                  class="size-4 transition-transform group-hover:translate-x-0.5 rtl:rotate-180 rtl:group-hover:-translate-x-0.5"
                />
              </span>
            </.link>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
