# Demo content for development, in Persian, based on https://taamol.se
# (news texts, photos and gallery of Taamol – Jameh Imamiyeh Sweden).
#
#     mix run priv/repo/seeds.exs      (also run by `mix ecto.setup` / `mix ecto.reset`)
#
# Every section is skipped when its content already exists, so running the
# seeds twice doesn't duplicate anything. Photos are copied from
# priv/repo/seed_images into the uploads folder, like uploads from the editor.

import Ecto.Query

alias Taamol.Repo
alias Taamol.Accounts.User
alias Taamol.Tracking.{Article, ArticleLike, Comment, CommentLike}
alias Taamol.Events.Event
alias Taamol.Gallery.Image
alias Taamol.Contact.Message
alias Taamol.Bookings.{Booking, Service}
alias Taamol.Settings.SiteSetting

now = DateTime.utc_now(:second)
today = Date.utc_today()
seed_dir = Path.join(__DIR__, "seed_images")
data = __DIR__ |> Path.join("seed_data/taamol.json") |> File.read!() |> Jason.decode!()

store_image = fn file ->
  if file, do: TaamolWeb.Uploads.store!(Path.join(seed_dir, file), file)
end

# ---------------------------------------------------------------------------
# People: the administrator (created by the migration) and demo members
# ---------------------------------------------------------------------------
admin =
  Repo.one(from u in User, where: u.role == :admin, order_by: u.inserted_at, limit: 1) ||
    Repo.insert!(%User{
      email: "editor@taamol.local",
      name: "تحریریه تعامل",
      role: :admin,
      can_view_dashboard: true,
      confirmed_at: now
    })

member_specs = [
  {"zahra@example.com", "زهرا حسینی"},
  {"ali@example.com", "علی رضایی"},
  {"maryam@example.com", "مریم احمدی"},
  {"hasan@example.com", "حسن محمدی"},
  {"fatemeh@example.com", "فاطمه کریمی"}
]

members =
  for {email, name} <- member_specs do
    Repo.get_by(User, email: email) ||
      Repo.insert!(%User{email: email, name: name, confirmed_at: now})
  end

[zahra, ali, maryam, hasan, fatemeh] = members
IO.puts("People: #{admin.email} (admin) and #{length(members)} demo members.")

# ---------------------------------------------------------------------------
# News: the articles from taamol.se with their photos
# ---------------------------------------------------------------------------
truncate = fn text, max ->
  if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
end

if Repo.exists?(Article) do
  IO.puts("Articles already exist, skipping news.")
else
  articles =
    for {item, i} <- Enum.with_index(data["articles"]) do
      paragraphs = item["paragraphs"]
      date = Date.from_iso8601!(item["date"])

      published =
        date
        |> DateTime.new!(Time.new!(8 + rem(i * 3, 12), rem(i * 17, 60), 0))
        |> DateTime.truncate(:second)

      # a short opening paragraph becomes the summary (and isn't repeated in
      # the body); a long one is shortened for the summary and kept in the body
      {summary, body_paragraphs} =
        case paragraphs do
          [first | rest] when rest != [] and byte_size(first) > 0 ->
            if String.length(first) <= 280,
              do: {first, rest},
              else: {truncate.(first, 280), paragraphs}

          [first] ->
            {truncate.(first, 280), paragraphs}

          [] ->
            {nil, []}
        end

      %Article{creator_id: admin.id, view_count: 180 + rem(item["source_id"] * 137, 2400)}
      |> Article.changeset(%{
        title: truncate.(item["title"], 100),
        summary: summary,
        body: Enum.join(body_paragraphs, "\n\n"),
        category: item["category"],
        featured: item["featured"],
        author: "تحریریه تعامل",
        published: published,
        cover_image_url: store_image.(item["image"])
      })
      |> Repo.insert!()
    end

  IO.puts("Inserted #{length(articles)} articles from taamol.se.")
end

# ---------------------------------------------------------------------------
# Comments, replies and likes on the newest articles
# ---------------------------------------------------------------------------
if Repo.exists?(Comment) do
  IO.puts("Comments already exist, skipping comments.")
else
  newest = Repo.all(from a in Article, order_by: [desc: a.published], limit: 6)

  conversations = [
    [
      {zahra,
       "خدا رحمتشان کند. مجلس بسیار باشکوه و پرمعنایی بود، از همه برگزارکنندگان سپاسگزاریم."},
      {ali,
       "متن کامل سخنرانی را هم منتشر کنید لطفاً، برای کسانی که نتوانستند شرکت کنند خیلی مفید است.",
       :reply},
      {admin, "حتماً، متن کامل به‌زودی در همین بخش قرار می‌گیرد.", :reply}
    ],
    [
      {maryam,
       "ممنون از اطلاع‌رسانی. آیا برای خانواده‌ها و کودکان هم برنامه‌ای در نظر گرفته شده است؟"},
      {fatemeh, "پارسال برای بچه‌ها برنامه جداگانه داشتند، امیدوارم امسال هم باشد.", :reply}
    ],
    [
      {hasan, "مطلب بسیار خوب و آموزنده‌ای بود. ای کاش جوانان بیشتری این‌ها را بخوانند."},
      {zahra, "موافقم، شاید بشود در جلسات جوانان هم درباره‌اش گفت‌وگو کرد.", :reply}
    ],
    [
      {ali, "التماس دعا. جای همه خالی بود."}
    ],
    [
      {fatemeh, "خدا قوت به همه خادمان و داوطلبان که زحمت کشیدند."},
      {maryam, "واقعاً همه چیز منظم و آرام برگزار شد.", :reply}
    ],
    [
      {hasan, "اطلاعات مفیدی بود، ممنون. لطفاً ترجمه سوئدی را هم برای نسل جوان منتشر کنید."}
    ]
  ]

  count =
    for {article, conversation} <- Enum.zip(newest, conversations), reduce: 0 do
      acc ->
        {_, n} =
          Enum.reduce(conversation, {nil, acc}, fn
            {user, body, :reply}, {root, n} ->
              %Comment{
                article_id: article.id,
                creator_id: user.id,
                parent_id: root.id,
                inserted_at: DateTime.add(now, -(40 - n * 3) * 3600)
              }
              |> Comment.changeset(%{body: body})
              |> Repo.insert!()

              {root, n + 1}

            {user, body}, {_root, n} ->
              comment =
                %Comment{
                  article_id: article.id,
                  creator_id: user.id,
                  # spread over the last days, replies after their comment
                  inserted_at: DateTime.add(now, -(42 - n * 3) * 3600)
                }
                |> Comment.changeset(%{body: body})
                |> Repo.insert!()

              {comment, n + 1}
          end)

        n
    end

  # likes on the newest articles and on the first comments
  for {article, i} <- Enum.with_index(newest), user <- Enum.take(members, 5 - rem(i, 3)) do
    Repo.insert!(%ArticleLike{article_id: article.id, user_id: user.id}, on_conflict: :nothing)
  end

  for comment <- Repo.all(from c in Comment, where: is_nil(c.parent_id)), user <- [zahra, ali] do
    if comment.creator_id != user.id,
      do:
        Repo.insert!(%CommentLike{comment_id: comment.id, user_id: user.id},
          on_conflict: :nothing
        )
  end

  IO.puts("Inserted #{count} comments and replies, with likes.")
end

# ---------------------------------------------------------------------------
# Calendar: community events (Shia holidays are added automatically)
# ---------------------------------------------------------------------------
if Repo.exists?(Event) do
  IO.puts("Events already exist, skipping events.")
else
  next_weekday = fn weekday ->
    Date.add(
      today,
      Integer.mod(weekday - Date.day_of_week(today), 7) |> then(&if(&1 == 0, do: 7, else: &1))
    )
  end

  at = fn date, time -> NaiveDateTime.new!(date, time) end
  thursday = next_weekday.(4)
  saturday = next_weekday.(6)

  events = [
    %{
      title: "دعای کمیل",
      kind: :community,
      location: "حسینیه امیرالمؤمنین (ع)",
      starts_at: at.(thursday, ~T[19:30:00]),
      ends_at: at.(thursday, ~T[21:00:00]),
      description: "قرائت دعای کمیل و پذیرایی. شرکت برای همه آزاد است."
    },
    %{
      title: "دعای کمیل",
      kind: :community,
      location: "حسینیه امیرالمؤمنین (ع)",
      starts_at: at.(Date.add(thursday, 7), ~T[19:30:00]),
      ends_at: at.(Date.add(thursday, 7), ~T[21:00:00]),
      description: "قرائت دعای کمیل و پذیرایی. شرکت برای همه آزاد است."
    },
    %{
      title: "مجلس عزاداری ایام فاطمیه",
      kind: :mourning,
      location: "حسینیه امیرالمؤمنین (ع)",
      starts_at: at.(Date.add(today, 1), ~T[18:00:00]),
      ends_at: at.(Date.add(today, 1), ~T[21:00:00]),
      description:
        "سخنرانی، مرثیه‌خوانی و سینه‌زنی به مناسبت شهادت حضرت فاطمه زهرا (س). پس از مراسم شام نذری صرف می‌شود."
    },
    %{
      title: "کلاس آموزش قرآن کودکان",
      kind: :community,
      location: "کلاس‌های حسینیه",
      starts_at: at.(saturday, ~T[11:00:00]),
      ends_at: at.(saturday, ~T[13:00:00]),
      description: "آموزش روخوانی و روان‌خوانی قرآن برای کودکان ۷ تا ۱۴ سال."
    },
    %{
      title: "جلسه ماهانه هیئت مدیره و اعضا",
      kind: :community,
      location: "دفتر جامعه امامیه",
      starts_at: at.(Date.add(today, 9), ~T[18:30:00]),
      ends_at: at.(Date.add(today, 9), ~T[20:00:00]),
      description: "گزارش فعالیت‌ها و برنامه‌ریزی ماه آینده. همه اعضا دعوت هستند."
    },
    %{
      title: "جشن میلاد حضرت فاطمه زهرا (س) و روز مادر",
      kind: :celebration,
      location: "سالن جامعه امامیه",
      starts_at: at.(Taamol.Events.Hijri.to_date(1448, 6, 20), ~T[17:00:00]),
      ends_at: at.(Taamol.Events.Hijri.to_date(1448, 6, 20), ~T[20:30:00]),
      description: "مولودی‌خوانی، برنامه کودکان و تجلیل از مادران."
    },
    %{
      title: "فوتبال جوانان",
      kind: :community,
      location: "سالن ورزشی",
      starts_at: at.(Date.add(today, 4), ~T[17:00:00]),
      ends_at: at.(Date.add(today, 4), ~T[18:30:00])
    }
  ]

  for attrs <- events,
      do: %Event{creator_id: admin.id} |> Event.changeset(attrs) |> Repo.insert!()

  IO.puts("Inserted #{length(events)} community events.")
end

# ---------------------------------------------------------------------------
# Gallery: photos from taamol.se
# ---------------------------------------------------------------------------
if Repo.exists?(Image) do
  IO.puts("Gallery already has photos, skipping gallery.")
else
  for {photo, i} <- Enum.with_index(data["gallery"]) do
    Repo.insert!(%Image{
      image_url: store_image.(photo["image"]),
      caption: photo["caption"],
      creator_id: admin.id,
      inserted_at: DateTime.add(now, -i * 3600),
      updated_at: now
    })
  end

  IO.puts("Inserted #{length(data["gallery"])} gallery photos.")
end

# ---------------------------------------------------------------------------
# Site settings: Swish, social links (placeholders) and the prayer method
# ---------------------------------------------------------------------------
settings = Repo.get(SiteSetting, 1) || %SiteSetting{id: 1}

defaults = %{
  # Swish's own test number: replace with the community's real number
  swish_number: "1231181189",
  swish_message: "کمک به جامعه امامیه",
  # Shia Ithna Ashari (Jafari) prayer times
  prayer_method: "Jafari",
  # placeholders: replace with the community's real accounts
  instagram_url: "https://instagram.com/taamol",
  facebook_url: "https://facebook.com/taamol",
  telegram_url: "https://t.me/taamol",
  youtube_url: "https://youtube.com/@taamol",
  whatsapp_url: "https://wa.me/46700000000",
  # placeholders: replace with the community's real contact details
  contact_address: "Exempelgatan 12\n352 30 Växjö",
  contact_phone: "070 000 00 00",
  contact_email: "info@example.com",
  opening_hours: "شنبه تا پنجشنبه: ۱۷:۰۰ تا ۲۲:۰۰\nجمعه: ۱۸:۰۰ تا ۲۳:۰۰"
}

# only fill empty fields (and the prayer method while it's still the default)
missing =
  for {field, value} <- defaults,
      if(field == :prayer_method,
        do: settings.prayer_method in [nil, "MWL"],
        else: Map.get(settings, field) in [nil, ""]
      ),
      into: %{},
      do: {field, value}

if missing == %{} do
  IO.puts("Site settings already set, skipping.")
else
  settings |> SiteSetting.changeset(missing) |> Repo.insert_or_update!()
  Taamol.Settings.reset_cache()
  IO.puts("Site settings: #{missing |> Map.keys() |> Enum.join(", ")}.")
end

# ---------------------------------------------------------------------------
# Booking: services and example bookings in every state
# ---------------------------------------------------------------------------
if Repo.exists?(Service) do
  IO.puts("Booking services already exist, skipping booking.")
else
  services =
    for attrs <- [
          %{
            name_fa: "سالن برای مراسم ختم",
            name_sv: "Lokal för minnesceremoni (khatm)",
            description_fa: "سالن برای مجلس ختم، قرآن‌خوانی و دیدار پس از خاکسپاری.",
            description_sv:
              "Lokalen för minnesstund, koranläsning och samling efter en begravning.",
            resource: :premises,
            duration_minutes: 720,
            opens_at: ~T[08:00:00],
            closes_at: ~T[20:00:00],
            icon: "hero-building-library",
            position: 1
          },
          %{
            name_fa: "امام برای عقد ازدواج",
            name_sv: "Imam för vigsel (nikah)",
            description_fa:
              "امام مراسم عقد را برگزار می‌کند. کارت شناسایی هر دو نفر و دو شاهد همراه داشته باشید.",
            description_sv:
              "Imamen förrättar vigseln. Ta med legitimation för båda och två vittnen.",
            resource: :imam,
            duration_minutes: 60,
            icon: "hero-heart",
            position: 2
          },
          %{
            name_fa: "سالن برای جشن",
            name_sv: "Lokal för firande",
            description_fa: "سالن برای جشن عروسی، عقیقه یا تولد.",
            description_sv: "Lokalen för till exempel bröllopsfest, aqiqa eller födelsedag.",
            resource: :premises,
            duration_minutes: 240,
            icon: "hero-sparkles",
            position: 3
          },
          %{
            name_fa: "امام برای مراسم دیگر",
            name_sv: "Imam för andra ceremonier",
            description_fa: "برای نمونه قرآن‌خوانی در خانه، گفت‌وگو یا مشاوره.",
            description_sv: "Till exempel koranläsning i hemmet, samtal eller rådgivning.",
            resource: :imam,
            duration_minutes: 60,
            icon: "hero-book-open",
            position: 4
          }
        ] do
      %Service{} |> Service.changeset(attrs) |> Repo.insert!()
    end

  [khatm, nikah, party, _other] = services
  at = fn days, time -> NaiveDateTime.new!(Date.add(today, days), time) end

  bookings = [
    # waiting for an answer
    %Booking{
      service_id: khatm.id,
      user_id: hasan.id,
      status: :pending,
      starts_at: at.(6, ~T[08:00:00]),
      ends_at: at.(6, ~T[20:00:00]),
      contact_name: "حسن محمدی",
      contact_phone: "070 111 22 33",
      guests: 80,
      notes: "مجلس ختم برای پدرم. اگر ممکن است قاری قرآن هم حضور داشته باشد."
    },
    # confirmed
    %Booking{
      service_id: nikah.id,
      user_id: maryam.id,
      status: :confirmed,
      starts_at: at.(10, ~T[14:00:00]),
      ends_at: at.(10, ~T[15:00:00]),
      contact_name: "مریم احمدی",
      contact_phone: "073 444 55 66",
      guests: 12,
      notes: "عقد ساده خانوادگی.",
      admin_message: "مبارک باشد! لطفاً ده دقیقه زودتر حاضر شوید.",
      decided_by_id: admin.id,
      decided_at: now
    },
    # another time offered
    %Booking{
      service_id: party.id,
      user_id: ali.id,
      status: :proposed,
      starts_at: at.(14, ~T[12:00:00]),
      ends_at: at.(14, ~T[16:00:00]),
      proposed_starts_at: at.(15, ~T[13:00:00]),
      proposed_ends_at: at.(15, ~T[17:00:00]),
      contact_name: "علی رضایی",
      contact_phone: "076 777 88 99",
      guests: 60,
      notes: "جشن عقیقه پسرمان.",
      admin_message: "سالن در آن روز رزرو است، روز بعد را پیشنهاد می‌کنیم.",
      decided_by_id: admin.id,
      decided_at: now
    }
  ]

  Enum.each(bookings, &Repo.insert!/1)
  IO.puts("Inserted #{length(services)} booking services and #{length(bookings)} bookings.")
end

# ---------------------------------------------------------------------------
# Contact page messages
# ---------------------------------------------------------------------------
if Repo.exists?(Message) do
  IO.puts("Messages already exist, skipping messages.")
else
  messages = [
    {"زهرا حسینی", "zahra@example.com", :question,
     "سلام. آیا کلاس‌های قرآن برای بزرگسالان هم برگزار می‌شود؟ اگر بله، چه روزهایی؟", nil},
    {"رضا نوری", "reza.nouri@example.com", :feedback,
     "وب‌سایت جدید بسیار زیبا و کاربردی است. ممنون از زحمات شما. پیشنهاد می‌کنم اوقات شرعی را در صفحه اول بزرگ‌تر نمایش دهید.",
     now},
    {"سارا جعفری", "sara.jafari@example.com", :events,
     "برای جشن میلاد حضرت زهرا (س) می‌خواهم داوطلب شوم. چطور می‌توانم کمک کنم؟", nil},
    {"Johan Lindberg", "johan.lindberg@example.com", :other,
     "Hej! Vi är en skolklass som gärna vill besöka er moské och lära oss mer. Går det att boka ett besök?",
     nil}
  ]

  for {{name, email, topic, text, read_at}, i} <- Enum.with_index(messages) do
    Repo.insert!(%Message{
      name: name,
      email: email,
      topic: topic,
      message: text,
      read_at: read_at,
      inserted_at: DateTime.add(now, -(i + 1) * 5 * 3600),
      updated_at: now
    })
  end

  IO.puts("Inserted #{length(messages)} contact messages.")
end
