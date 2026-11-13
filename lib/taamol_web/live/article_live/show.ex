defmodule TaamolWeb.ArticleLive.Show do
  @moduledoc """
  A single published article with likes and threaded comments. Each
  connected visit counts one view. Likes and comments from other readers
  arrive live over PubSub (`Tracking.subscribe_article/1`).
  """
  use TaamolWeb, :live_view

  import TaamolWeb.NewsComponents

  alias Taamol.Tracking

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    article = Tracking.get_public_article!(id)

    # count a view once per live visit (not for the static first render)
    article =
      if connected?(socket),
        do: %{article | view_count: Tracking.increment_article_views(article)},
        else: article

    scope = socket.assigns.current_scope
    if connected?(socket), do: Tracking.subscribe_article(article)

    {:ok,
     socket
     |> assign(page_title: article.title, article: article)
     |> assign(:upcoming, Taamol.Events.upcoming(limit: 5))
     |> assign(
       like_count: Tracking.article_like_count(article),
       liked?: Tracking.liked_by?(scope, article),
       comment_count: Tracking.comment_count(article),
       comment_form: to_form(%{"body" => ""}, as: :comment),
       # bumped after each post so the textarea is replaced with an empty one
       comment_key: 0,
       replying_to: nil,
       reply_form: to_form(%{"body" => ""}, as: :reply)
     )
     |> stream(:threads, Tracking.comment_threads(scope, article))
     |> stream(
       :related,
       Tracking.list_public_articles(category: article.category, exclude: article.id, limit: 4)
     )
     |> stream(:most_read, Tracking.list_most_read_articles(limit: 5, exclude: article.id))}
  end

  # ---------------------------------------------------------------------------
  # Likes and comments (logged-in users; guests are sent to log in)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event(_event, _params, %{assigns: %{current_scope: nil}} = socket) do
    {:noreply,
     socket
     |> put_flash(:info, gettext("Log in to like and comment."))
     |> push_navigate(to: ~p"/users/log-in")}
  end

  def handle_event("toggle-like", _params, socket) do
    %{current_scope: scope, article: article, liked?: liked?} = socket.assigns

    if liked?,
      do: Tracking.unlike_article(scope, article),
      else: Tracking.like_article(scope, article)

    count = Tracking.article_like_count(article)
    Tracking.broadcast_article(article, {:article_likes, count})
    {:noreply, assign(socket, like_count: count, liked?: not liked?)}
  end

  def handle_event("comment", %{"comment" => params}, socket) do
    %{current_scope: scope, article: article} = socket.assigns

    case Tracking.create_comment(scope, article, params) do
      {:ok, comment} ->
        {:noreply,
         socket
         |> assign(comment_form: to_form(%{"body" => ""}, as: :comment))
         |> update(:comment_key, &(&1 + 1))
         |> refresh_thread(comment.id, at: 0)}

      {:error, changeset} ->
        {:noreply, assign(socket, comment_form: to_form(changeset, as: :comment))}
    end
  end

  def handle_event("start-reply", %{"id" => id, "root" => root}, socket) do
    previous_root = socket.assigns[:replying_root]

    socket =
      socket
      |> assign(
        replying_to: id,
        replying_root: root,
        reply_form: to_form(%{"body" => ""}, as: :reply)
      )
      |> restream_thread(root)

    {:noreply,
     if(previous_root && previous_root != root,
       do: restream_thread(socket, previous_root),
       else: socket
     )}
  end

  def handle_event("cancel-reply", %{"root" => root}, socket) do
    {:noreply, socket |> assign(replying_to: nil, replying_root: nil) |> restream_thread(root)}
  end

  def handle_event(
        "reply",
        %{"parent_id" => parent_id, "root" => root, "reply" => params},
        socket
      ) do
    %{current_scope: scope, article: article} = socket.assigns

    with %{} = parent <- Tracking.get_article_comment(article, parent_id),
         {:ok, _reply} <- Tracking.reply_to_comment(scope, parent, params) do
      {:noreply,
       socket
       |> assign(replying_to: nil, replying_root: nil)
       |> refresh_thread(root)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket |> assign(reply_form: to_form(changeset, as: :reply)) |> restream_thread(root)}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("That comment no longer exists."))}
    end
  end

  def handle_event("toggle-comment-like", %{"id" => id, "root" => root, "liked" => liked}, socket) do
    %{current_scope: scope, article: article} = socket.assigns

    case Tracking.get_article_comment(article, id) do
      nil ->
        {:noreply, socket}

      comment ->
        if liked == "true",
          do: Tracking.unlike_comment(scope, comment),
          else: Tracking.like_comment(scope, comment)

        {:noreply, refresh_thread(socket, root)}
    end
  end

  def handle_event("delete-comment", %{"id" => id, "root" => root}, socket) do
    %{current_scope: scope, article: article} = socket.assigns

    with %{} = comment <- Tracking.get_article_comment(article, id),
         {:ok, _} <- Tracking.delete_comment(scope, comment) do
      {:noreply, socket |> put_flash(:info, gettext("Comment deleted.")) |> refresh_thread(root)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("The comment could not be deleted."))}
    end
  end

  @impl true
  def handle_info({:article_likes, count}, socket),
    do: {:noreply, assign(socket, like_count: count)}

  def handle_info({:thread_changed, root}, socket),
    do: {:noreply, refresh_thread(socket, root, broadcast: false, at: 0)}

  # Re-reads one thread after a change, updates the count and tells other readers.
  defp refresh_thread(socket, root, opts \\ []) do
    if Keyword.get(opts, :broadcast, true),
      do: Tracking.broadcast_article(socket.assigns.article, {:thread_changed, root})

    socket
    |> assign(comment_count: Tracking.comment_count(socket.assigns.article))
    |> restream_thread(root, Keyword.take(opts, [:at]))
  end

  defp restream_thread(socket, root, opts \\ []) do
    %{current_scope: scope, article: article} = socket.assigns

    case Tracking.comment_thread(scope, article, root) do
      nil -> stream_delete_by_dom_id(socket, :threads, "threads-#{root}")
      thread -> stream_insert(socket, :threads, thread, opts)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={@article.category}>
      <div class="mx-auto max-w-7xl px-4 pt-4 sm:px-6 lg:px-8 lg:pt-8">
        <div class="grid gap-10 xl:grid-cols-[minmax(0,1fr)_18rem]">
          <article id={"article-#{@article.id}"} class="mx-auto w-full max-w-3xl min-w-0">
            <div class="flex items-center justify-between gap-4">
              <.link
                id="article-back"
                navigate={~p"/news?#{[category: @article.category]}"}
                class="inline-flex items-center gap-1.5 text-sm text-base-content/60 transition-colors hover:text-primary"
              >
                <.icon name="hero-arrow-left" class="size-4 rtl:rotate-180" />
                {category_name(@article.category)}
              </.link>
              <button
                id="share-article"
                type="button"
                phx-hook=".ShareArticle"
                data-title={@article.title}
                data-copied={gettext("Link copied")}
                class="inline-flex items-center gap-2 rounded-full border border-base-300 px-3 py-1.5 text-xs font-medium transition hover:border-primary/40 hover:bg-base-200"
              >
                <.icon name="hero-share" class="size-4" />
                <span data-label>{gettext("Share")}</span>
              </button>
              <script :type={Phoenix.LiveView.ColocatedHook} name=".ShareArticle">
                export default {
                  mounted() {
                    this.el.addEventListener("click", async () => {
                      const url = window.location.href
                      if (navigator.share) {
                        try { await navigator.share({title: this.el.dataset.title, url}) } catch (_e) {}
                        return
                      }
                      try { await navigator.clipboard.writeText(url) } catch (_e) { return }
                      const label = this.el.querySelector("[data-label]")
                      const original = label.textContent
                      label.textContent = this.el.dataset.copied
                      setTimeout(() => { label.textContent = original }, 2000)
                    })
                  }
                }
              </script>
            </div>

            <header class="mt-6">
              <.category_label category={@article.category} />
              <h1
                dir="auto"
                class="mt-2 text-3xl font-bold leading-tight tracking-tight text-balance sm:text-4xl"
              >
                {@article.title}
              </h1>
              <div class="mt-4 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-base-content/55">
                <span
                  :if={@article.author || @article.creator}
                  dir="auto"
                  class="font-medium text-base-content/80"
                >
                  {@article.author || @article.creator.name}
                </span>
                <time datetime={DateTime.to_iso8601(@article.published)}>
                  {format_date(@article.published, time: true)}
                </time>
                <span id="article-views" class="inline-flex items-center gap-1 tabular-nums">
                  <.icon name="hero-eye-micro" class="size-4" />
                  {format_count(@article.view_count)}
                </span>
                <a
                  href="#comments"
                  class="inline-flex items-center gap-1 tabular-nums hover:text-primary"
                >
                  <.icon name="hero-chat-bubble-left-micro" class="size-4" />
                  {format_count(@comment_count)}
                </a>
              </div>
            </header>

            <.cover
              :if={@article.cover_image_url}
              article={@article}
              class="mt-6 aspect-[16/9] w-full rounded-2xl"
              sizes="(min-width: 768px) 48rem, 100vw"
            />

            <p
              :if={show_summary?(@article)}
              dir="auto"
              class="mt-6 text-lg font-medium leading-relaxed text-base-content/85"
            >
              {@article.summary}
            </p>

            <div id="article-body" dir="auto" class="markdown-body mt-6 text-[1.05rem]">
              {raw(Taamol.Markdown.to_html(@article.body))}
            </div>

            <div id="article-reactions" class="mt-10 flex items-center gap-3">
              <.like_button id="like-article" liked={@liked?} count={@like_count} />
              <a
                href="#comments"
                class="inline-flex h-10 items-center gap-2 rounded-full border border-base-300 px-4 text-sm font-medium transition hover:border-primary/40 hover:bg-base-200"
              >
                <.icon name="hero-chat-bubble-left-right" class="size-5" />
                <span class="tabular-nums">{format_count(@comment_count)}</span>
                <span class="hidden sm:inline">{gettext("Comments")}</span>
              </a>
            </div>

            <section id="comments" class="mt-10 scroll-mt-24 border-t border-base-300 pt-8">
              <h2 class="text-lg font-bold tracking-tight">
                {gettext("Comments")}
                <span class="ms-1 text-base font-medium text-base-content/50 tabular-nums">
                  {@comment_count}
                </span>
              </h2>

              <%= if @current_scope do %>
                <.form
                  for={@comment_form}
                  id="comment-form"
                  phx-submit="comment"
                  class="mt-5 flex gap-3"
                >
                  <Layouts.avatar user={@current_scope.user} class="size-10 text-sm" />
                  <div class="min-w-0 flex-1">
                    <textarea
                      id={"comment-body-#{@comment_key}"}
                      name={@comment_form[:body].name}
                      rows="3"
                      maxlength="2000"
                      dir="auto"
                      required
                      placeholder={gettext("Write a comment…")}
                      class="block w-full resize-y rounded-2xl border border-base-300 bg-base-100 px-4 py-3 text-sm outline-none transition focus:border-primary"
                    >{@comment_form[:body].value}</textarea>
                    <p
                      :for={error <- @comment_form[:body].errors}
                      class="mt-1 text-xs text-error"
                    >
                      {translate_error(error)}
                    </p>
                    <div class="mt-2 flex justify-end">
                      <button
                        type="submit"
                        id="post-comment"
                        phx-disable-with={gettext("Posting…")}
                        class="rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-content transition hover:opacity-85"
                      >
                        {gettext("Post comment")}
                      </button>
                    </div>
                  </div>
                </.form>
              <% else %>
                <div
                  id="comments-login"
                  class="mt-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl bg-base-200/70 px-5 py-4"
                >
                  <p class="text-sm text-base-content/70">
                    {gettext("Log in to like and join the conversation.")}
                  </p>
                  <.link
                    navigate={~p"/users/log-in"}
                    class="rounded-full bg-primary px-4 py-2 text-sm font-semibold text-primary-content transition hover:opacity-85"
                  >
                    {gettext("Log in")}
                  </.link>
                </div>
              <% end %>

              <div id="threads" phx-update="stream" class="mt-8 space-y-6">
                <p id="threads-empty" class="hidden text-sm text-base-content/55 only:block">
                  {gettext("No comments yet. Be the first to comment.")}
                </p>
                <div :for={{dom_id, thread} <- @streams.threads} id={dom_id}>
                  <.comment_node
                    node={thread}
                    root={thread.id}
                    depth={0}
                    current_scope={@current_scope}
                    replying_to={@replying_to}
                    reply_form={@reply_form}
                  />
                </div>
              </div>
            </section>

            <section id="related" class="mt-12 border-t border-base-300 pt-8">
              <h2 class="text-lg font-bold tracking-tight">
                {gettext("More from %{category}", category: category_name(@article.category))}
              </h2>
              <div
                id="related-articles"
                phx-update="stream"
                class="mt-2 grid gap-x-8 divide-y divide-base-300/70 sm:grid-cols-2 sm:divide-y-0"
              >
                <p id="related-empty" class="hidden py-4 text-sm text-base-content/55 only:block">
                  {gettext("No other articles in this category yet.")}
                </p>
                <.compact_card
                  :for={{id, article} <- @streams.related}
                  id={id}
                  article={article}
                />
              </div>
            </section>
          </article>

          <.rail upcoming={@upcoming}>
            <.side_card id="rail-most-read" title={gettext("Most read")}>
              <div id="most-read" phx-update="stream" class="divide-y divide-base-300/70">
                <.compact_card
                  :for={{id, article} <- @streams.most_read}
                  id={id}
                  article={article}
                  show_views
                />
              </div>
            </.side_card>
          </.rail>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :liked, :boolean, required: true
  attr :count, :integer, required: true

  defp like_button(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-click="toggle-like"
      aria-pressed={to_string(@liked)}
      class={[
        "group inline-flex h-10 items-center gap-2 rounded-full border px-4 text-sm font-medium transition active:scale-95",
        if(@liked,
          do: "border-rose-500/30 bg-rose-500/10 text-rose-600 dark:text-rose-400",
          else: "border-base-300 hover:border-rose-400/50 hover:bg-rose-500/5"
        )
      ]}
    >
      <.icon
        name={if(@liked, do: "hero-heart-solid", else: "hero-heart")}
        class="size-5 transition-transform group-active:scale-125"
      />
      <span class="tabular-nums">{format_count(@count)}</span>
      <span class="hidden sm:inline">{if(@liked, do: gettext("Liked"), else: gettext("Like"))}</span>
    </button>
    """
  end

  attr :node, :map, required: true
  attr :root, :string, required: true
  attr :depth, :integer, required: true
  attr :current_scope, :map, default: nil
  attr :replying_to, :string, default: nil
  attr :reply_form, :any, required: true

  # one comment with its actions, reply form and (recursively) its replies
  defp comment_node(assigns) do
    ~H"""
    <article id={"comment-#{@node.id}"} class="flex gap-3">
      <Layouts.avatar
        user={@node.comment.creator}
        class={if(@depth == 0, do: "size-10 text-sm", else: "size-8 text-xs")}
      />
      <div class="min-w-0 flex-1">
        <div class="rounded-2xl rounded-ss-md bg-base-200/70 px-4 py-3">
          <div class="flex flex-wrap items-baseline gap-x-2">
            <span dir="auto" class="text-sm font-semibold">{@node.comment.creator.name}</span>
            <time
              datetime={DateTime.to_iso8601(@node.comment.inserted_at)}
              class="text-xs text-base-content/50"
            >
              {relative_time(@node.comment.inserted_at)}
            </time>
          </div>
          <%!-- kept on one line: whitespace here would show (pre-line keeps line breaks) --%>
          <p
            dir="auto"
            class="mt-1 whitespace-pre-line break-words text-sm leading-relaxed"
            phx-no-format
          >{@node.comment.body}</p>
        </div>

        <div class="mt-1 flex items-center gap-1 text-xs font-medium text-base-content/60">
          <button
            type="button"
            id={"like-comment-#{@node.id}"}
            phx-click="toggle-comment-like"
            phx-value-id={@node.id}
            phx-value-root={@root}
            phx-value-liked={to_string(@node.liked?)}
            aria-pressed={to_string(@node.liked?)}
            class={[
              "inline-flex items-center gap-1 rounded-full px-2 py-1 transition hover:bg-base-200",
              @node.liked? && "text-rose-600 dark:text-rose-400"
            ]}
          >
            <.icon
              name={if(@node.liked?, do: "hero-heart-solid", else: "hero-heart")}
              class="size-4"
            />
            <span :if={@node.likes > 0} class="tabular-nums">{@node.likes}</span>
            <span class="sr-only">{gettext("Like")}</span>
          </button>
          <button
            type="button"
            id={"reply-to-#{@node.id}"}
            phx-click="start-reply"
            phx-value-id={@node.id}
            phx-value-root={@root}
            class="inline-flex items-center gap-1 rounded-full px-2 py-1 transition hover:bg-base-200"
          >
            <.icon name="hero-arrow-uturn-left" class="size-4 rtl:-scale-x-100" />
            {gettext("Reply")}
          </button>
          <button
            :if={Taamol.Tracking.can_delete_comment?(@current_scope, @node.comment)}
            type="button"
            id={"delete-comment-#{@node.id}"}
            phx-click="delete-comment"
            phx-value-id={@node.id}
            phx-value-root={@root}
            data-confirm={gettext("Delete this comment and its replies?")}
            class="inline-flex items-center gap-1 rounded-full px-2 py-1 text-error/80 transition hover:bg-error/10 hover:text-error"
          >
            <.icon name="hero-trash" class="size-4" />
            <span class="sr-only">{gettext("Delete")}</span>
          </button>
        </div>

        <.form
          :if={@replying_to == @node.id}
          for={@reply_form}
          id={"reply-form-#{@node.id}"}
          phx-submit="reply"
          class="mt-2"
        >
          <input type="hidden" name="parent_id" value={@node.id} />
          <input type="hidden" name="root" value={@root} />
          <textarea
            id={"reply-body-#{@node.id}"}
            name={@reply_form[:body].name}
            rows="2"
            maxlength="2000"
            dir="auto"
            required
            phx-mounted={JS.focus()}
            placeholder={gettext("Reply to %{name}…", name: @node.comment.creator.name)}
            class="block w-full resize-y rounded-2xl border border-base-300 bg-base-100 px-4 py-2.5 text-sm outline-none transition focus:border-primary"
          >{@reply_form[:body].value}</textarea>
          <p :for={error <- @reply_form[:body].errors} class="mt-1 text-xs text-error">
            {translate_error(error)}
          </p>
          <div class="mt-2 flex justify-end gap-2">
            <button
              type="button"
              phx-click="cancel-reply"
              phx-value-root={@root}
              class="rounded-full px-4 py-1.5 text-sm transition hover:bg-base-200"
            >
              {gettext("Cancel")}
            </button>
            <button
              type="submit"
              id={"post-reply-#{@node.id}"}
              phx-disable-with={gettext("Posting…")}
              class="rounded-full bg-primary px-4 py-1.5 text-sm font-semibold text-primary-content transition hover:opacity-85"
            >
              {gettext("Reply")}
            </button>
          </div>
        </.form>

        <div
          :if={@node.replies != []}
          class={[
            "mt-4 space-y-4",
            @depth < 3 && "border-s-2 border-base-300/70 ps-4"
          ]}
        >
          <.comment_node
            :for={reply <- @node.replies}
            node={reply}
            root={@root}
            depth={@depth + 1}
            current_scope={@current_scope}
            replying_to={@replying_to}
            reply_form={@reply_form}
          />
        </div>
      </div>
    </article>
    """
  end

  # the summary is shown as a lead, unless the body already starts with it
  defp show_summary?(%{summary: nil}), do: false

  defp show_summary?(%{summary: summary, body: body}) do
    lead = summary |> String.trim_trailing("…") |> String.trim()
    not String.starts_with?(String.trim(body || ""), lead)
  end
end
