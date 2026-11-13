defmodule Taamol.Contact do
  @moduledoc """
  Messages sent through the contact page, and the administrators' inbox.
  """

  import Ecto.Query

  alias Taamol.Accounts
  alias Taamol.Accounts.{Scope, User}
  alias Taamol.Contact.{Message, Notifier}
  alias Taamol.Repo

  @per_hour 3
  @messages_topic "contact:messages"

  @doc "Subscribes an administrator to inbox changes."
  def subscribe_messages(scope) do
    if Accounts.can?(scope, :manage_messages) and admin?(scope),
      do: Phoenix.PubSub.subscribe(Taamol.PubSub, @messages_topic),
      else: {:error, :forbidden}
  end

  defp broadcast_messages_changed do
    Phoenix.PubSub.broadcast_from(
      Taamol.PubSub,
      self(),
      @messages_topic,
      :contact_messages_changed
    )
  end

  @doc "A changeset for the contact form."
  def change_message(%Message{} = message \\ %Message{}, attrs \\ %{}),
    do: Message.changeset(message, attrs)

  @doc """
  Saves a message from the contact page and emails the administrators.

  `honeypot` is a hidden form field people never fill in; when it has a value
  the message is treated as spam and silently dropped (`{:ok, :ignored}`).
  At most #{@per_hour} messages per email address are accepted per hour.
  """
  def submit_message(scope, attrs, honeypot \\ "") do
    changeset =
      %Message{user_id: user_id(scope)}
      |> Message.changeset(attrs)

    cond do
      honeypot not in [nil, ""] ->
        {:ok, :ignored}

      not changeset.valid? ->
        {:error, %{changeset | action: :insert}}

      too_many?(Ecto.Changeset.get_field(changeset, :email)) ->
        {:error, :rate_limited}

      true ->
        with {:ok, message} <- Repo.insert(changeset) do
          :ok = broadcast_messages_changed()
          Notifier.deliver_new_message(admin_emails(), message)
          {:ok, message}
        end
    end
  end

  defp user_id(%Scope{user: %User{id: id}}), do: id
  defp user_id(_), do: nil

  defp too_many?(email) do
    hour_ago = DateTime.add(DateTime.utc_now(), -3600)

    Repo.aggregate(
      from(m in Message,
        where:
          fragment("lower(?)", m.email) == ^String.downcase(email) and m.inserted_at > ^hour_ago
      ),
      :count
    ) >= @per_hour
  end

  defp admin_emails, do: Repo.all(from u in User, where: u.role == :admin, select: u.email)

  ## Inbox (administrators)

  @doc """
  Lists messages, newest first (`:unread` true for unread only, `:limit`,
  `:offset`). Returns `{:ok, %{entries:, total:}}`.
  """
  def list_messages_page(scope, opts \\ []) do
    if admin?(scope) do
      query =
        if Keyword.get(opts, :unread, false),
          do: from(m in Message, where: is_nil(m.read_at)),
          else: from(m in Message)

      entries =
        query
        |> order_by([m], desc: m.inserted_at, desc: m.id)
        |> limit(^Keyword.get(opts, :limit, 20))
        |> offset(^Keyword.get(opts, :offset, 0))
        |> Repo.all()

      {:ok, %{entries: entries, total: Repo.aggregate(query, :count)}}
    else
      {:error, :forbidden}
    end
  end

  @doc "Number of unread messages (0 for non-administrators)."
  def unread_count(scope) do
    if Accounts.can?(scope, :manage_messages) and admin?(scope),
      do: Repo.aggregate(from(m in Message, where: is_nil(m.read_at)), :count),
      else: 0
  end

  @doc "Marks a message read or unread."
  def set_read(scope, id, read?) do
    with true <- admin?(scope),
         %Message{} = message <- get(id) do
      with {:ok, message} <-
             message
             |> Ecto.Changeset.change(read_at: if(read?, do: DateTime.utc_now(:second)))
             |> Repo.update() do
        :ok = broadcast_messages_changed()
        {:ok, message}
      end
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  @doc "Deletes a message."
  def delete_message(scope, id) do
    with true <- admin?(scope),
         %Message{} = message <- get(id) do
      with {:ok, message} <- Repo.delete(message) do
        :ok = broadcast_messages_changed()
        {:ok, message}
      end
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  defp get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Message, uuid)
      :error -> nil
    end
  end

  # re-reads the role so a demoted admin's old session can't read the inbox
  defp admin?(%Scope{user: %User{id: id}}),
    do: Repo.exists?(from u in User, where: u.id == ^id and u.role == :admin)

  defp admin?(_), do: false
end
