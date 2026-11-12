defmodule TaamolWeb.Uploads do
  @moduledoc """
  Stores images uploaded from the dashboard under `priv/static/uploads`
  (served at `/uploads/...`).

  This is local disk storage: fine for development and a single server, but
  files are lost when the server is rebuilt. Use persistent storage (a mounted
  volume or S3-compatible object storage) in production.
  """

  @extensions ~w(.jpg .jpeg .png .webp .gif)
  @max_size 8_000_000

  @doc "Upload options for `allow_upload/3` (images up to 8 MB)."
  def image_options(extra \\ []) do
    Keyword.merge([accept: @extensions, max_entries: 1, max_file_size: @max_size], extra)
  end

  @doc """
  Copies an uploaded temp file into the uploads folder and returns its public
  path, e.g. `"/uploads/2026/11/1f3c…a9.jpg"`. The file name is random, so
  user-supplied names never reach the file system.
  """
  def store!(tmp_path, client_name) do
    ext = client_name |> Path.extname() |> String.downcase()
    ext = if ext in @extensions, do: ext, else: ".jpg"
    today = Date.utc_today()

    folder =
      Path.join([to_string(today.year), String.pad_leading(to_string(today.month), 2, "0")])

    name = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false) <> ext

    dest_dir = Path.join(root(), folder)
    File.mkdir_p!(dest_dir)
    File.cp!(tmp_path, Path.join(dest_dir, name))

    "/uploads/#{folder}/#{name}"
  end

  @doc """
  Deletes a previously stored upload (`"/uploads/…"`). Other URLs and
  paths that would leave the uploads folder are ignored.
  """
  def delete("/uploads/" <> relative) do
    root = Path.expand(root())
    path = Path.expand(relative, root)

    if String.starts_with?(path, root <> "/") do
      _ = File.rm(path)
    end

    :ok
  end

  def delete(_url), do: :ok

  defp root do
    Application.get_env(:taamol, :uploads_dir) ||
      Path.join(:code.priv_dir(:taamol), "static/uploads")
  end
end
