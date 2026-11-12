defmodule Taamol.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Taamol.Repo

  alias Taamol.Accounts.{Scope, User, UserToken, UserNotifier}

  @doc "Returns whether the scope belongs to an administrator."
  def admin?(%Scope{user: %User{role: :admin}}), do: true
  def admin?(_), do: false

  @doc "Checks a named permission for the current scope."
  def allowed?(%Scope{user: %User{role: :admin, can_view_dashboard: true}}, :view_dashboard),
    do: true

  def allowed?(_, _), do: false

  @doc """
  What the current scope may see and do in the dashboard.

    * `:use_dashboard` - any logged-in user (own overview and settings)
    * `:view_statistics` - administrators with dashboard access
    * `:manage_news`, `:manage_users`, `:manage_events`, `:manage_gallery`,
      `:manage_settings` -
      administrators
  """
  def can?(%Scope{user: %User{}}, :use_dashboard), do: true
  def can?(scope, :view_statistics), do: allowed?(scope, :view_dashboard)

  def can?(scope, action)
      when action in [
             :manage_news,
             :manage_users,
             :manage_events,
             :manage_gallery,
             :manage_settings
           ],
      do: admin?(scope)

  def can?(_scope, _action), do: false

  @doc """
  Lists users for administrators, newest first.

  Options: `:search` (name or email), `:role` (`:user`/`:admin`),
  `:limit` (default 20), `:offset`. Returns `{:ok, %{entries: [...], total: n}}`.
  """
  def list_users_page(scope, opts \\ []) do
    if fresh_admin?(scope) do
      query =
        from(u in User)
        |> filter_users_search(Keyword.get(opts, :search))
        |> filter_users_role(Keyword.get(opts, :role))

      entries =
        query
        |> order_by([u], desc: u.inserted_at, desc: u.id)
        |> limit(^Keyword.get(opts, :limit, 20))
        |> offset(^Keyword.get(opts, :offset, 0))
        |> Repo.all()

      {:ok, %{entries: entries, total: Repo.aggregate(query, :count)}}
    else
      {:error, :forbidden}
    end
  end

  defp filter_users_search(query, search) when is_binary(search) and search != "" do
    pattern = "%" <> String.replace(search, ~r/[\\%_]/, "\\\\\\0") <> "%"
    where(query, [u], ilike(u.name, ^pattern) or ilike(u.email, ^pattern))
  end

  defp filter_users_search(query, _), do: query

  defp filter_users_role(query, role) when role in [:user, :admin],
    do: where(query, [u], u.role == ^role)

  defp filter_users_role(query, _), do: query

  @doc "Gets a user for administrators."
  def get_user_for_admin(scope, id) do
    with true <- fresh_admin?(scope),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %User{} = user <- Repo.get(User, uuid) do
      {:ok, user}
    else
      false -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  @doc "A changeset for the admin user form."
  def change_user_as_admin(%User{} = user, attrs \\ %{}) do
    User.admin_changeset(user, attrs, validate_unique: false)
  end

  @doc """
  Creates an account as an administrator. The new user signs in with a
  magic link (see `deliver_login_instructions/2`).
  """
  def create_user_as_admin(scope, attrs) do
    if fresh_admin?(scope) do
      %User{} |> User.admin_changeset(attrs) |> Repo.insert()
    else
      {:error, :forbidden}
    end
  end

  @doc "Updates an account's name and email as an administrator."
  def update_user_as_admin(scope, %User{} = user, attrs) do
    if fresh_admin?(scope) do
      user |> User.admin_changeset(attrs) |> Repo.update()
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Deletes an account as an administrator. You can't delete yourself, and
  accounts that wrote articles or comments are kept (`{:error, :has_content}`).
  Returns `{:ok, {user, session_tokens}}`; disconnect the sessions afterwards.
  """
  def delete_user_as_admin(%Scope{user: %User{id: actor_id}} = scope, user_id) do
    Repo.transact(fn ->
      lock_access_changes()

      with true <- fresh_admin?(scope),
           {:ok, uuid} <- Ecto.UUID.cast(user_id),
           false <- uuid == actor_id,
           %User{} = user <- Repo.get(User, uuid) do
        tokens =
          Repo.all(from t in UserToken, where: t.user_id == ^uuid and t.context == "session")

        user
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.foreign_key_constraint(:id,
          name: :articles_creator_id_fkey,
          message: "has articles"
        )
        |> Ecto.Changeset.foreign_key_constraint(:id,
          name: :comments_creator_id_fkey,
          message: "has comments"
        )
        |> Repo.delete()
        |> case do
          {:ok, user} -> {:ok, {user, tokens}}
          {:error, _changeset} -> {:error, :has_content}
        end
      else
        true -> {:error, :cannot_delete_self}
        :error -> {:error, :not_found}
        nil -> {:error, :not_found}
        false -> {:error, :forbidden}
      end
    end)
  end

  def delete_user_as_admin(_scope, _user_id), do: {:error, :forbidden}

  @doc """
  User totals for the statistics dashboard: totals, new accounts in the last
  7 days and sign-ups per week for the last `weeks` weeks (oldest first).
  """
  def user_statistics(scope, weeks \\ 8) do
    if can?(scope, :view_statistics) do
      now = DateTime.utc_now()
      week_ago = DateTime.add(now, -7 * 86_400)
      since = DateTime.add(now, -weeks * 7 * 86_400)

      totals =
        Repo.one(
          from u in User,
            select: %{
              total: count(u.id),
              confirmed: filter(count(u.id), not is_nil(u.confirmed_at)),
              admins: filter(count(u.id), u.role == :admin),
              new_this_week: filter(count(u.id), u.inserted_at >= ^week_ago)
            }
        )

      signups =
        Repo.all(
          from u in User,
            where: u.inserted_at >= ^since,
            select: u.inserted_at
        )

      per_week =
        for i <- (weeks - 1)..0//-1 do
          from = DateTime.add(now, -(i + 1) * 7 * 86_400)
          to = DateTime.add(now, -i * 7 * 86_400)

          count =
            Enum.count(
              signups,
              &(DateTime.compare(&1, from) != :lt and DateTime.compare(&1, to) == :lt)
            )

          %{week_start: DateTime.to_date(from), count: count}
        end

      {:ok, Map.put(totals, :per_week, per_week)}
    else
      {:error, :forbidden}
    end
  end

  # re-reads the role so a demoted admin's old session can't keep acting
  defp fresh_admin?(%Scope{user: %User{id: id}}),
    do: Repo.exists?(from u in User, where: u.id == ^id and u.role == :admin)

  defp fresh_admin?(_), do: false

  @doc "Returns account totals for an administrator with dashboard access."
  def dashboard_stats(%Scope{user: %User{id: id}}) do
    user = Repo.get(User, id)

    if allowed?(Scope.for_user(user), :view_dashboard) do
      {:ok,
       Repo.one(
         from u in User,
           select: %{
             users: count(u.id),
             confirmed: filter(count(u.id), not is_nil(u.confirmed_at)),
             admins: filter(count(u.id), u.role == :admin)
           }
       )}
    else
      {:error, :forbidden}
    end
  end

  @doc "Creates the first administrator from an existing confirmed user."
  def bootstrap_admin(email) when is_binary(email) do
    Repo.transact(fn ->
      lock_access_changes()

      cond do
        Repo.exists?(from u in User, where: u.role == :admin) ->
          {:error, :admin_already_exists}

        user = Repo.get_by(User, email: email) ->
          if user.confirmed_at do
            user
            |> Ecto.Changeset.change(role: :admin, can_view_dashboard: true)
            |> Repo.update()
          else
            {:error, :user_unconfirmed}
          end

        true ->
          {:error, :user_not_found}
      end
    end)
  end

  @doc "Lists users for administrators."
  def list_users(%Scope{user: %User{id: id}}) do
    if Repo.exists?(from u in User, where: u.id == ^id and u.role == :admin) do
      {:ok, Repo.all(from u in User, order_by: [asc: u.email])}
    else
      {:error, :forbidden}
    end
  end

  @doc "Updates an account's administrator role or dashboard permission."
  def update_user_access(%Scope{user: %User{id: actor_id}}, user_id, action)
      when action in ["promote", "demote", "grant_dashboard", "revoke_dashboard"] do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id) do
      Repo.transact(fn ->
        lock_access_changes()
        actor = Repo.get(User, actor_id)
        target = Repo.get(User, user_id)

        cond do
          not admin?(Scope.for_user(actor)) ->
            {:error, :forbidden}

          is_nil(target) ->
            {:error, :not_found}

          action == "demote" and actor_id == user_id ->
            {:error, :cannot_demote_self}

          action in ["grant_dashboard", "revoke_dashboard"] and target.role != :admin ->
            {:error, :not_admin}

          true ->
            changes =
              case action do
                "promote" -> [role: :admin, can_view_dashboard: true]
                "demote" -> [role: :user, can_view_dashboard: false]
                "grant_dashboard" -> [can_view_dashboard: true]
                "revoke_dashboard" -> [can_view_dashboard: false]
              end

            with {:ok, updated} <- target |> Ecto.Changeset.change(changes) |> Repo.update() do
              tokens =
                Repo.all(
                  from t in UserToken, where: t.user_id == ^user_id and t.context == "session"
                )

              Repo.delete_all(
                from t in UserToken, where: t.user_id == ^user_id and t.context == "session"
              )

              {:ok, {updated, tokens}}
            end
        end
      end)
    else
      :error -> {:error, :not_found}
    end
  end

  defp lock_access_changes do
    Ecto.Adapters.SQL.query!(Repo, "LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE", [])
  end

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for registering a user.

  See `Taamol.Accounts.User.registration_changeset/3` for supported options.
  """
  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Taamol.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user name.

  ## Examples

      iex> change_user_name(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_name(user, attrs \\ %{}) do
    User.name_changeset(user, attrs)
  end

  @doc """
  Updates the current user's name.
  """
  def update_user_name(%Taamol.Accounts.Scope{user: user}, attrs) do
    user
    |> User.name_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Taamol.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
