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

  test "the language switch offers the other language", %{conn: conn} do
    conn = conn |> post(~p"/locale", %{"locale" => "sv"}) |> recycle() |> get(~p"/")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    # on a Swedish page the header button switches to Persian
    assert document
           |> LazyHTML.query(~s(#header-locale-button[name="locale"][value="fa"]))
           |> Enum.count() == 1
  end

  test "English is no longer offered" do
    conn = post(build_conn(), ~p"/locale", %{"locale" => "en"})
    assert response(conn, 400)
  end

  test "first visits follow the browser's language, Persian otherwise" do
    sv =
      build_conn() |> put_req_header("accept-language", "sv-SE,sv;q=0.9,en;q=0.8") |> get(~p"/")

    assert html_response(sv, 200) =~ ~s(lang="sv")
    assert get_session(sv, :locale) == "sv"

    fa = build_conn() |> put_req_header("accept-language", "fa-IR,fa;q=0.9") |> get(~p"/")
    assert html_response(fa, 200) =~ ~s(lang="fa")

    other = build_conn() |> put_req_header("accept-language", "de-DE,de;q=0.9") |> get(~p"/")
    # the test config uses the English source strings as the default
    assert get_session(other, :locale) == TaamolWeb.Locale.default()
  end
end
