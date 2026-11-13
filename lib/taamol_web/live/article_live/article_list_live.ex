defmodule TaamolWeb.ArticleLive.ArticleListLive do
  use TaamolWeb, :live_view
  alias Taamol.Tracking

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :articles, Tracking.list_public_articles())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.page_hero id="articles-hero" class="mb-6">
        <:title>{gettext("News")}</:title>
      </Layouts.page_hero>
      <.table id="articles" rows={@streams.articles} row_item={fn {_id, article} -> article end}>
        <:col :let={article} label={gettext("Title")}><span dir="auto">{article.title}</span></:col>
        <:col :let={article} label={gettext("Body")}><span dir="auto">{article.body}</span></:col>
        <:col :let={article} label={gettext("Publication Date")}>{to_string(article.published)}</:col>
        <:col :let={article} label={gettext("Created By")}>
          <span dir="auto">{article.creator.name}</span>
        </:col>
      </.table>
    </Layouts.app>
    """
  end
end
