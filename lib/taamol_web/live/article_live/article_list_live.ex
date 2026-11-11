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
      <.table id="articles" rows={@streams.articles} row_item={fn {_id, article} -> article end}>
        <:col :let={article} label="Title">{article.title}</:col>
        <:col :let={article} label="Body">{article.body}</:col>
        <:col :let={article} label="Publication Date">{to_string(article.published)}</:col>
        <:col :let={article} label="Created By">{article.creator.name}</:col>
      </.table>
    </Layouts.app>
    """
  end
end
