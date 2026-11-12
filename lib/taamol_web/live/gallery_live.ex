defmodule TaamolWeb.GalleryLive do
  @moduledoc """
  `/gallery`: the photo gallery as a mosaic. On wide screens it repeats in
  groups of nine on a five-column grid: three narrow columns of small and tall
  tiles beside a wide tile and a large 2×2 tile. `?photo=<id>` opens a photo in
  the full-screen viewer; arrow keys move between photos and Escape closes.
  """
  use TaamolWeb, :live_view

  alias Taamol.Gallery

  # a multiple of 9 keeps the mosaic pattern intact across pages
  @page_size 18

  @impl true
  def mount(_params, _session, socket) do
    images = Gallery.list_images(limit: @page_size)

    {:ok,
     socket
     |> assign(
       page_title: gettext("Gallery"),
       total: Gallery.count_images(),
       loaded: length(images)
     )
     |> stream(:images, positioned(images, 0))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case params["photo"] && Gallery.get_image(params["photo"]) do
      nil ->
        {:noreply, assign(socket, photo: nil, newer: nil, older: nil)}

      photo ->
        {newer, older} = Gallery.neighbours(photo)
        {:noreply, assign(socket, photo: photo, newer: newer, older: older)}
    end
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    images = Gallery.list_images(limit: @page_size, offset: socket.assigns.loaded)

    {:noreply,
     socket
     |> update(:loaded, &(&1 + length(images)))
     |> stream(:images, positioned(images, socket.assigns.loaded))}
  end

  def handle_event("viewer-key", %{"key" => key}, socket) do
    target =
      case key do
        "Escape" -> :close
        "ArrowRight" -> if(rtl?(), do: socket.assigns.newer, else: socket.assigns.older)
        "ArrowLeft" -> if(rtl?(), do: socket.assigns.older, else: socket.assigns.newer)
        _ -> nil
      end

    case target do
      nil -> {:noreply, socket}
      :close -> {:noreply, push_patch(socket, to: ~p"/gallery")}
      image -> {:noreply, push_patch(socket, to: ~p"/gallery?#{[photo: image.id]}")}
    end
  end

  defp rtl?, do: Gettext.get_locale(TaamolWeb.Gettext) == "fa"

  defp positioned(images, start) do
    images
    |> Enum.with_index(start)
    |> Enum.map(fn {image, pos} -> %{id: image.id, image: image, pos: pos} end)
  end

  # tile shape by position within each group of nine (five-column grid):
  #   row 1: small · small · tall · wide
  #   row 2: small · tall  · ↑    · large (2×2)
  #   row 3: small · ↑     · small · ↑
  defp tile_class(pos) do
    case rem(pos, 9) do
      2 -> "row-span-2"
      3 -> "col-span-2"
      5 -> "row-span-2"
      6 -> "col-span-2 row-span-2"
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={:gallery}>
      <div id="gallery" class="mx-auto max-w-7xl px-4 pt-6 sm:px-6 lg:px-8 lg:pt-10">
        <div class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 class="text-2xl font-bold tracking-tight sm:text-3xl">{gettext("Gallery")}</h1>
            <p class="mt-1 text-sm text-base-content/60">
              {ngettext("%{count} photo", "%{count} photos", @total)}
            </p>
          </div>
        </div>

        <div
          id="gallery-grid"
          phx-update="stream"
          class="mt-6 grid grid-flow-row-dense auto-rows-[8.5rem] grid-cols-2 gap-2 sm:auto-rows-[10rem] sm:grid-cols-3 sm:gap-3 lg:auto-rows-[11.5rem] lg:grid-cols-5"
        >
          <div
            id="gallery-empty"
            class="col-span-full row-span-2 hidden place-items-center rounded-2xl border border-dashed border-base-300 text-center text-sm text-base-content/55 only:grid"
          >
            <div>
              <.icon name="hero-photo" class="mx-auto size-10 text-base-content/30" />
              <p class="mt-2">{gettext("No photos yet.")}</p>
            </div>
          </div>
          <.link
            :for={{dom_id, item} <- @streams.images}
            id={dom_id}
            patch={~p"/gallery?#{[photo: item.id]}"}
            class={[
              "group relative overflow-hidden rounded-lg bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
              tile_class(item.pos)
            ]}
          >
            <img
              src={item.image.image_url}
              alt={item.image.caption || ""}
              loading="lazy"
              decoding="async"
              class="size-full object-cover transition duration-500 group-hover:scale-[1.04]"
            />
            <span
              :if={item.image.caption}
              dir="auto"
              class="absolute inset-x-0 bottom-0 translate-y-2 bg-linear-to-t from-black/70 to-transparent p-3 pt-8 text-sm font-medium text-white opacity-0 transition duration-300 group-hover:translate-y-0 group-hover:opacity-100"
            >
              {item.image.caption}
            </span>
          </.link>
        </div>

        <div :if={@loaded < @total} class="mt-8 text-center">
          <button
            id="gallery-load-more"
            type="button"
            phx-click="load-more"
            phx-disable-with={gettext("Loading…")}
            class="rounded-xl border border-base-300 px-8 py-2.5 text-sm font-medium transition hover:border-primary/40 hover:bg-base-200"
          >
            {gettext("Show more")}
          </button>
        </div>
      </div>

      <%!-- full-screen viewer --%>
      <div
        :if={@photo}
        id="gallery-viewer"
        role="dialog"
        aria-modal="true"
        aria-label={@photo.caption || gettext("Photo")}
        phx-window-keydown="viewer-key"
        class="fixed inset-0 z-[60] flex flex-col bg-black/95 text-white"
      >
        <div class="flex items-center justify-end gap-2 p-3 sm:p-4">
          <.link
            id="viewer-close"
            patch={~p"/gallery"}
            aria-label={gettext("Close")}
            class="grid size-10 place-items-center rounded-full bg-white/10 transition hover:bg-white/20"
          >
            <.icon name="hero-x-mark" class="size-6" />
          </.link>
        </div>

        <div class="relative flex min-h-0 flex-1 items-center justify-center px-4 sm:px-16">
          <img
            src={@photo.image_url}
            alt={@photo.caption || ""}
            class="max-h-full max-w-full rounded-lg object-contain shadow-2xl"
          />
          <.link
            :if={@newer}
            id="viewer-newer"
            patch={~p"/gallery?#{[photo: @newer.id]}"}
            aria-label={gettext("Previous photo")}
            class="absolute start-2 top-1/2 grid size-11 -translate-y-1/2 place-items-center rounded-full bg-white/10 transition hover:bg-white/25 sm:start-4"
          >
            <.icon name="hero-chevron-left" class="size-6 rtl:rotate-180" />
          </.link>
          <.link
            :if={@older}
            id="viewer-older"
            patch={~p"/gallery?#{[photo: @older.id]}"}
            aria-label={gettext("Next photo")}
            class="absolute end-2 top-1/2 grid size-11 -translate-y-1/2 place-items-center rounded-full bg-white/10 transition hover:bg-white/25 sm:end-4"
          >
            <.icon name="hero-chevron-right" class="size-6 rtl:rotate-180" />
          </.link>
        </div>

        <p
          :if={@photo.caption}
          id="viewer-caption"
          dir="auto"
          class="px-6 py-5 text-center text-sm text-white/85"
        >
          {@photo.caption}
        </p>
        <div :if={!@photo.caption} class="h-6" />
      </div>
    </Layouts.app>
    """
  end
end
