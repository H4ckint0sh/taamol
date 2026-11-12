defmodule Taamol.TrackingFixtures do
  @moduledoc """
  Test helpers for creating articles.
  """

  alias Taamol.Repo
  alias Taamol.Tracking.Article

  @doc """
  Inserts a published article (published a minute ago) for `creator`.
  Pass `published: nil` for a draft, or `view_count:` to set views.
  """
  def article_fixture(creator, attrs \\ %{}) do
    attrs = Map.new(attrs)
    {view_count, attrs} = Map.pop(attrs, :view_count, 0)

    %Article{creator_id: creator.id, view_count: view_count}
    |> Article.changeset(
      Map.merge(
        %{
          title: "Article #{System.unique_integer([:positive])}",
          summary: "A short summary",
          body: "First paragraph.\n\nSecond paragraph.",
          category: :community,
          published: DateTime.add(DateTime.utc_now(:second), -60)
        },
        attrs
      )
    )
    |> Repo.insert!()
  end
end
