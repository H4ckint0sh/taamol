// <prayer-times> custom element.
//
// Fetches the day's prayer times for the site's default location
// (computed server-side by Taamol.PrayTime) and fills in the header chip and
// the popover: a live countdown on a sun-path arc, the day's prayer grid and,
// during Ramadan, a suhoor/iftar banner.
//
// A custom element is used instead of a LiveView hook so it also works on
// controller-rendered pages (e.g. the home page).

const DAY = 24 * 60 * 60 * 1000;
const PRAYERS = ["fajr", "dhuhr", "asr", "maghrib", "isha"];
const ARC_PRAYERS = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"];

const clamp = (n, min, max) => Math.min(max, Math.max(min, n));
const arcPoint = (f) => ({
  x: 100 - 88 * Math.cos(Math.PI * f),
  y: 104 - 88 * Math.sin(Math.PI * f),
});
const reducedMotion = () =>
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

async function fetchTimes({ lat, lng }, date) {
  const params = new URLSearchParams({ lat, lng, date });
  const res = await fetch(`/api/prayer-times?${params}`, {
    headers: { accept: "application/json" },
  });
  if (!res.ok) throw new Error(`prayer times request failed: ${res.status}`);

  return res.json();
}

class PrayerTimes extends HTMLElement {
  static get observedAttributes() {
    return ["data-calculation"];
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (name === "data-calculation" && oldValue !== newValue && this.isConnected && this.root) {
      this.startCalculation();
    }
  }

  connectedCallback() {
    // state attributes go on the inner root: LiveView patches the attributes
    // of the phx-update="ignore" host element, but leaves its children alone
    this.root = this.querySelector("[data-role=root]");
    const locale = document.documentElement.lang || navigator.language;
    this.two = new Intl.NumberFormat(locale, {
      minimumIntegerDigits: 2,
      useGrouping: false,
    });
    this.number = new Intl.NumberFormat(locale);

    if (this.dataset.calculation) {
      this.locale = locale;
      this.startCalculation();
      return;
    }

    const timezone = this.dataset.timezone;
    const unit = (unit, unitDisplay) =>
      new Intl.NumberFormat(locale, { style: "unit", unit, unitDisplay });

    this.location = { lat: this.dataset.latitude, lng: this.dataset.longitude };
    this.dateFormat = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    this.timeFormat = new Intl.DateTimeFormat(locale, {
      timeZone: timezone,
      hour: "numeric",
      minute: "2-digit",
    });
    // "5h 15m"; Persian narrow units fall back to Latin letters, so use words
    const display = locale.startsWith("fa") ? "short" : "narrow";
    this.hours = unit("hour", display);
    this.minutes = unit("minute", display);
    try {
      const calendar = `${locale}-u-ca-islamic-umalqura`;
      this.hijriFormat = new Intl.DateTimeFormat(calendar, {
        timeZone: timezone,
        day: "numeric",
        month: "long",
        year: "numeric",
      });
      this.hijriParts = new Intl.DateTimeFormat(calendar, {
        timeZone: timezone,
        day: "numeric",
        month: "numeric",
      });
    } catch (_e) {
      /* calendar unsupported: hide Hijri date and Ramadan banner */
    }

    this.set("place", this.dataset.city);

    this.onTrigger = () => {
      const state = this.root.dataset.state;
      if (state === "error") this.start();
    };
    // the chip (popover) or the whole card retries after a failure
    this.root.addEventListener("click", this.onTrigger);

    // the header popover replays the arc animation each time it opens
    if (this.$("trigger")) {
      this.onOpen = () => {
        if (this.popoverOpen) return;
        this.popoverOpen = true;
        this.playArcIntro();
      };
      this.onClose = (e) => {
        if (!this.root.contains(e.relatedTarget)) this.popoverOpen = false;
      };
      this.root.addEventListener("mouseenter", this.onOpen);
      this.root.addEventListener("focusin", this.onOpen);
      this.root.addEventListener("mouseleave", this.onClose);
      this.root.addEventListener("focusout", this.onClose);
    }

    this.start();
  }

  disconnectedCallback() {
    cancelAnimationFrame(this.raf);
    this.revealTimers?.forEach(clearTimeout);
    this.stopTimers();
    this.root?.removeEventListener("click", this.onTrigger);
  }

  $(role) {
    return this.querySelector(`[data-role=${role}]`);
  }

  // the card variant has no header chip, so every target is optional
  set(role, text) {
    const el = this.$(role);
    if (el) el.textContent = text;
  }

  stopTimers() {
    clearTimeout(this.timer);
    clearInterval(this.secondTimer);
    this.secondTimer = null;
  }

  startCalculation() {
    this.stopTimers();
    try {
      this.data = JSON.parse(this.dataset.calculation);
      this.calculation = true;
      const timezone = this.data.timezone || "UTC";
      this.offset = this.data.timezone ? 0 : this.data.utc_offset * 3600000;
      this.dateFormat = new Intl.DateTimeFormat("en-CA", {
        timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit",
      });
      this.timeFormat = new Intl.DateTimeFormat(this.locale, {
        timeZone: timezone, hour: "numeric", minute: "2-digit",
      });
      this.render();
      this.root.dataset.state = "ready";
      this.secondTimer = setInterval(() => {
        if ((this.nextAt && this.nextAt <= Date.now()) || this.renderedToday !== this.localToday()) {
          this.render();
        } else {
          this.renderCountdowns();
        }
      }, 1000);
    } catch (error) {
      console.error("Could not display calculated prayer times", error);
      this.root.dataset.state = "error";
      this.$("prayer-arc").hidden = true;
      this.$("arc-unavailable").hidden = false;
    }
  }

  localToday() {
    const parts = Object.fromEntries(
      this.dateFormat.formatToParts(new Date(Date.now() + this.offset))
        .map((part) => [part.type, part.value]),
    );
    return `${parts.year}-${parts.month}-${parts.day}`;
  }

  async start() {
    this.stopTimers();
    this.root.dataset.state = "loading";

    try {
      this.date = null;
      await this.tick();
    } catch (error) {
      this.stopTimers();
      console.error("Could not load prayer times", error);
      this.root.dataset.state = "error";
    }
  }

  // full re-render at the start of every minute
  async tick() {
    const parts = Object.fromEntries(
      this.dateFormat
        .formatToParts(new Date())
        .map((part) => [part.type, part.value]),
    );
    const today = `${parts.year}-${parts.month}-${parts.day}`;

    if (this.date !== today) {
      this.data = await fetchTimes(this.location, today);
      this.date = today;
    }

    this.render();
    this.root.dataset.state = "ready";

    if (!this.secondTimer)
      this.secondTimer = setInterval(() => this.renderCountdowns(), 1000);

    const now = new Date();
    const delay = (60 - now.getSeconds()) * 1000 - now.getMilliseconds() + 50;
    this.timer = setTimeout(() => this.tick().catch(() => this.start()), delay);
  }

  render() {
    const now = Date.now();
    const { times, next_fajr: nextFajr } = this.data;
    const format = (ts) => (ts ? this.timeFormat.format(ts + (this.offset || 0)) : "–");

    const today = this.calculation ? this.localToday() : null;
    this.renderedToday = today;
    if (this.calculation) {
      this.root.hidden = Math.abs(Date.parse(this.data.date) - Date.parse(today)) > 7 * DAY;
      if (this.root.hidden) {
        cancelAnimationFrame(this.raf);
        this.revealTimers?.forEach(clearTimeout);
        this.drawnFraction = undefined;
        this.targetFraction = undefined;
        this.nextAt = null;
        return;
      }
    }

    let next = this.calculation && this.data.date < today
      ? undefined
      : PRAYERS.find((key) => times[key] && times[key] > now);
    const allowTomorrow = !this.calculation ||
      (this.data.date === today && nextFajr > now);
    this.nextAt = next ? times[next] : (allowTomorrow ? nextFajr : null);
    if (!next && this.nextAt) next = "fajr";

    // after Isha the next prayer is tomorrow's Fajr: show that time in its cell
    const tomorrowFajr = !PRAYERS.some((key) => times[key] && times[key] > now);

    this.querySelectorAll("[data-prayer]").forEach((cell) => {
      const key = cell.dataset.prayer;
      const ts =
        key === "fajr" && tomorrowFajr && nextFajr ? nextFajr : times[key];
      cell.querySelector("[data-role=time]").textContent = format(ts);
      cell.toggleAttribute("data-next", key === next);
      cell.toggleAttribute(
        "data-past",
        Boolean(ts) && ts <= now && key !== next,
      );
    });

    // the header chip shows the next prayer's own icon
    this.querySelectorAll("[data-chip-icon]").forEach((el) => {
      el.hidden = el.dataset.chipIcon !== (next || "none");
    });

    const label = next
      ? (this.querySelector(`[data-prayer="${next}"]`) ||
        this.querySelector(`[data-marker-icon="${next}"]`))?.dataset.label || ""
      : "";
    this.set("next-label", label);
    this.set("next-time", this.nextAt ? format(this.nextAt) : "");
    this.set(
      "until",
      label ? this.$("until").dataset.template.replace("%{prayer}", label) : "",
    );
    this.set("next-at", this.nextAt ? format(this.nextAt) : "");
    this.set("hijri", this.hijriFormat ? this.hijriFormat.format(now) : "");

    this.renderArc(now, times, next);
    if (!this.calculation) this.renderRamadan(now, times, format);
    this.renderCountdowns();
  }

  // Sun path: a half circle from Fajr (left) to Isha (right).
  // The SVG arc has its centre at (100, 104) and radius 88 in a 200x112 box.
  renderArc(now, times, next) {
    const start = times.fajr;
    const end = times.isha;
    const available = Number.isFinite(start) && Number.isFinite(end) && end > start;
    const arc = this.$("prayer-arc");
    const unavailable = this.$("arc-unavailable");
    if (arc) arc.hidden = !available;
    if (unavailable) unavailable.hidden = available;
    if (!available) {
      cancelAnimationFrame(this.raf);
      this.revealTimers?.forEach(clearTimeout);
      this.drawnFraction = undefined;
      this.targetFraction = undefined;
      return;
    }

    this.arcFraction = (ts) => clamp((ts - start) / (end - start), 0, 1);

    ARC_PRAYERS.forEach((key) => {
      const marker = this.querySelector(`[data-marker=${key}]`);
      const icon = this.querySelector(`[data-marker-icon=${key}]`);
      if (!marker || !icon) return;
      const present = Number.isFinite(times[key]);
      marker.style.display = present ? "" : "none";
      icon.hidden = !present;
      if (!present) return;

      const { x, y } = arcPoint(this.arcFraction(times[key]));
      marker.setAttribute("cx", x.toFixed(2));
      marker.setAttribute("cy", y.toFixed(2));

      // the icon sits just inside the arc, towards its centre
      const dx = 100 - x,
        dy = 104 - y,
        len = Math.hypot(dx, dy) || 1;
      Object.assign(icon.style, {
        left: `${(x + (dx / len) * 17) / 2}%`,
        top: `${((y + (dy / len) * 17) / 112) * 100}%`,
      });

      const active = key === next;
      const past = !active && times[key] <= now;
      for (const el of [marker, icon]) {
        el.toggleAttribute("data-active", active);
        el.toggleAttribute("data-past", past);
      }
      marker.setAttribute("r", active ? "3.5" : "2.5");
    });

    this.targetFraction = this.arcFraction(now);

    if (this.drawnFraction === undefined) this.playArcIntro();
    else this.animateArc(this.targetFraction, 900);

    const night =
      !times.sunrise ||
      !times.maghrib ||
      now < times.sunrise ||
      now >= times.maghrib;
    this.root.toggleAttribute("data-night", night);
  }

  // the badge travels from Fajr to "now" and the icons rise in one by one
  playArcIntro() {
    if (this.targetFraction === undefined) return;
    const icons = [...this.querySelectorAll("[data-marker-icon]")];
    this.revealTimers?.forEach(clearTimeout);
    icons.forEach((icon) => icon.removeAttribute("data-shown"));

    this.drawnFraction = 0;
    this.animateArc(this.targetFraction, 1600);
    this.revealTimers = icons.map((icon, i) =>
      setTimeout(
        () => icon.setAttribute("data-shown", ""),
        reducedMotion() ? 0 : 250 + i * 140,
      ),
    );
  }

  // moves the badge along the curve (not straight across) and fills the line
  animateArc(target, duration) {
    cancelAnimationFrame(this.raf);
    const from = this.drawnFraction ?? 0;
    const ms = reducedMotion() ? 0 : duration;
    const started = performance.now();
    const ease = (t) => 1 - Math.pow(1 - t, 3);

    const step = (time) => {
      const progress = ms ? Math.min(1, (time - started) / ms) : 1;
      this.drawArc(from + (target - from) * ease(progress));
      if (progress < 1) this.raf = requestAnimationFrame(step);
    };
    this.raf = requestAnimationFrame(step);
  }

  drawArc(fraction) {
    this.drawnFraction = fraction;
    const { x, y } = arcPoint(fraction);
    this.$("arc-progress").setAttribute(
      "stroke-dasharray",
      `${fraction.toFixed(4)} 1`,
    );
    Object.assign(this.$("sun").style, {
      left: `${x / 2}%`,
      top: `${(y / 112) * 100}%`,
    });
  }

  renderRamadan(now, times, format) {
    const parts = this.hijri(now);
    const ramadan = parts && parts.month === 9;
    this.root.toggleAttribute("data-ramadan", ramadan);
    if (!ramadan) return;

    // Umm al-Qura months have 29 or 30 days
    const total =
      this.hijri(now + (30 - parts.day) * DAY).month === 9 ? 30 : 29;
    const template = this.$("ramadan-day").dataset.template;
    this.set(
      "ramadan-day",
      template
        .replace("%{day}", this.number.format(parts.day))
        .replace("%{total}", this.number.format(total)),
    );
    this.$("ramadan-progress").style.width = `${(parts.day / total) * 100}%`;
    this.set("suhoor", format(times.fajr));
    this.set("iftar", format(times.maghrib));

    // fasting until Maghrib; otherwise count down to the end of suhoor (Fajr)
    const fasting =
      times.fajr && times.maghrib && now >= times.fajr && now < times.maghrib;
    this.fastUntil = fasting
      ? times.maghrib
      : now < times.fajr
        ? times.fajr
        : this.data.next_fajr;
    const fastLabel = this.$("fast-label");
    fastLabel.textContent = fasting
      ? fastLabel.dataset.iftar
      : fastLabel.dataset.suhoor;
  }

  hijri(ts) {
    if (!this.hijriParts) return null;
    const parts = Object.fromEntries(
      this.hijriParts.formatToParts(ts).map((p) => [p.type, p.value]),
    );
    return { day: parseInt(parts.day, 10), month: parseInt(parts.month, 10) };
  }

  // the only things updated every second
  renderCountdowns() {
    const now = Date.now();
    const left = this.nextAt
      ? Math.max(0, Math.ceil((this.nextAt - now) / 1000))
      : 0;
    const h = Math.floor(left / 3600);
    const m = Math.floor((left % 3600) / 60);
    const s = left % 60;
    this.set("countdown", this.calculation && !this.nextAt
      ? "--:--:--"
      : `${this.two.format(h)}:${this.two.format(m)}:${this.two.format(s)}`);
    this.set(
      "chip-countdown",
      `${this.number.format(h)}:${this.two.format(m)}:${this.two.format(s)}`,
    );

    if (this.root.hasAttribute("data-ramadan") && this.fastUntil) {
      const mins = Math.max(0, Math.ceil((this.fastUntil - now) / 60000));
      const fh = Math.floor(mins / 60);
      this.set(
        "fast-countdown",
        [fh && this.hours.format(fh), this.minutes.format(mins % 60)]
          .filter(Boolean)
          .join(" "),
      );
    }
  }
}

if (!customElements.get("prayer-times")) {
  customElements.define("prayer-times", PrayerTimes);
}
