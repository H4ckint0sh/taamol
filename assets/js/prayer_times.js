// <prayer-times> custom element.
//
// Asks the browser for the visitor's location, fetches the day's prayer times
// (computed server-side by Taamol.PrayTime) and fills in the header chip and
// the popover: a live countdown on a sun-path arc, the day's prayer grid and,
// during Ramadan, a suhoor/iftar banner.
//
// A custom element is used instead of a LiveView hook so it also works on
// controller-rendered pages (e.g. the home page).

const LOCATION_KEY = "taamol:prayer-location"
const LOCATION_MAX_AGE = 24 * 60 * 60 * 1000
const DAY = 24 * 60 * 60 * 1000
const PRAYERS = ["fajr", "dhuhr", "asr", "maghrib", "isha"]
const ARC_PRAYERS = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]

const pad = n => String(n).padStart(2, "0")
const localDate = (d = new Date()) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
// ~1 km precision is plenty for prayer times and avoids storing an exact position
const round = n => Math.round(n * 100) / 100
const clamp = (n, min, max) => Math.min(max, Math.max(min, n))

function cachedLocation() {
  try {
    const loc = JSON.parse(localStorage.getItem(LOCATION_KEY))
    if (loc && Date.now() - loc.at < LOCATION_MAX_AGE) return loc
  } catch (_e) { /* ignore broken cache */ }
  return null
}

function requestLocation() {
  return new Promise((resolve, reject) => {
    if (!("geolocation" in navigator)) return reject(new Error("geolocation unsupported"))

    navigator.geolocation.getCurrentPosition(
      ({coords}) => {
        const loc = {lat: round(coords.latitude), lng: round(coords.longitude), at: Date.now()}
        try { localStorage.setItem(LOCATION_KEY, JSON.stringify(loc)) } catch (_e) { /* storage full/disabled */ }
        resolve(loc)
      },
      reject,
      {enableHighAccuracy: false, timeout: 15000, maximumAge: 60 * 60 * 1000}
    )
  })
}

async function fetchTimes({lat, lng}, date) {
  const cacheKey = `taamol:prayer-times:${lat},${lng},${date}`
  const cached = sessionStorage.getItem(cacheKey)
  if (cached) return JSON.parse(cached)

  const params = new URLSearchParams({lat, lng, date})
  const res = await fetch(`/api/prayer-times?${params}`, {headers: {accept: "application/json"}})
  if (!res.ok) throw new Error(`prayer times request failed: ${res.status}`)

  const data = await res.json()
  try { sessionStorage.setItem(cacheKey, JSON.stringify(data)) } catch (_e) { /* ignore */ }
  return data
}

class PrayerTimes extends HTMLElement {
  connectedCallback() {
    // state attributes go on the inner root: LiveView patches the attributes
    // of the phx-update="ignore" host element, but leaves its children alone
    this.root = this.querySelector("[data-role=root]")
    const locale = document.documentElement.lang || navigator.language
    const unit = (unit, unitDisplay) => new Intl.NumberFormat(locale, {style: "unit", unit, unitDisplay})

    this.timeFormat = new Intl.DateTimeFormat(locale, {hour: "numeric", minute: "2-digit"})
    this.two = new Intl.NumberFormat(locale, {minimumIntegerDigits: 2, useGrouping: false})
    this.number = new Intl.NumberFormat(locale)
    // "5h 15m"; Persian narrow units fall back to Latin letters, so use words
    const display = locale.startsWith("fa") ? "short" : "narrow"
    this.hours = unit("hour", display)
    this.minutes = unit("minute", display)
    try {
      const calendar = `${locale}-u-ca-islamic-umalqura`
      this.hijriFormat = new Intl.DateTimeFormat(calendar, {day: "numeric", month: "long", year: "numeric"})
      this.hijriParts = new Intl.DateTimeFormat(calendar, {day: "numeric", month: "numeric"})
    } catch (_e) { /* calendar unsupported: hide Hijri date and Ramadan banner */ }

    // City from the device timezone ("Europe/Stockholm" -> "Stockholm"). No
    // network lookup, so it names the timezone's city, not the exact town.
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone || ""
    this.$("place").textContent = zone.split("/").pop().replace(/_/g, " ")

    this.onTrigger = () => {
      const state = this.root.dataset.state
      if (state === "denied" || state === "error") this.start({retry: true})
    }
    this.$("trigger")?.addEventListener("click", this.onTrigger)

    this.start()
  }

  disconnectedCallback() {
    this.stopTimers()
    this.$("trigger")?.removeEventListener("click", this.onTrigger)
  }

  $(role) { return this.querySelector(`[data-role=${role}]`) }

  stopTimers() {
    clearTimeout(this.timer)
    clearInterval(this.secondTimer)
    this.secondTimer = null
  }

  async start({retry = false} = {}) {
    this.stopTimers()
    this.root.dataset.state = "loading"

    try {
      this.location = (!retry && cachedLocation()) || await requestLocation()
      this.date = null
      await this.tick()
    } catch (error) {
      this.stopTimers()
      // GeolocationPositionError.PERMISSION_DENIED === 1
      this.root.dataset.state = error && error.code === 1 ? "denied" : "error"
    }
  }

  // full re-render at the start of every minute
  async tick() {
    const today = localDate()

    if (this.date !== today) {
      this.data = await fetchTimes(this.location, today)
      this.date = today
    }

    this.render()
    this.root.dataset.state = "ready"

    if (!this.secondTimer) this.secondTimer = setInterval(() => this.renderCountdowns(), 1000)

    const now = new Date()
    const delay = (60 - now.getSeconds()) * 1000 - now.getMilliseconds() + 50
    this.timer = setTimeout(() => this.tick().catch(() => this.start()), delay)
  }

  render() {
    const now = Date.now()
    const {times, next_fajr: nextFajr} = this.data
    const format = ts => (ts ? this.timeFormat.format(ts) : "–")

    let next = PRAYERS.find(key => times[key] && times[key] > now)
    this.nextAt = next ? times[next] : nextFajr
    if (!next && nextFajr) next = "fajr"

    this.querySelectorAll("[data-prayer]").forEach(cell => {
      const key = cell.dataset.prayer
      const ts = times[key]
      cell.querySelector("[data-role=time]").textContent = format(ts)
      cell.toggleAttribute("data-next", key === next)
      cell.toggleAttribute("data-past", Boolean(ts) && ts <= now && key !== next)
    })

    const label = next ? this.querySelector(`[data-prayer="${next}"]`).dataset.label : ""
    this.$("next-label").textContent = label
    this.$("next-time").textContent = this.nextAt ? format(this.nextAt) : ""
    this.$("until").textContent = label ? this.$("until").dataset.template.replace("%{prayer}", label) : ""
    this.$("next-at").textContent = this.nextAt ? format(this.nextAt) : ""
    this.$("hijri").textContent = this.hijriFormat ? this.hijriFormat.format(now) : ""

    this.renderArc(now, times)
    this.renderRamadan(now, times, format)
    this.renderCountdowns()
  }

  // Sun path: a half circle from Fajr (left) to Isha (right).
  renderArc(now, times) {
    const start = times.fajr
    const end = times.isha
    if (!start || !end) return

    const point = ts => {
      const f = clamp((ts - start) / (end - start), 0, 1)
      // matches the SVG arc: centre (100, 104), radius 88, viewBox 200x112
      return {f, x: 100 - 88 * Math.cos(Math.PI * f), y: 104 - 88 * Math.sin(Math.PI * f)}
    }

    ARC_PRAYERS.forEach(key => {
      const marker = this.querySelector(`[data-marker=${key}]`)
      if (!marker || !times[key]) return
      const {x, y} = point(times[key])
      marker.setAttribute("cx", x.toFixed(2))
      marker.setAttribute("cy", y.toFixed(2))
    })

    const {f, x, y} = point(now)
    this.$("arc-progress").setAttribute("stroke-dasharray", `${f.toFixed(4)} 1`)
    Object.assign(this.$("sun").style, {left: `${x / 2}%`, top: `${(y / 112) * 100}%`})

    const night = !times.sunrise || !times.maghrib || now < times.sunrise || now >= times.maghrib
    this.root.toggleAttribute("data-night", night)
  }

  renderRamadan(now, times, format) {
    const parts = this.hijri(now)
    const ramadan = parts && parts.month === 9
    this.root.toggleAttribute("data-ramadan", ramadan)
    if (!ramadan) return

    // Umm al-Qura months have 29 or 30 days
    const total = this.hijri(now + (30 - parts.day) * DAY).month === 9 ? 30 : 29
    const template = this.$("ramadan-day").dataset.template
    this.$("ramadan-day").textContent = template
      .replace("%{day}", this.number.format(parts.day))
      .replace("%{total}", this.number.format(total))
    this.$("ramadan-progress").style.width = `${(parts.day / total) * 100}%`
    this.$("suhoor").textContent = format(times.fajr)
    this.$("iftar").textContent = format(times.maghrib)

    // fasting until Maghrib; otherwise count down to the end of suhoor (Fajr)
    const fasting = times.fajr && times.maghrib && now >= times.fajr && now < times.maghrib
    this.fastUntil = fasting ? times.maghrib : (now < times.fajr ? times.fajr : this.data.next_fajr)
    const fastLabel = this.$("fast-label")
    fastLabel.textContent = fasting ? fastLabel.dataset.iftar : fastLabel.dataset.suhoor
  }

  hijri(ts) {
    if (!this.hijriParts) return null
    const parts = Object.fromEntries(this.hijriParts.formatToParts(ts).map(p => [p.type, p.value]))
    return {day: parseInt(parts.day, 10), month: parseInt(parts.month, 10)}
  }

  // the only things updated every second
  renderCountdowns() {
    const now = Date.now()
    const left = this.nextAt ? Math.max(0, Math.ceil((this.nextAt - now) / 1000)) : 0
    const h = Math.floor(left / 3600)
    const m = Math.floor((left % 3600) / 60)
    const s = left % 60
    this.$("countdown").textContent = `${this.two.format(h)}:${this.two.format(m)}:${this.two.format(s)}`

    if (this.root.hasAttribute("data-ramadan") && this.fastUntil) {
      const mins = Math.max(0, Math.ceil((this.fastUntil - now) / 60000))
      const fh = Math.floor(mins / 60)
      this.$("fast-countdown").textContent =
        [fh && this.hours.format(fh), this.minutes.format(mins % 60)].filter(Boolean).join(" ")
    }
  }
}

if (!customElements.get("prayer-times")) {
  customElements.define("prayer-times", PrayerTimes)
}
