defmodule TaamolWeb.DashboardLive.DashboardCreateArticleLive do
  use TaamolWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="article-creation-placeholder" class="mx-auto max-w-3xl px-4 py-12">
        <h1 class="text-2xl font-semibold">{gettext("Create article")}</h1>
        <p class="mt-3 text-base-content/65">{gettext("Article creation is not available yet.")}</p>
      </div>
    </Layouts.app>
    """
  end
end
