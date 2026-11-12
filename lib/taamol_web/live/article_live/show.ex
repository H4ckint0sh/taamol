defmodule TaamolWeb.ArticleLive.Show do
  @moduledoc """
  A single published article. Each connected visit counts one view.
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

    {:ok,
     socket
     |> assign(page_title: article.title, article: article)
     |> assign(:upcoming, Taamol.Events.upcoming(limit: 5))
     |> stream(
       :related,
       Tracking.list_public_articles(category: article.category, exclude: article.id, limit: 4)
     )
     |> stream(:most_read, Tracking.list_most_read_articles(limit: 5, exclude: article.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide active={@article.category}>
      <div class="mx-auto max-w-7xl px-4 pt-4 sm:px-6 lg:px-8 lg:pb-16 lg:pt-8">
        <div class="grid gap-10 xl:grid-cols-[minmax(0,1fr)_18rem]">
          <article id={"article-#{@article.id}"} class="mx-auto w-full max-w-3xl min-w-0">
            <div class="flex items-center justify-between gap-4">
              <.link
                id="article-back"
                navigate={~p"/categories/#{@article.category}"}
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
              </div>
            </header>

            <.cover
              :if={@article.cover_image_url}
              article={@article}
              class="mt-6 aspect-[16/9] w-full rounded-2xl"
              sizes="(min-width: 768px) 48rem, 100vw"
            />

            <p
              :if={@article.summary}
              dir="auto"
              class="mt-6 text-lg font-medium leading-relaxed text-base-content/85"
            >
              {@article.summary}
            </p>

            <div
              id="article-body"
              class="mt-6 space-y-5 text-[1.05rem] leading-8 text-base-content/85"
            >
              <p :for={paragraph <- paragraphs(@article.body)} dir="auto">{paragraph}</p>
            </div>

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
end
