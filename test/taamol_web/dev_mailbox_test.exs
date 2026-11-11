defmodule TaamolWeb.DevMailboxTest do
  use TaamolWeb.ConnCase, async: true

  test "allows unauthenticated localhost access", %{conn: conn} do
    conn = %{conn | host: "localhost", remote_ip: {127, 0, 0, 1}}
    assert html_response(get(conn, "/dev/mailbox"), 200)
  end

  test "rejects remote clients and untrusted hostnames", %{conn: conn} do
    remote = %{conn | host: "localhost", remote_ip: {192, 0, 2, 1}}
    assert response(get(remote, "/dev/mailbox"), 403)

    untrusted_host = %{conn | host: "example.com", remote_ip: {127, 0, 0, 1}}
    assert response(get(untrusted_host, "/dev/mailbox"), 403)
  end
end
