defmodule TaamolWeb.DonationQrController do
  @moduledoc """
  `GET /donate/qr.png?amount=200`: the Swish QR code for a donation, made by
  Swish's QR generator (see `Taamol.Donations`) and cached.
  """
  use TaamolWeb, :controller

  alias Taamol.{Donations, Settings}

  def show(conn, params) do
    with %{} = swish <- Settings.swish(),
         {:ok, amount} <- parse_amount(params["amount"]),
         {:ok, png} <- Donations.qr_png(swish, amount) do
      conn
      |> put_resp_content_type("image/png")
      |> put_resp_header("cache-control", "public, max-age=86400")
      |> send_resp(200, png)
    else
      nil -> send_resp(conn, 404, "Donations are not set up")
      :error -> send_resp(conn, 400, "Invalid amount")
      {:error, _reason} -> send_resp(conn, 502, "Swish QR code unavailable")
    end
  end

  defp parse_amount(value) when is_binary(value) do
    case Integer.parse(value) do
      {amount, ""} when amount in 1..100_000 -> {:ok, amount}
      _ -> :error
    end
  end

  defp parse_amount(_), do: :error
end
