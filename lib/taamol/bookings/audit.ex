defmodule Taamol.Bookings.Audit do
  @moduledoc """
  Append-only booking transition history. Call `record!/4` inside the same
  transaction as the booking change; a failure rolls the entire change back.

  Details are limited to booking time fields. Values must be naive datetimes
  or ISO 8601 strings; messages, contact information and notes are never stored.
  """
  import Ecto.Query

  alias Taamol.Accounts.{Scope, User}
  alias Taamol.Bookings.{AuditEvent, Booking}
  alias Taamol.Repo

  @actions ~w(requested confirmed declined proposed proposal_accepted proposal_declined cancelled)
  @time_fields [
    :starts_at,
    :ends_at,
    :proposed_starts_at,
    :proposed_ends_at,
    :previous_starts_at,
    :previous_ends_at,
    :old_starts_at,
    :old_ends_at,
    :new_starts_at,
    :new_ends_at
  ]

  @doc "Records a transition and returns its event. Accepts action strings or atoms."
  def record!(%Booking{id: booking_id}, scope, action, details \\ %{}) when is_map(details) do
    action = if is_atom(action), do: Atom.to_string(action), else: action
    unless action in @actions, do: raise(ArgumentError, "unknown booking audit action")

    actor =
      case scope do
        %Scope{user: %User{id: id}} when not is_nil(id) -> Repo.get!(User, id)
        nil -> nil
        _ -> raise ArgumentError, "invalid booking audit actor"
      end

    %AuditEvent{
      booking_id: booking_id,
      actor_id: actor && actor.id,
      actor_name: actor && (actor.name || actor.email),
      actor_email: actor && actor.email,
      action: action,
      details: time_details(details),
      inserted_at: DateTime.utc_now()
    }
    |> Repo.insert!()
  end

  @doc "Lists events newest first, only for a currently authorized administrator."
  def list_for_booking(%Scope{user: %User{id: id}}, %Booking{id: booking_id})
      when not is_nil(id) and not is_nil(booking_id) do
    case Repo.get(User, id) do
      %User{role: :admin} ->
        {:ok,
         Repo.all(
           from e in AuditEvent,
             where: e.booking_id == ^booking_id,
             order_by: [desc: e.inserted_at, desc: e.id]
         )}

      _ ->
        {:error, :forbidden}
    end
  end

  def list_for_booking(_, _), do: {:error, :forbidden}

  defp time_details(details) do
    Enum.reduce(@time_fields, %{}, fn field, acc ->
      key = Atom.to_string(field)
      value = Map.get(details, key) || Map.get(details, field)

      case value do
        %NaiveDateTime{} = datetime ->
          Map.put(acc, key, NaiveDateTime.to_iso8601(datetime))

        value when is_binary(value) ->
          case NaiveDateTime.from_iso8601(value) do
            {:ok, datetime} -> Map.put(acc, key, NaiveDateTime.to_iso8601(datetime))
            _ -> raise ArgumentError, "invalid booking audit time"
          end

        nil ->
          acc

        _ ->
          raise ArgumentError, "invalid booking audit time"
      end
    end)
  end
end
