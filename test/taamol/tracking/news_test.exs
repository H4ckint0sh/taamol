defmodule Taamol.Tracking.NewsTest do
  use Taamol.DataCase, async: true

  import Taamol.AccountsFixtures
  import Taamol.TrackingFixtures

  alias Taamol.Tracking

  setup do
    %{creator: user_fixture()}
  end

  test "public lists exclude drafts and future articles", %{creator: creator} do
    published = article_fixture(creator)
    article_fixture(creator, published: nil)
    article_fixture(creator, published: DateTime.add(DateTime.utc_now(:second), 3600))

    assert [%{id: id}] = Tracking.list_public_articles()
    assert id == published.id
    assert_raise Ecto.NoResultsError, fn -> Tracking.get_public_article!(Ecto.UUID.generate()) end
    assert_raise Ecto.NoResultsError, fn -> Tracking.get_public_article!("not-a-uuid") end
  end

  test "filters by category and excludes an article", %{creator: creator} do
    world = article_fixture(creator, category: :world)
    other_world = article_fixture(creator, category: :world)
    article_fixture(creator, category: :sport)

    ids = Tracking.list_public_articles(category: :world) |> Enum.map(& &1.id) |> Enum.sort()
    assert ids == Enum.sort([world.id, other_world.id])

    assert [%{id: id}] = Tracking.list_public_articles(category: :world, exclude: world.id)
    assert id == other_world.id
    assert %{world: 2, sport: 1} = Tracking.count_public_articles_by_category()
  end

  test "the lead article prefers featured articles", %{creator: creator} do
    assert Tracking.get_lead_article() == nil

    featured =
      article_fixture(creator,
        featured: true,
        published: DateTime.add(DateTime.utc_now(:second), -7200)
      )

    article_fixture(creator)

    assert Tracking.get_lead_article().id == featured.id
  end

  test "most read is ordered by views and views can be counted", %{creator: creator} do
    low = article_fixture(creator, view_count: 1)
    high = article_fixture(creator, view_count: 50)

    assert [%{id: first}, %{id: second}] = Tracking.list_most_read_articles()
    assert {first, second} == {high.id, low.id}
    assert Tracking.increment_article_views(low) == 2
  end

  test "cover images must be http(s) URLs", %{creator: creator} do
    changeset =
      Taamol.Tracking.Article.changeset(%Taamol.Tracking.Article{creator_id: creator.id}, %{
        title: "Title",
        cover_image_url: "javascript:alert(1)"
      })

    assert %{cover_image_url: [_]} = errors_on(changeset)
  end
end
