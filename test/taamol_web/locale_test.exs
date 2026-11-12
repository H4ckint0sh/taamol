defmodule TaamolWeb.LocaleTest do
  use TaamolWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taamol.AccountsFixtures

  test "switches language and direction for controller and connected LiveView pages", %{
    conn: conn
  } do
    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/users/register")
      |> post(~p"/locale", %{"locale" => "fa"})

    assert redirected_to(conn) == "/users/register"
    conn = recycle(conn)
    html = conn |> get(~p"/users/register") |> html_response(200)
    assert html =~ ~s(lang="fa")
    assert html =~ ~s(dir="rtl")

    {:ok, view, _} = live(conn, ~p"/users/register")
    assert has_element?(view, "#registration_form label", "ایمیل")

    view
    |> form("#registration_form", user: %{email: "invalid", name: "Test"})
    |> render_change()

    assert has_element?(view, "#registration_form", "باید شامل @ و بدون فاصله باشد")

    conn = conn |> recycle() |> post(~p"/locale", %{"locale" => "sv"})
    conn = recycle(conn)
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(lang="sv")
    assert html =~ ~s(dir="ltr")
    assert html =~ "Nyheter för vår gemenskap"
    assert {:ok, view, _} = live(conn, ~p"/users/register")
    assert has_element?(view, "#registration_form label", "E-post")
  end

  test "preserves the language when logging in and out", %{conn: conn} do
    user = user_fixture() |> set_password()
    conn = conn |> post(~p"/locale", %{"locale" => "fa"}) |> recycle()

    conn =
      post(conn, ~p"/users/log-in", %{
        "user" => %{"email" => user.email, "password" => valid_user_password()}
      })

    assert get_session(conn, :locale) == "fa"

    conn = conn |> recycle() |> delete(~p"/users/log-out")
    assert get_session(conn, :locale) == "fa"
    assert conn |> recycle() |> get(~p"/") |> html_response(200) =~ ~s(lang="fa")
  end

  test "rejects invalid locales and does not redirect to another site", %{conn: conn} do
    assert response(post(conn, ~p"/locale", %{"locale" => "invalid"}), 400)

    conn =
      conn
      |> put_req_header("referer", "https://evil.example/path")
      |> post(~p"/locale", %{"locale" => "sv"})

    assert redirected_to(conn) == "/"
  end

  test "account emails use the current language" do
    user = unconfirmed_user_fixture()

    Gettext.with_locale(TaamolWeb.Gettext, "sv", fn ->
      {:ok, email} =
        Taamol.Accounts.UserNotifier.deliver_login_instructions(user, "https://example.com/token")

      assert email.subject == "Bekräftelseinstruktioner"
      assert email.text_body =~ "https://example.com/token"
    end)
  end

  test "the language menu marks the current language", %{conn: conn} do
    conn = conn |> post(~p"/locale", %{"locale" => "sv"}) |> recycle() |> get(~p"/")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#locale-switcher button[name=locale]") |> Enum.count() == 3

    assert document
           |> LazyHTML.query(~s(#locale-switcher-option-sv[aria-current="true"]))
           |> Enum.count() ==
             1

    assert document |> LazyHTML.query("#locale-switcher-option-en[aria-current]") |> Enum.count() ==
             0
  end
end
