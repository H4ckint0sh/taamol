defmodule TaamolWeb.DashboardLive.Gallery do
  @moduledoc """
  `/dashboard/gallery`: upload photos (up to 20 at a time), edit captions and
  delete photos (administrators).
  """
  use TaamolWeb, :live_view

  alias Taamol.Gallery
  alias TaamolWeb.Uploads

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @page_size 30

  @impl true
  def mount(_params, _session, socket) do
    images = Gallery.list_images(limit: @page_size)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Gallery"),
       total: Gallery.count_images(),
       loaded: length(images),
       upload_form: to_form(%{})
     )
     |> stream(:images, images)
     |> allow_upload(:photos, Uploads.image_options(max_entries: 20))}
  end

  @impl true
  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  def handle_event("upload", _params, socket) do
    scope = socket.assigns.current_scope

    created =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        url = Uploads.store!(path, entry.client_name)

        case Gallery.create_image(scope, url) do
          {:ok, image} ->
            {:ok, image}

          {:error, _} ->
            Uploads.delete(url)
            {:ok, nil}
        end
      end)
      |> Enum.reject(&is_nil/1)

    socket =
      Enum.reduce(created, socket, fn image, acc -> stream_insert(acc, :images, image, at: 0) end)

    {:noreply,
     socket
     |> update(:total, &(&1 + length(created)))
     |> update(:loaded, &(&1 + length(created)))
     |> put_flash(
       :info,
       ngettext("%{count} photo added.", "%{count} photos added.", length(created))
     )}
  end

  def handle_event("caption", %{"image_id" => id, "caption" => caption}, socket) do
    with %{} = image <- Gallery.get_image(id),
         {:ok, image} <-
           Gallery.update_image(socket.assigns.current_scope, image, %{caption: caption}) do
      {:noreply,
       socket |> stream_insert(:images, image) |> put_flash(:info, gettext("Caption saved."))}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("The caption could not be saved."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %{} = image <- Gallery.get_image(id),
         {:ok, image} <- Gallery.delete_image(socket.assigns.current_scope, image) do
      Uploads.delete(image.image_url)

      {:noreply,
       socket
       |> stream_delete(:images, image)
       |> update(:total, &(&1 - 1))
       |> update(:loaded, &(&1 - 1))
       |> put_flash(:info, gettext("Photo deleted."))}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("The photo could not be deleted."))}
    end
  end

  def handle_event("load-more", _params, socket) do
    images = Gallery.list_images(limit: @page_size, offset: socket.assigns.loaded)

    {:noreply,
     socket
     |> update(:loaded, &(&1 + length(images)))
     |> stream(:images, images)}
  end

  defp upload_error(:too_large), do: gettext("The image is too large (max 8 MB).")
  defp upload_error(:not_accepted), do: gettext("Use a JPG, PNG, WebP or GIF image.")
  defp upload_error(:too_many_files), do: gettext("You can upload up to 20 photos at a time.")
  defp upload_error(_), do: gettext("The image could not be uploaded.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      unread_messages={@unread_messages}
      active={:gallery}
      title={gettext("Gallery")}
    >
      <Layouts.dashboard_heading
        title={gettext("Gallery")}
        subtitle={ngettext("%{count} photo", "%{count} photos", @total)}
      >
        <:actions>
          <.link
            navigate={~p"/gallery"}
            class="rounded-xl border border-base-300 bg-base-100 px-4 py-2 text-sm font-medium transition hover:bg-base-200"
          >
            {gettext("View gallery")}
          </.link>
        </:actions>
      </Layouts.dashboard_heading>

      <.form
        for={@upload_form}
        id="gallery-upload"
        phx-change="validate-upload"
        phx-submit="upload"
        class="rounded-2xl border border-base-300 bg-base-100 p-5"
      >
        <label
          for={@uploads.photos.ref}
          phx-drop-target={@uploads.photos.ref}
          class="flex cursor-pointer flex-col items-center gap-2 rounded-xl border-2 border-dashed border-base-300 px-4 py-10 text-center text-sm text-base-content/60 transition hover:border-primary/50 hover:bg-base-200/50"
        >
          <.icon name="hero-cloud-arrow-up" class="size-9 text-base-content/40" />
          <span class="font-medium text-base-content/80">
            {gettext("Drop photos here or click to choose")}
          </span>
          <span class="text-xs text-base-content/45">
            {gettext("Up to 20 photos at a time. JPG, PNG, WebP or GIF, up to 8 MB each.")}
          </span>
        </label>
        <.live_file_input upload={@uploads.photos} class="sr-only" />

        <p :for={err <- upload_errors(@uploads.photos)} class="mt-3 text-sm text-error">
          {upload_error(err)}
        </p>

        <div :if={@uploads.photos.entries != []} class="mt-4">
          <ul class="grid grid-cols-3 gap-3 sm:grid-cols-5 lg:grid-cols-8">
            <li :for={entry <- @uploads.photos.entries} class="relative">
              <.live_img_preview entry={entry} class="aspect-square w-full rounded-lg object-cover" />
              <div class="absolute inset-x-1 bottom-1 h-1 overflow-hidden rounded-full bg-black/30">
                <div class="h-full bg-primary" style={"width: #{entry.progress}%"} />
              </div>
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                aria-label={gettext("Remove")}
                class="absolute end-1 top-1 grid size-6 place-items-center rounded-full bg-base-100/90 shadow"
              >
                <.icon name="hero-x-mark-micro" class="size-4" />
              </button>
              <p
                :for={err <- upload_errors(@uploads.photos, entry)}
                class="mt-1 text-[11px] text-error"
              >
                {upload_error(err)}
              </p>
            </li>
          </ul>
          <div class="mt-4 flex justify-end">
            <button
              type="submit"
              id="upload-photos"
              phx-disable-with={gettext("Uploading…")}
              class="rounded-xl bg-primary px-6 py-2.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
            >
              {ngettext(
                "Upload %{count} photo",
                "Upload %{count} photos",
                length(@uploads.photos.entries)
              )}
            </button>
          </div>
        </div>
      </.form>

      <ul
        id="gallery-images"
        phx-update="stream"
        class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
      >
        <li
          id="gallery-images-empty"
          class="hidden col-span-full rounded-2xl border border-dashed border-base-300 p-10 text-center text-sm text-base-content/55 only:block"
        >
          {gettext("No photos yet.")}
        </li>
        <li
          :for={{dom_id, image} <- @streams.images}
          id={dom_id}
          class="overflow-hidden rounded-2xl border border-base-300 bg-base-100"
        >
          <img
            src={image.image_url}
            alt={image.caption || ""}
            loading="lazy"
            class="aspect-[4/3] w-full bg-base-200 object-cover"
          />
          <form
            id={"caption-#{image.id}"}
            phx-submit="caption"
            class="flex items-center gap-2 p-3"
          >
            <input type="hidden" name="image_id" value={image.id} />
            <.input
              type="text"
              id={"caption-input-#{image.id}"}
              name="caption"
              value={image.caption}
              maxlength="255"
              dir="auto"
              placeholder={gettext("Add a caption")}
              aria-label={gettext("Caption")}
              wrapper_class="mb-0 min-w-0 flex-1"
            />
            <button
              type="submit"
              aria-label={gettext("Save caption")}
              class="grid size-8 shrink-0 place-items-center rounded-lg text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
            >
              <.icon name="hero-check" class="size-4" />
            </button>
            <button
              type="button"
              id={"delete-#{image.id}"}
              phx-click="delete"
              phx-value-id={image.id}
              data-confirm={gettext("Delete this photo?")}
              aria-label={gettext("Delete")}
              class="grid size-8 shrink-0 place-items-center rounded-lg text-error/80 transition hover:bg-error/10 hover:text-error"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </form>
        </li>
      </ul>

      <div :if={@loaded < @total} class="mt-6 text-center">
        <button
          type="button"
          phx-click="load-more"
          class="rounded-xl border border-base-300 bg-base-100 px-8 py-2.5 text-sm font-medium transition hover:bg-base-200"
        >
          {gettext("Show more")}
        </button>
      </div>
    </Layouts.dashboard>
    """
  end
end
