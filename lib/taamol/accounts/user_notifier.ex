defmodule Taamol.Accounts.UserNotifier do
  import Swoosh.Email
  use Gettext, backend: TaamolWeb.Gettext

  alias Taamol.Mailer
  alias Taamol.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Taamol", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(
      user.email,
      gettext("Update email instructions"),
      gettext(
        "Hi %{email},\n\nYou can change your email by visiting the URL below:\n\n%{url}\n\nIf you didn't request this change, please ignore this.",
        email: user.email,
        url: url
      )
    )
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(
      user.email,
      gettext("Log in instructions"),
      gettext(
        "Hi %{email},\n\nYou can log into your account by visiting the URL below:\n\n%{url}\n\nIf you didn't request this email, please ignore this.",
        email: user.email,
        url: url
      )
    )
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      gettext("Confirmation instructions"),
      gettext(
        "Hi %{email},\n\nYou can confirm your account by visiting the URL below:\n\n%{url}\n\nIf you didn't create an account with us, please ignore this.",
        email: user.email,
        url: url
      )
    )
  end
end
