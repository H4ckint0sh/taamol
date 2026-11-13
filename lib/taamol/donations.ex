defmodule Taamol.Donations do
  @moduledoc """
  Donations with Swish, using Swish's "prefilled" payments: the payer's Swish
  app opens with our number, an amount and a message filled in. No Swish for
  business agreement or certificates are needed (those are only for payment
  requests created by the site itself).

    * On phones: `app_link/2` opens the Swish app (`swish://payment?data=…`).
    * On computers: `qr_png/2` returns a QR code to scan with the Swish app,
      made by Swish's QR code generator and cached in memory.
  """

  @qr_endpoint "https://mpc.getswish.net/qrg-swish/api/v1/prefilled"
  @cache :taamol_swish_qr

  @doc "Creates the in-memory QR cache (called once at application start)."
  def init_cache do
    if :ets.whereis(@cache) == :undefined do
      :ets.new(@cache, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  @doc ~S|Formats a Swish number for display: "1231181189" -> "123 118 11 89".|
  def format_number(<<a::binary-3, b::binary-3, c::binary-2, d::binary-2>>),
    do: "#{a} #{b} #{c} #{d}"

  def format_number(number), do: number

  @doc """
  Link that opens the Swish app with the payment filled in. The payer can
  still change the amount and message; the number is locked.
  """
  def app_link(%{number: number, message: message}, amount) do
    data =
      %{
        version: 1,
        payee: %{value: number, editable: false},
        amount: %{value: amount, editable: true},
        message: %{value: message, editable: true}
      }
      |> Jason.encode!()

    "swish://payment?data=" <> URI.encode_www_form(data)
  end

  @doc """
  A PNG QR code for the payment, from Swish's QR generator. Results are
  cached per number, amount and message. Returns `{:ok, png}` or `{:error, reason}`.
  """
  def qr_png(%{number: number, message: message}, amount) do
    key = {number, amount, message}

    case cache_get(key) do
      {:ok, png} ->
        {:ok, png}

      :miss ->
        with {:ok, png} <- fetch_qr(number, amount, message) do
          cache_put(key, png)
          {:ok, png}
        end
    end
  end

  # The cache table is created at application start. If it is missing (e.g. a
  # dev server started before this code existed) QR codes are simply fetched
  # from Swish every time.
  defp cache_get(key) do
    with ref when ref != :undefined <- :ets.whereis(@cache),
         [{^key, png}] <- :ets.lookup(@cache, key) do
      {:ok, png}
    else
      _ -> :miss
    end
  end

  defp cache_put(key, png) do
    if :ets.whereis(@cache) != :undefined, do: :ets.insert(@cache, {key, png})
    :ok
  end

  defp fetch_qr(number, amount, message) do
    body = %{
      format: "png",
      size: 300,
      border: 1,
      transparent: true,
      payee: %{value: number, editable: false},
      amount: %{value: amount, editable: true},
      message: %{value: message, editable: true}
    }

    options =
      Keyword.merge(
        [json: body, receive_timeout: 10_000, retry: false],
        # tests stub Swish (see config/test.exs)
        Application.get_env(:taamol, :swish_req_options, [])
      )

    case Req.post(@qr_endpoint, options) do
      {:ok, %Req.Response{status: 200, body: png}} when is_binary(png) -> {:ok, png}
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
