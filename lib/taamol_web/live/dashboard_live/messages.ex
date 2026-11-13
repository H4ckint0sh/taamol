defmodule TaamolWeb.DashboardLive.Messages do
  @moduledoc """
  `/dashboard/messages`: messages from the contact page (administrators).
  `?filter=unread&page=2` drive the list.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.DashboardComponents

  alias Taamol.Contact

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Messages"), open: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    unread? = params["filter"] == "unread"
    page = page_param(params)

    {:ok, %{entries: messages, total: total}} =
      Contact.list_messages_page(socket.assigns.current_scope,
        unread: unread?,
        limit: @per_page,
        offset: (page - 1) * @per_page
      )

    {:noreply,
     socket
     |> assign(unread?: unread?, page: page, total: total)
     |> stream(:messages, messages, reset: true)}
  end

  defp list_path(unread?, page) do
    query =
      Enum.reject([filter: if(unread?, do: "unread"), page: page], fn {_, v} -> v in [nil, 1] end)

    ~p"/dashboard/messages?#{query}"
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    previous = socket.assigns.open
    opening? = previous != id

    socket = assign(socket, open: if(opening?, do: id))

    # opening a message marks it read; re-insert both cards so they re-render
    socket =
      case opening? && Contact.set_read(scope, id, true) do
        {:ok, message} -> stream_insert(socket, :messages, message)
        _ -> restream(socket, id)
      end

    {:noreply, if(previous && previous != id, do: restream(socket, previous), else: socket)}
  end

  def handle_event("mark-unread", %{"id" => id}, socket) do
    case Contact.set_read(socket.assigns.current_scope, id, false) do
      {:ok, message} ->
        {:noreply, socket |> assign(open: nil) |> stream_insert(:messages, message)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Contact.delete_message(socket.assigns.current_scope, id) do
      {:ok, message} ->
        {:noreply,
         socket
         |> stream_delete(:messages, message)
         |> update(:total, &(&1 - 1))
         |> put_flash(:info, gettext("Message deleted."))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("The message could not be deleted."))}
    end
  end

  defp restream(socket, id) do
    case Taamol.Repo.get(Taamol.Contact.Message, id) do
      nil -> socket
      message -> stream_insert(socket, :messages, message)
    end
  end

  defp topic_name(:feedback), do: gettext("Feedback")
  defp topic_name(:question), do: gettext("Question")
  defp topic_name(:events), do: gettext("Events and activities")
  defp topic_name(:other), do: gettext("Something else")

  defp reply_link(message) do
    "mailto:#{message.email}?" <>
      URI.encode_query(%{"subject" => "Re: " <> topic_name(message.topic)}, :rfc3986)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      active={:messages}
      title={gettext("Messages")}
    >
      <Layouts.dashboard_heading
        title={gettext("Messages")}
        subtitle={gettext("Feedback and questions sent through the contact page.")}
      />

      <.card padded={false}>
        <div class="flex gap-6 px-5 pt-4 text-sm">
          <.link
            :for={{unread?, label} <- [{false, gettext("All")}, {true, gettext("Unread")}]}
            patch={list_path(unread?, 1)}
            aria-current={if(@unread? == unread?, do: "page")}
            class="-mb-px border-b-2 border-transparent pb-3 text-base-content/60 transition-colors hover:text-base-content aria-[current=page]:border-primary aria-[current=page]:font-semibold aria-[current=page]:text-primary"
          >
            {label}
          </.link>
        </div>

        <ul
          id="messages"
          phx-update="stream"
          class="divide-y divide-base-300/70 border-t border-base-300"
        >
          <li
            id="messages-empty"
            class="hidden px-5 py-12 text-center text-sm text-base-content/55 only:block"
          >
            {gettext("No messages.")}
          </li>
          <li :for={{dom_id, message} <- @streams.messages} id={dom_id}>
            <button
              type="button"
              id={"open-#{message.id}"}
              phx-click="toggle"
              phx-value-id={message.id}
              aria-expanded={to_string(@open == message.id)}
              class={[
                "flex w-full items-start gap-3 px-5 py-4 text-start transition hover:bg-base-200/50",
                is_nil(message.read_at) && "bg-primary/[0.04]"
              ]}
            >
              <span class={[
                "mt-1.5 size-2 shrink-0 rounded-full",
                if(is_nil(message.read_at), do: "bg-primary", else: "bg-transparent")
              ]} />
              <span class="min-w-0 flex-1">
                <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
                  <span dir="auto" class={["text-sm", is_nil(message.read_at) && "font-semibold"]}>
                    {message.name}
                  </span>
                  <span class="text-xs text-base-content/50">{message.email}</span>
                  <span class="rounded-md bg-base-200 px-1.5 py-0.5 text-[11px] font-medium text-base-content/70">
                    {topic_name(message.topic)}
                  </span>
                </span>
                <span
                  dir="auto"
                  class={[
                    "mt-1 block text-sm text-base-content/70",
                    @open != message.id && "line-clamp-1"
                  ]}
                >
                  <%= if @open == message.id do %>
                    <span class="whitespace-pre-line" phx-no-format>{message.message}</span>
                  <% else %>
                    {message.message}
                  <% end %>
                </span>
              </span>
              <time class="shrink-0 text-xs text-base-content/50">
                {TaamolWeb.NewsComponents.relative_time(message.inserted_at)}
              </time>
            </button>

            <div :if={@open == message.id} class="flex flex-wrap items-center gap-2 px-5 pb-4 ps-10">
              <a
                href={reply_link(message)}
                id={"reply-#{message.id}"}
                class="inline-flex items-center gap-1.5 rounded-full bg-primary px-4 py-1.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
              >
                <.icon name="hero-envelope" class="size-4" />{gettext("Reply by email")}
              </a>
              <button
                type="button"
                id={"unread-#{message.id}"}
                phx-click="mark-unread"
                phx-value-id={message.id}
                class="rounded-full px-3 py-1.5 text-sm transition hover:bg-base-200"
              >
                {gettext("Mark as unread")}
              </button>
              <button
                type="button"
                id={"delete-#{message.id}"}
                phx-click="delete"
                phx-value-id={message.id}
                data-confirm={gettext("Delete this message?")}
                class="ms-auto rounded-full px-3 py-1.5 text-sm text-error transition hover:bg-error/10"
              >
                {gettext("Delete")}
              </button>
            </div>
          </li>
        </ul>

        <.pagination
          page={@page}
          per_page={20}
          total={@total}
          path={fn page -> list_path(@unread?, page) end}
        />
      </.card>
    </Layouts.dashboard>
    """
  end
end
