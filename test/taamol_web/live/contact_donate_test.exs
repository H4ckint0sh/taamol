defmodule TaamolWeb.ContactDonateTest do
  # not async: site settings (Swish number) are cached globally
  use TaamolWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures

  alias Taamol.{Contact, Repo, Settings}
  alias Taamol.Accounts.Scope

  setup do
    Settings.reset_cache()
    on_exit(&Settings.reset_cache/0)
  end

  defp admin_fixture, do: user_fixture() |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

  defp set_swish(number) do
    {:ok, _} =
      Settings.update(Scope.for_user(admin_fixture()), %{
        "swish_number" => number,
        "swish_message" => "Gift to Taamol"
      })
  end

  describe "contact page" do
    test "sends a message to the inbox and emails the admins", %{conn: conn} do
      admin = admin_fixture()
      {:ok, view, _html} = live(conn, ~p"/contact")
      assert has_element?(view, "#contact-form .hero-envelope")
      assert has_element?(view, "#contact-form textarea[data-field-input]")

      view
      |> form("#contact-form",
        message: %{
          name: "Maryam",
          email: "maryam@example.com",
          topic: "question",
          message: "When does the weekend school start?"
        }
      )
      |> render_submit()

      assert has_element?(view, "#contact-sent")
      assert {:ok, %{entries: [message]}} = Contact.list_messages_page(Scope.for_user(admin))
      assert message.topic == :question

      assert_received {:email,
                       %{to: [{"", admin_email}], reply_to: {"Maryam", "maryam@example.com"}}}

      assert admin_email == admin.email
    end

    test "shows the contact details that are filled in", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")
      refute has_element?(view, "#contact-phone")
      refute has_element?(view, "#contact-address")
      refute has_element?(view, "#contact-social")

      {:ok, _} =
        Settings.update(Scope.for_user(admin_fixture()), %{
          "contact_address" => "Example street 12\nVäxjö",
          "contact_phone" => "070 123 45 67",
          "contact_email" => "info@example.com",
          "opening_hours" => "Fridays 18–23",
          "instagram_url" => "https://instagram.com/taamol"
        })

      {:ok, view, _html} = live(build_conn(), ~p"/contact")

      for {id, icon} <- [
            {"contact-address", "hero-map-pin"},
            {"contact-phone", "hero-phone"},
            {"contact-email", "hero-envelope"},
            {"contact-opening_hours", "hero-clock"},
            {"contact-social", "hero-user-group"}
          ] do
        assert has_element?(view, "##{id} .#{icon}")
        assert has_element?(view, "##{id} h2")
        assert has_element?(view, "##{id} p.text-base-content\\/60")
      end

      assert has_element?(view, "#contact-address", "Example street 12")
      assert has_element?(view, "#contact-phone a[href='tel:0701234567']")
      assert has_element?(view, "#contact-email a[href='mailto:info@example.com']")
      assert has_element?(view, "#contact-opening_hours", "Fridays 18–23")
      assert has_element?(view, "#contact-social a[href='https://instagram.com/taamol']")
    end

    test "is pre-filled for logged-in users", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/contact")

      assert has_element?(
               view,
               "#contact-form input[name='message[email]'][value='#{user.email}']"
             )
    end

    test "validates, ignores spam and limits repeated messages" do
      attrs = %{
        "name" => "A",
        "email" => "a@example.com",
        "topic" => "other",
        "message" => "Hello there, a question"
      }

      assert {:error, %Ecto.Changeset{}} =
               Contact.submit_message(nil, %{attrs | "message" => "short"})

      assert {:ok, :ignored} = Contact.submit_message(nil, attrs, "http://spam.example")

      for _ <- 1..3, do: assert({:ok, _} = Contact.submit_message(nil, attrs))
      assert {:error, :rate_limited} = Contact.submit_message(nil, attrs)
    end
  end

  describe "inbox" do
    test "inboxes and dashboard badges update across sessions", %{conn: conn} do
      admin = admin_fixture()
      admin_conn = log_in_user(conn, admin)
      {:ok, first, _} = live(admin_conn, ~p"/dashboard/messages")
      {:ok, second, _} = live(admin_conn, ~p"/dashboard/messages?filter=unread")
      {:ok, overview, _} = live(admin_conn, ~p"/dashboard")
      {:ok, contact, _} = live(build_conn(), ~p"/contact")

      contact
      |> form("#contact-form",
        message: %{
          name: "Live Sender",
          email: "live@example.com",
          topic: "question",
          message: "Can you help me with an upcoming event?"
        }
      )
      |> render_submit()

      assert has_element?(contact, "#contact-sent")
      assert has_element?(first, "#messages", "Live Sender")
      assert has_element?(second, "#messages", "Live Sender")
      assert has_element?(overview, "#unread-messages", "1")

      assert {:ok, %{entries: [message]}} =
               Contact.list_messages_page(Scope.for_user(admin))

      first |> element("#open-#{message.id}") |> render_click()
      refute has_element?(second, "#open-#{message.id}")
      refute has_element?(overview, "#unread-messages")
      refute has_element?(first, "#unread-messages")

      first |> element("#unread-#{message.id}") |> render_click()
      assert has_element?(second, "#open-#{message.id}")
      assert has_element?(overview, "#unread-messages", "1")

      first |> element("#open-#{message.id}") |> render_click()
      first |> element("#delete-#{message.id}") |> render_click()
      refute has_element?(second, "#open-#{message.id}")
      refute has_element?(overview, "#unread-messages")
    end

    test "only current administrators can subscribe to inbox updates" do
      admin_scope = Scope.for_user(admin_fixture())
      member_scope = Scope.for_user(user_fixture())
      assert {:error, :forbidden} = Contact.subscribe_messages(member_scope)
      assert :ok = Contact.subscribe_messages(admin_scope)

      Repo.update!(Ecto.Changeset.change(admin_scope.user, role: :user))
      assert {:error, :forbidden} = Contact.subscribe_messages(admin_scope)
      assert Contact.unread_count(admin_scope) == 0
    end

    test "new messages refresh a full inbox without exceeding its page size", %{conn: conn} do
      for i <- 1..20 do
        %Taamol.Contact.Message{}
        |> Taamol.Contact.Message.changeset(%{
          "name" => "Sender #{i}",
          "email" => "sender#{i}@example.com",
          "topic" => "other",
          "message" => "A message about an upcoming event."
        })
        |> Repo.insert!()
      end

      admin = admin_fixture()
      {:ok, view, _} = conn |> log_in_user(admin) |> live(~p"/dashboard/messages")

      assert {:ok, _message} =
               Contact.submit_message(nil, %{
                 "name" => "Another sender",
                 "email" => "another@example.com",
                 "topic" => "question",
                 "message" => "A question about the community."
               })

      assert has_element?(view, "#unread-messages", "21")
      assert has_element?(view, "#messages li:nth-child(21):not(#messages-empty)")
      refute has_element?(view, "#messages li:nth-child(22)")
      assert has_element?(view, "nav[aria-label='Pages'] a", "2")
    end

    test "live inbox updates preserve the page size and correct an empty last page", %{conn: conn} do
      for i <- 1..21 do
        %Taamol.Contact.Message{}
        |> Taamol.Contact.Message.changeset(%{
          "name" => "Sender #{i}",
          "email" => "sender#{i}@example.com",
          "topic" => "other",
          "message" => "A message about an upcoming event."
        })
        |> Repo.insert!()
      end

      admin = admin_fixture()
      scope = Scope.for_user(admin)
      {:ok, view, _} = conn |> log_in_user(admin) |> live(~p"/dashboard/messages?page=2")
      assert {:ok, %{entries: [last]}} = Contact.list_messages_page(scope, limit: 20, offset: 20)
      assert has_element?(view, "#open-#{last.id}")

      assert {:ok, _} = Contact.delete_message(scope, last.id)
      assert_patch(view, ~p"/dashboard/messages")
      assert has_element?(view, "#messages li:nth-child(21):not(#messages-empty)")
      refute has_element?(view, "#messages li:nth-child(22)")
    end

    test "admins read, mark unread and delete messages", %{conn: conn} do
      {:ok, message} =
        Contact.submit_message(nil, %{
          "name" => "Ali",
          "email" => "ali@example.com",
          "topic" => "feedback",
          "message" => "Great new website!"
        })

      {:ok, view, _html} = conn |> log_in_user(admin_fixture()) |> live(~p"/dashboard/messages")
      assert has_element?(view, "#unread-messages", "1")
      assert has_element?(view, "#message-filters.rounded-full #messages-all[aria-current=page]")
      view |> element("#messages-unread") |> render_click()
      assert has_element?(view, "#messages-unread[aria-current=page]")
      assert has_element?(view, "#open-#{message.id}")

      view |> element("#open-#{message.id}") |> render_click()
      assert Repo.reload!(message).read_at
      assert has_element?(view, "#reply-#{message.id}[href^='mailto:ali@example.com']")

      view |> element("#unread-#{message.id}") |> render_click()
      refute Repo.reload!(message).read_at

      # marking unread closes it; open it again to delete
      view |> element("#open-#{message.id}") |> render_click()
      view |> element("#delete-#{message.id}") |> render_click()
      refute Repo.reload(message)
    end

    test "regular users can't open the inbox", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard/messages")
      assert {:error, :forbidden} = Contact.list_messages_page(Scope.for_user(user_fixture()))
    end
  end

  describe "donations" do
    test "are hidden until a Swish number is set", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/donate")
      assert has_element?(view, "#donate-unavailable")
      {:ok, home, _html} = live(conn, ~p"/")
      refute has_element?(home, "#header-donate")
    end

    test "show the Swish link and QR code for the chosen amount", %{conn: conn} do
      set_swish("123 118 11 89")
      {:ok, view, _html} = live(conn, ~p"/donate")

      assert has_element?(view, "#swish-number", "123 118 11 89")
      assert has_element?(view, "#custom-amount-input-stepper[phx-hook=NumberStepper]")
      assert has_element?(view, "#donate-amount-options #amount-200[aria-pressed=true]")
      assert has_element?(view, "#donate-amount-options-indicator[phx-hook=SegmentedIndicator]")

      for {id, icon} <- [
            {"donate-number", "hero-device-phone-mobile"},
            {"donate-message", "hero-chat-bubble-bottom-center-text"},
            {"donate-contact", "hero-envelope"}
          ] do
        assert has_element?(view, "##{id} .#{icon}")
        assert has_element?(view, "##{id} h2")
        assert has_element?(view, "##{id} p.text-base-content\\/60")
      end

      assert has_element?(view, "#donate-message", "Gift to Taamol")
      assert has_element?(view, "#donate-contact a[href='/contact']")
      view |> element("#amount-500") |> render_click()
      assert has_element?(view, "#amount-500[aria-pressed=true]")
      assert has_element?(view, "#swish-qr[src='/donate/qr.png?amount=500']")
      assert has_element?(view, ~s(#open-swish[href^="swish://payment?data="]))

      [href] =
        view
        |> element("#open-swish")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("href")

      data =
        href
        |> String.replace_prefix("swish://payment?data=", "")
        |> URI.decode_www_form()
        |> Jason.decode!()

      assert %{"payee" => %{"value" => "1231181189"}, "amount" => %{"value" => 500}} = data

      view |> form("#custom-amount", custom: %{amount: "250"}) |> render_change()
      assert has_element?(view, "#swish-qr[src='/donate/qr.png?amount=250']")
      refute has_element?(view, "#donate-amount-options [aria-pressed=true]")

      {:ok, home, _html} = live(conn, ~p"/")
      assert has_element?(home, "#prayer-times-trigger.h-8")
      assert has_element?(home, "#header-donate.h-8.ring-inset")
      assert has_element?(home, "#header-locale-button.h-8.ring-inset")
      assert has_element?(home, "#header-theme.h-8.ring-inset")
      assert has_element?(home, "#main-nav-indicator.h-8.ring-inset")
      assert has_element?(home, "#main-nav a[data-nav-item].h-8")

      {:ok, signed_in, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/")
      assert has_element?(signed_in, "#user-menu-trigger.h-8")
    end

    test "the QR endpoint returns Swish's image", %{conn: conn} do
      set_swish("1231181189")

      Req.Test.stub(Taamol.Donations, fn stub_conn ->
        {:ok, body, stub_conn} = Plug.Conn.read_body(stub_conn)

        assert %{"payee" => %{"value" => "1231181189"}, "amount" => %{"value" => 300}} =
                 Jason.decode!(body)

        stub_conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, "PNGDATA")
      end)

      conn = get(conn, ~p"/donate/qr.png?amount=300")
      assert response(conn, 200) == "PNGDATA"
      assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
      assert response(get(build_conn(), ~p"/donate/qr.png?amount=-1"), 400)
    end

    test "the Swish number must have 10 digits" do
      scope = Scope.for_user(admin_fixture())
      assert {:error, changeset} = Settings.update(scope, %{"swish_number" => "12345"})
      assert %{swish_number: [_]} = Taamol.DataCase.errors_on(changeset)
    end
  end
end
