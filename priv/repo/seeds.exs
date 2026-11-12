# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Taamol.Repo.insert!(%Taamol.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# ---------------------------------------------------------------------------
# Demo news content (development only). Skipped when the demo articles exist.
# Remove them with: DELETE FROM articles WHERE cover_image_url LIKE 'https://picsum.photos/seed/taamol-%';
# Images are placeholder photos from picsum.photos.
# ---------------------------------------------------------------------------
import Ecto.Query

alias Taamol.Repo
alias Taamol.Accounts.User
alias Taamol.Tracking.Article

demo_image_prefix = "https://picsum.photos/seed/taamol-"

if Repo.exists?(from a in Article, where: like(a.cover_image_url, ^"#{demo_image_prefix}%")) do
  IO.puts("Demo articles already exist, skipping demo news.")
else
  now = DateTime.utc_now(:second)

  editor =
    Repo.one(from u in User, where: u.role == :admin, limit: 1) ||
      Repo.insert!(%User{
        email: "editor@taamol.local",
        name: "Taamol Editor",
        role: :admin,
        can_view_dashboard: true,
        confirmed_at: now
      })

  image = fn seed -> "#{demo_image_prefix}#{seed}/1200/800" end

  body = fn _summary ->
    """
    The event brought together families, volunteers and guests from across the region. Organisers said the turnout exceeded expectations and thanked everyone who helped with preparations, food and childcare.

    "This is what community means to us: showing up for each other," one of the volunteers said. A follow-up meeting will be announced in the coming weeks.

    Those who want to get involved can contact the association after Friday prayers or through the website.
    """
  end

  articles = [
    {:community, true, 25, 12_540, "New community centre opens its doors in Stockholm",
     "After three years of fundraising the centre offers prayer halls, classrooms and a library for all ages."},
    {:religion, false, 45, 3_120, "Programme announced for the nights of Muharram",
     "Lectures, majalis and shared iftars will be held every evening at the centre."},
    {:sweden, false, 70, 2_450, "Municipality backs new youth sports initiative",
     "Free football and swimming sessions start in March for children aged 8 to 16."},
    {:world, false, 120, 5_320, "Pilgrims gather in Karbala for Arbaeen",
     "Millions walk from Najaf to Karbala in one of the world's largest annual gatherings."},
    {:society, false, 180, 1_840, "Volunteers deliver winter packages to 300 families",
     "Warm clothes, food and school supplies were handed out over the weekend."},
    {:culture, false, 240, 980, "Evening of Persian poetry draws a full house",
     "Readings of Hafez and Saadi were accompanied by live traditional music."},
    {:education, false, 300, 2_150,
     "Weekend school opens registration for Quran and language classes",
     "Classes in Quran recitation, Persian and Arabic for children and adults."},
    {:youth, false, 420, 1_230, "Youth council elects new board",
     "The new board wants to focus on mentoring, study help and outdoor activities."},
    {:health, false, 600, 760, "Free health check day at the centre on Saturday",
     "Nurses and doctors from the community offer blood pressure and diabetes checks."},
    {:sport, false, 900, 1_670, "Community football team wins regional cup",
     "A late goal secured the title in front of a crowd of supporters."},
    {:community, false, 1_500, 4_020, "Annual iftar gathers more than 500 guests",
     "Neighbours, local politicians and interfaith guests joined the shared meal."},
    {:religion, false, 2_000, 2_980, "Ramadan timetable published for Swedish cities",
     "The timetable covers suhoor and iftar times for Stockholm, Gothenburg and Malmö."},
    {:world, false, 2_900, 1_150, "Aid convoy reaches families affected by flooding",
     "Donations collected across Europe were delivered to the hardest hit villages."},
    {:sweden, false, 4_300, 640, "Ny samverkan mellan föreningar i Göteborg",
     "Fem föreningar har gått samman för att erbjuda läxhjälp och språkcaféer."},
    {:culture, false, 5_800, 1_330, "نمایشگاه خوشنویسی در مرکز فرهنگی برگزار شد",
     "آثار هنرمندان جوان و پیشکسوت در این نمایشگاه یک‌هفته‌ای به نمایش درآمد."},
    {:education, false, 8_000, 870, "Study circle on Nahj al-Balagha starts a new season",
     "Weekly sessions in English and Persian, open to everyone."}
  ]

  articles
  |> Enum.with_index()
  |> Enum.each(fn {{category, featured, minutes_ago, views, title, summary}, i} ->
    %Article{creator_id: editor.id, view_count: views}
    |> Article.changeset(%{
      title: title,
      summary: summary,
      body: body.(summary),
      category: category,
      featured: featured,
      published: DateTime.add(now, -minutes_ago * 60),
      cover_image_url: image.(i)
    })
    |> Repo.insert!()
  end)

  IO.puts("Inserted #{length(articles)} demo articles.")
end

# ---------------------------------------------------------------------------
# Demo community events (development only). Skipped when events exist.
# ---------------------------------------------------------------------------
alias Taamol.Events.Event

if Repo.exists?(Event) do
  IO.puts("Events already exist, skipping demo events.")
else
  admin = Repo.one(from u in User, where: u.role == :admin, limit: 1)
  today = Date.utc_today()
  at = fn days, time -> NaiveDateTime.new!(Date.add(today, days), time) end

  events = [
    %{
      title: "Dua Kumayl gathering",
      kind: :community,
      location: "Taamol centre, main hall",
      starts_at: at.(1, ~T[19:30:00]),
      ends_at: at.(1, ~T[21:00:00]),
      description: "Weekly recitation of Dua Kumayl followed by tea."
    },
    %{
      title: "Fatimiyya majlis",
      kind: :mourning,
      location: "Taamol centre",
      starts_at: at.(2, ~T[18:00:00]),
      ends_at: at.(2, ~T[21:00:00]),
      description: "Commemoration with a lecture in Persian and Swedish. Dinner is served."
    },
    %{
      title: "Youth football training",
      kind: :community,
      location: "Rinkeby sports hall",
      starts_at: at.(4, ~T[17:00:00]),
      ends_at: at.(4, ~T[18:30:00])
    },
    %{
      title: "Weekend school open house",
      kind: :community,
      location: "Taamol centre, classrooms",
      starts_at: at.(9, ~T[11:00:00]),
      ends_at: at.(9, ~T[14:00:00]),
      description: "Meet the teachers and register for Quran, Persian and Arabic classes."
    },
    %{
      title: "Community clean-up day",
      kind: :community,
      all_day: true,
      starts_at: at.(16, ~T[00:00:00]),
      location: "Meeting point: centre entrance"
    }
  ]

  for attrs <- events do
    %Event{creator_id: admin && admin.id} |> Event.changeset(attrs) |> Repo.insert!()
  end

  IO.puts("Inserted #{length(events)} demo events.")
end
