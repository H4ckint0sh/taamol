defmodule TaamolWeb.DashboardLive.ArticleForm do
  @moduledoc """
  Write (`/dashboard/news/new`) or edit (`/dashboard/news/:id/edit`) an
  article: Markdown with a toolbar and a live, server-rendered preview (the
  same sanitized HTML the article page shows), image uploads into the text,
  a cover image and publishing options.
  """
  use TaamolWeb, :live_view

  import TaamolWeb.NewsComponents, only: [categories: 0, category_name: 1]

  alias Taamol.{Markdown, Tracking}
  alias Taamol.Tracking.Article
  alias TaamolWeb.Uploads

  on_mount {TaamolWeb.UserAuth, :require_admin}

  @impl true
  def mount(params, _session, socket) do
    case load(socket, socket.assigns.live_action, params) do
      {:ok, article} ->
        {:ok,
         socket
         |> assign(
           article: article,
           page_title: page_title(socket.assigns.live_action),
           status: if(article.published, do: "published", else: "draft"),
           cover_url: article.cover_image_url,
           preview: Markdown.to_html(article.body)
         )
         |> assign(:form, to_form(Article.changeset(article, %{})))
         |> allow_upload(:cover, Uploads.image_options())
         |> allow_upload(
           :inline_image,
           Uploads.image_options(auto_upload: true, progress: &handle_progress/3)
         )}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Article not found."))
         |> push_navigate(to: ~p"/dashboard/news")}
    end
  end

  defp load(socket, :new, _params),
    do: {:ok, %Article{creator_id: socket.assigns.current_scope.user.id}}

  defp load(socket, :edit, %{"id" => id}),
    do: Tracking.get_article_for_admin(socket.assigns.current_scope, id)

  defp page_title(:new), do: gettext("New article")
  defp page_title(:edit), do: gettext("Edit article")

  @impl true
  def handle_event("validate", %{"article" => params} = all, socket) do
    changeset = Article.changeset(socket.assigns.article, params)

    {:noreply,
     socket
     |> assign(form: to_form(changeset, action: :validate))
     |> assign(status: all["status"] || socket.assigns.status)
     |> assign(preview: Markdown.to_html(params["body"]))}
  end

  def handle_event("remove-cover", _params, socket) do
    {:noreply, assign(socket, cover_url: nil)}
  end

  def handle_event("cancel-upload", %{"ref" => ref, "name" => name}, socket)
      when name in ["cover", "inline_image"] do
    {:noreply, cancel_upload(socket, String.to_existing_atom(name), ref)}
  end

  def handle_event("save", %{"article" => params} = all, socket) do
    %{current_scope: scope, article: article, live_action: action} = socket.assigns

    uploaded =
      consume_uploaded_entries(socket, :cover, fn %{path: path}, entry ->
        {:ok, Uploads.store!(path, entry.client_name)}
      end)

    params =
      params
      |> Map.put("cover_image_url", List.first(uploaded) || socket.assigns.cover_url)
      |> Map.put("published", published_value(all["status"], article))

    result =
      case action do
        :new -> Tracking.create_article(scope, params)
        :edit -> Tracking.update_article(scope, article, params)
      end

    case result do
      {:ok, saved} when action == :new ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Article created."))
         |> push_navigate(to: ~p"/dashboard/news/#{saved.id}/edit")}

      {:ok, saved} ->
        {:noreply,
         socket
         |> assign(article: saved, cover_url: saved.cover_image_url)
         |> assign(status: if(saved.published, do: "published", else: "draft"))
         |> assign(:form, to_form(Article.changeset(saved, %{})))
         |> put_flash(:info, gettext("Article saved."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset), cover_url: params["cover_image_url"])}

      {:error, :forbidden} ->
        {:noreply, push_navigate(socket, to: ~p"/dashboard")}
    end
  end

  def handle_event("delete", _params, socket) do
    case Tracking.delete_article(socket.assigns.current_scope, socket.assigns.article) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Article deleted."))
         |> push_navigate(to: ~p"/dashboard/news")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("The article could not be deleted."))}
    end
  end

  # keep the original publish time when an article stays published
  defp published_value("published", %Article{published: %DateTime{} = published}), do: published
  defp published_value("published", _article), do: DateTime.utc_now(:second)
  defp published_value(_draft, _article), do: nil

  # an image dropped into the editor: store it and insert Markdown at the cursor
  defp handle_progress(:inline_image, entry, socket) do
    if entry.done? do
      url =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Uploads.store!(path, entry.client_name)}
        end)

      alt = entry.client_name |> Path.rootname() |> String.replace(~r/[\[\]\(\)]/, "")
      {:noreply, push_event(socket, "markdown:insert", %{text: "![#{alt}](#{url})"})}
    else
      {:noreply, socket}
    end
  end

  defp upload_error(:too_large), do: gettext("The image is too large (max 8 MB).")
  defp upload_error(:not_accepted), do: gettext("Use a JPG, PNG, WebP or GIF image.")
  defp upload_error(:too_many_files), do: gettext("Choose one image at a time.")
  defp upload_error(_), do: gettext("The image could not be uploaded.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      active={:news}
      title={@page_title}
    >
      <.link
        navigate={~p"/dashboard/news"}
        class="mb-4 inline-flex items-center gap-1.5 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="size-4 rtl:rotate-180" />{gettext("News")}
      </.link>

      <.form
        for={@form}
        id="article-form"
        phx-change="validate"
        phx-submit="save"
        class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_20rem]"
      >
        <%!-- writing column --%>
        <div class="min-w-0 space-y-4">
          <div class="rounded-2xl border border-base-300 bg-base-100 p-5">
            <.input
              field={@form[:title]}
              type="text"
              label={gettext("Title")}
              placeholder={gettext("A clear, short headline")}
              dir="auto"
              required
            />
            <.input
              field={@form[:summary]}
              type="textarea"
              label={gettext("Summary")}
              placeholder={gettext("One or two sentences shown under the headline")}
              rows="2"
              dir="auto"
            />
          </div>

          <div
            id="markdown-editor"
            phx-hook=".MarkdownEditor"
            class="group/editor overflow-hidden rounded-2xl border border-base-300 bg-base-100"
          >
            <div class="flex flex-wrap items-center gap-1 border-b border-base-300 px-2 py-1.5">
              <.tool md="bold" icon="hero-bold" label={gettext("Bold")} />
              <.tool md="italic" icon="hero-italic" label={gettext("Italic")} />
              <.tool md="h2" icon="hero-h2" label={gettext("Heading")} />
              <.tool md="h3" icon="hero-h3" label={gettext("Subheading")} />
              <span class="mx-1 h-5 w-px bg-base-300" />
              <.tool md="link" icon="hero-link" label={gettext("Link")} />
              <.tool md="quote" icon="hero-chat-bubble-bottom-center-text" label={gettext("Quote")} />
              <.tool md="ul" icon="hero-list-bullet" label={gettext("List")} />
              <.tool md="ol" icon="hero-numbered-list" label={gettext("Numbered list")} />
              <.tool md="code" icon="hero-code-bracket" label={gettext("Code")} />
              <span class="mx-1 h-5 w-px bg-base-300" />
              <label
                id="insert-image"
                title={gettext("Insert image")}
                class="grid size-8 cursor-pointer place-items-center rounded-lg text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
              >
                <.icon name="hero-photo" class="size-5" />
                <.live_file_input upload={@uploads.inline_image} class="sr-only" />
              </label>
              <span
                :for={entry <- @uploads.inline_image.entries}
                class="text-xs text-base-content/60"
              >
                {gettext("Uploading… %{progress}%", progress: entry.progress)}
              </span>

              <div class="ms-auto flex rounded-lg bg-base-200 p-0.5 text-xs font-medium lg:hidden">
                <button
                  type="button"
                  id="tab-write"
                  phx-click={JS.remove_class("show-preview", to: "#markdown-editor")}
                  class="rounded-md bg-base-100 px-3 py-1 shadow-sm group-[.show-preview]/editor:bg-transparent group-[.show-preview]/editor:shadow-none"
                >
                  {gettext("Write")}
                </button>
                <button
                  type="button"
                  id="tab-preview"
                  phx-click={JS.add_class("show-preview", to: "#markdown-editor")}
                  class="rounded-md px-3 py-1 group-[.show-preview]/editor:bg-base-100 group-[.show-preview]/editor:shadow-sm"
                >
                  {gettext("Preview")}
                </button>
              </div>
            </div>

            <p
              :for={
                err <-
                  upload_errors(@uploads.inline_image) ++
                    Enum.flat_map(
                      @uploads.inline_image.entries,
                      &upload_errors(@uploads.inline_image, &1)
                    )
              }
              class="border-b border-base-300 bg-error/10 px-4 py-2 text-xs text-error"
            >
              {upload_error(err)}
            </p>

            <div class="grid lg:grid-cols-2">
              <div class="group-[.show-preview]/editor:max-lg:hidden lg:border-e lg:border-base-300">
                <.input
                  field={@form[:body]}
                  type="textarea"
                  phx-debounce="250"
                  dir="auto"
                  placeholder={gettext("Write the article in Markdown…")}
                  class="block min-h-[28rem] w-full resize-y border-0 bg-transparent p-5 font-mono text-sm leading-relaxed outline-none"
                />
              </div>
              <div class="max-lg:hidden group-[.show-preview]/editor:max-lg:block">
                <p class="border-b border-base-300 px-5 py-2 text-[11px] font-semibold uppercase tracking-wider text-base-content/45 max-lg:hidden">
                  {gettext("Preview")}
                </p>
                <div id="markdown-preview" class="markdown-body min-h-[26rem] p-5" dir="auto">
                  <p :if={@preview == ""} class="text-base-content/45">
                    {gettext("Nothing to preview yet.")}
                  </p>
                  {raw(@preview)}
                </div>
              </div>
            </div>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".MarkdownEditor">
              export default {
                mounted() {
                  this.textarea = () => this.el.querySelector("textarea")
                  this.el.addEventListener("click", (e) => {
                    const button = e.target.closest("[data-md]")
                    if (!button) return
                    e.preventDefault()
                    this.apply(button.dataset.md)
                  })
                  this.handleEvent("markdown:insert", ({text}) => this.insertBlock(text))
                },
                apply(kind) {
                  const wraps = {
                    bold: ["**", "**", "bold text"], italic: ["_", "_", "italic text"],
                    code: ["`", "`", "code"], link: ["[", "](https://)", "link text"],
                  }
                  const prefixes = {h2: "## ", h3: "### ", quote: "> ", ul: "- ", ol: "1. "}
                  if (wraps[kind]) this.wrap(...wraps[kind])
                  else if (prefixes[kind]) this.prefixLines(prefixes[kind])
                },
                wrap(before, after, placeholder) {
                  const t = this.textarea(), start = t.selectionStart, end = t.selectionEnd
                  const text = t.value.slice(start, end) || placeholder
                  t.setRangeText(before + text + after, start, end, "end")
                  t.setSelectionRange(start + before.length, start + before.length + text.length)
                  this.changed()
                },
                prefixLines(prefix) {
                  const t = this.textarea()
                  const start = t.value.lastIndexOf("\n", t.selectionStart - 1) + 1
                  const end = t.selectionEnd
                  const lines = t.value.slice(start, end).split("\n").map((line) => prefix + line)
                  t.setRangeText(lines.join("\n"), start, end, "end")
                  this.changed()
                },
                insertBlock(text) {
                  const t = this.textarea(), start = t.selectionStart
                  const before = t.value.slice(0, start)
                  const gap = before && !before.endsWith("\n") ? "\n\n" : ""
                  t.setRangeText(gap + text + "\n", start, t.selectionEnd, "end")
                  this.changed()
                },
                changed() {
                  const t = this.textarea()
                  t.focus()
                  t.dispatchEvent(new Event("input", {bubbles: true}))
                },
              }
            </script>
          </div>

          <details class="rounded-2xl border border-base-300 bg-base-100 px-5 py-3 text-sm">
            <summary class="cursor-pointer font-medium">{gettext("Markdown help")}</summary>
            <div class="mt-3 space-y-1 overflow-x-auto rounded-xl bg-base-200 p-4 font-mono text-xs leading-relaxed text-base-content/80">
              <code
                :for={
                  line <- [
                    "## Heading",
                    "**bold**, _italic_, [link](https://example.com)",
                    "- list item",
                    "1. numbered item",
                    "> quote",
                    "![image description](/uploads/…)"
                  ]
                }
                class="block whitespace-pre"
              >{line}</code>
            </div>
          </details>
        </div>

        <%!-- side column --%>
        <div class="space-y-4">
          <section class="rounded-2xl border border-base-300 bg-base-100 p-5">
            <h2 class="mb-3 font-semibold">{gettext("Publishing")}</h2>
            <label for="article-status" class="label mb-1 text-sm">{gettext("Status")}</label>
            <select
              id="article-status"
              name="status"
              class="mb-3 w-full rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-sm outline-none focus:border-primary"
            >
              <option value="draft" selected={@status == "draft"}>{gettext("Draft")}</option>
              <option value="published" selected={@status == "published"}>
                {gettext("Published")}
              </option>
            </select>
            <p :if={@article.published} class="mb-3 text-xs text-base-content/55">
              {gettext("Published on %{date}",
                date: TaamolWeb.NewsComponents.format_date(@article.published, time: true)
              )}
            </p>
            <button
              type="submit"
              id="save-article"
              phx-disable-with={gettext("Saving…")}
              class="w-full rounded-xl bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
            >
              {gettext("Save")}
            </button>
            <div :if={@live_action == :edit} class="mt-3 flex items-center justify-between text-sm">
              <.link
                :if={Tracking.article_status(@article) == :published}
                navigate={~p"/articles/#{@article.id}"}
                class="inline-flex items-center gap-1 text-primary hover:underline"
              >
                <.icon name="hero-eye" class="size-4" />{gettext("View")}
              </.link>
              <button
                type="button"
                id="delete-article"
                phx-click="delete"
                data-confirm={gettext("Delete this article and its comments?")}
                class="ms-auto text-error hover:underline"
              >
                {gettext("Delete")}
              </button>
            </div>
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100 p-5">
            <.input
              field={@form[:category]}
              type="select"
              label={gettext("Category")}
              options={Enum.map(categories(), &{category_name(&1), &1})}
            />
            <.input field={@form[:featured]} type="checkbox" label={gettext("Top story")} />
            <.input
              field={@form[:author]}
              type="text"
              label={gettext("Author (optional)")}
              placeholder={@current_scope.user.name}
            />
          </section>

          <section class="rounded-2xl border border-base-300 bg-base-100 p-5">
            <h2 class="mb-3 font-semibold">{gettext("Cover image")}</h2>
            <%= cond do %>
              <% @uploads.cover.entries != [] -> %>
                <div :for={entry <- @uploads.cover.entries} class="relative">
                  <.live_img_preview
                    entry={entry}
                    class="aspect-[16/10] w-full rounded-xl object-cover"
                  />
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    phx-value-name="cover"
                    aria-label={gettext("Remove")}
                    class="absolute end-2 top-2 grid size-8 place-items-center rounded-full bg-base-100/90 shadow"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                  <p
                    :for={err <- upload_errors(@uploads.cover, entry)}
                    class="mt-2 text-xs text-error"
                  >
                    {upload_error(err)}
                  </p>
                </div>
              <% @cover_url -> %>
                <div class="relative">
                  <img src={@cover_url} alt="" class="aspect-[16/10] w-full rounded-xl object-cover" />
                  <button
                    type="button"
                    id="remove-cover"
                    phx-click="remove-cover"
                    aria-label={gettext("Remove")}
                    class="absolute end-2 top-2 grid size-8 place-items-center rounded-full bg-base-100/90 shadow"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              <% true -> %>
                <label
                  for={@uploads.cover.ref}
                  phx-drop-target={@uploads.cover.ref}
                  class="flex cursor-pointer flex-col items-center gap-2 rounded-xl border-2 border-dashed border-base-300 px-4 py-8 text-center text-sm text-base-content/60 transition hover:border-primary/50 hover:bg-base-200/50"
                >
                  <.icon name="hero-photo" class="size-8 text-base-content/40" />
                  <span>{gettext("Drop an image here or click to choose")}</span>
                  <span class="text-xs text-base-content/45">{gettext(
                    "JPG, PNG, WebP or GIF, up to 8 MB"
                  )}</span>
                </label>
            <% end %>
            <%!-- always rendered: the file is sent from this input when saving --%>
            <.live_file_input upload={@uploads.cover} class="sr-only" />
            <p :for={err <- upload_errors(@uploads.cover)} class="mt-2 text-xs text-error">
              {upload_error(err)}
            </p>
            <p
              :for={msg <- Enum.map(@form[:cover_image_url].errors, &translate_error/1)}
              class="mt-2 text-xs text-error"
            >
              {msg}
            </p>
          </section>
        </div>
      </.form>
    </Layouts.dashboard>
    """
  end

  attr :md, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp tool(assigns) do
    ~H"""
    <button
      type="button"
      data-md={@md}
      title={@label}
      aria-label={@label}
      class="grid size-8 place-items-center rounded-lg text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
    >
      <.icon name={@icon} class="size-5" />
    </button>
    """
  end
end
