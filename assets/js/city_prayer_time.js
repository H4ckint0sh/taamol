export function cityPrayerTime(timestamp, timezone, format) {
  if (timestamp === "-----") return timestamp
  const ms = Number(timestamp)
  if (!Number.isFinite(ms)) throw new Error("Invalid prayer time")
  if (format === "x") return String(ms)
  if (format === "X") return String(Math.floor(ms / 1000))

  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: timezone, hour: "2-digit", minute: "2-digit", hourCycle: "h23"
  }).formatToParts(new Date(ms))
  const hour = Number(parts.find(part => part.type === "hour").value)
  const minute = parts.find(part => part.type === "minute").value
  if (format === "24h") return `${String(hour).padStart(2, "0")}:${minute}`
  const hour12 = hour % 12 || 12
  return `${hour12}:${minute}${format === "12h" ? (hour < 12 ? " AM" : " PM") : ""}`
}

export const CityPrayerTime = {
  mounted() { this.renderTime() },
  updated() { this.renderTime() },
  renderTime() {
    try {
      this.el.textContent = cityPrayerTime(this.el.dataset.timestamp, this.el.dataset.timezone, this.el.dataset.format)
    } catch (error) {
      console.error("Could not display city prayer time", error)
      this.el.textContent = this.el.dataset.error
    }
  }
}

export const CityToday = {
  mounted() { this.updateDate() },
  updated() { this.updateDate() },
  updateDate() {
    const timezone = this.el.dataset.timezone
    if (this.el.dataset.autoDate !== "true" || timezone === this.lastTimezone) return
    try {
      const parts = new Intl.DateTimeFormat("en-CA", {
        timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit"
      }).formatToParts(new Date())
      const get = type => parts.find(part => part.type === type).value
      this.lastTimezone = timezone
      this.pushEvent("city-today", {timezone, date: `${get("year")}-${get("month")}-${get("day")}`})
    } catch (error) {
      console.error("Could not determine city date", error)
    }
  }
}

export const CitySearch = {
  mounted() {
    this.input = this.el.querySelector("#city-search-input")
    this.onInput = event => {
      if (event.target === this.input) this.pushEvent("city-query-changed", {query: this.input.value})
    }
    this.onFocus = event => {
      if (event.target === this.input && this.input.getAttribute("aria-expanded") === "false" &&
          this.input.value.trim().length >= 3) {
        this.pushEvent("city-query-changed", {query: this.input.value})
        this.pushEvent("search-cities", {city_search: {query: this.input.value}})
      }
    }
    this.onKeydown = event => {
      const first = this.el.querySelector("#city-search-results button")
      if (event.key === "Escape") {
        event.preventDefault()
        this.pushEvent("close-city-search", {})
        this.input.focus()
      } else if (event.target === this.input && event.key === "ArrowDown" && first) {
        event.preventDefault()
        first.focus()
      } else if (event.target === this.input && event.key === "Enter") {
        event.preventDefault()
        first?.click()
      }
    }
    this.onOutsideClick = event => {
      if (!this.el.contains(event.target) && this.input.getAttribute("aria-expanded") === "true") {
        this.pushEvent("close-city-search", {})
      }
    }
    this.el.addEventListener("input", this.onInput)
    this.el.addEventListener("focusin", this.onFocus)
    this.el.addEventListener("keydown", this.onKeydown)
    document.addEventListener("click", this.onOutsideClick)
  },
  destroyed() {
    this.el.removeEventListener("input", this.onInput)
    this.el.removeEventListener("focusin", this.onFocus)
    this.el.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onOutsideClick)
  }
}
