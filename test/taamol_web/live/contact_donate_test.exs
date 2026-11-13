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

      {:ok, home, _html} = live(conn, ~p"/")
      assert has_element?(home, "#header-donate")
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
