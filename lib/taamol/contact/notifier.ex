defmodule Taamol.Contact.Notifier do
  @moduledoc "Emails administrators when someone writes through the contact page."

  import Swoosh.Email

  alias Taamol.Mailer

  def deliver_new_message([], _message), do: :ok

  def deliver_new_message(admin_emails, message) do
    new()
    |> to(admin_emails)
    |> reply_to({message.name, message.email})
    |> from({"Taamol", "contact@example.com"})
    |> subject("New message (#{message.topic}) from #{message.name}")
    |> text_body("""
    #{message.name} <#{message.email}> wrote (#{message.topic}):

    #{message.message}

    Read and answer it in the dashboard under Messages.
    """)
    |> Mailer.deliver()

    :ok
  end
end
