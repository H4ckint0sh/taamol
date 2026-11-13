import test from "node:test"
import assert from "node:assert/strict"

let widgetClass

test("the site widget uses Växjö's date and timezone without requesting location", async () => {
  const saved = {
    HTMLElement: globalThis.HTMLElement,
    customElements: globalThis.customElements,
    document: globalThis.document,
    fetch: globalThis.fetch,
    Date: globalThis.Date,
    cancelAnimationFrame: globalThis.cancelAnimationFrame
  }
  let widget
  let requested
  const root = {dataset: {}, addEventListener() {}, removeEventListener() {}}
  const place = {textContent: ""}

  globalThis.HTMLElement = class {}
  globalThis.customElements = {
    get() { return undefined },
    define(_name, klass) { widgetClass = klass }
  }
  globalThis.document = {documentElement: {lang: "en"}}
  globalThis.cancelAnimationFrame = () => {}
  globalThis.fetch = async url => {
    requested = new URL(url, "https://example.test")
    return {ok: true, json: async () => ({times: {}})}
  }
  globalThis.Date = class extends saved.Date {
    constructor(...args) {
      super(...(args.length ? args : ["2026-03-28T23:30:00Z"]))
    }
  }

  try {
    await import("../../assets/js/prayer_times.js")
    widget = new widgetClass()
    widget.dataset = {latitude: "56.879", longitude: "14.8059", timezone: "Europe/Stockholm", city: "Växjö"}
    widget.querySelector = selector => {
      if (selector === "[data-role=root]") return root
      if (selector === "[data-role=place]") return place
      return null
    }
    widget.start = () => {}
    widget.render = () => {}
    widget.connectedCallback()
    await widget.tick()

    assert.equal(place.textContent, "Växjö")
    assert.equal(requested.searchParams.get("lat"), "56.879")
    assert.equal(requested.searchParams.get("lng"), "14.8059")
    assert.equal(requested.searchParams.get("date"), "2026-03-29")
    assert.equal(widget.timeFormat.resolvedOptions().timeZone, "Europe/Stockholm")
    assert.equal(widget.timeFormat.format(saved.Date.parse("2026-03-29T01:30:00Z")), "3:30 AM")
    widget.disconnectedCallback()
  } finally {
    widget?.stopTimers()
    Object.assign(globalThis, saved)
  }
})

test("the calculator arc updates with its data and only counts down to relevant prayers", async () => {
  const saved = {
    HTMLElement: globalThis.HTMLElement,
    customElements: globalThis.customElements,
    document: globalThis.document,
    cancelAnimationFrame: globalThis.cancelAnimationFrame,
    setInterval: globalThis.setInterval,
    clearInterval: globalThis.clearInterval,
    now: Date.now
  }
  let widget
  let interval
  let now = Date.parse("2026-03-29T22:30:00Z")
  const node = () => ({
    dataset: {}, style: {}, textContent: "", hidden: false, attributes: new Set(),
    setAttribute(name) { this.attributes.add(name) },
    removeAttribute(name) { this.attributes.delete(name) },
    toggleAttribute(name, value) { value ? this.attributes.add(name) : this.attributes.delete(name) },
    hasAttribute(name) { return this.attributes.has(name) }
  })
  const root = node()
  root.removeEventListener = () => {}
  const roles = Object.fromEntries(
    ["prayer-arc", "arc-unavailable", "until", "countdown", "next-at"].map(key => [key, node()])
  )
  roles.until.dataset.template = "until %{prayer}"
  const markers = Object.fromEntries(
    ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"].map(key => [key, node()])
  )
  const icons = Object.fromEntries(Object.keys(markers).map(key => {
    const icon = node()
    icon.dataset.label = key
    return [key, icon]
  }))

  globalThis.HTMLElement = class {}
  globalThis.customElements = {
    get() { return undefined },
    define(_name, klass) { widgetClass = klass }
  }
  globalThis.document = {documentElement: {lang: "en"}}
  globalThis.cancelAnimationFrame = () => {}
  globalThis.setInterval = callback => { interval = callback; return 1 }
  globalThis.clearInterval = () => {}
  Date.now = () => now

  try {
    widget = new widgetClass()
    widget.isConnected = true
    widget.dataset = {}
    widget.querySelector = selector => {
      if (selector === "[data-role=root]") return root
      const role = selector.match(/^\[data-role=(.+)\]$/)
      if (role) return roles[role[1]] || null
      const marker = selector.match(/^\[data-marker=(.+)\]$/)
      if (marker) return markers[marker[1]]
      const icon = selector.match(/^\[data-marker-icon="?([^"\]]+)"?\]$/)
      return icon ? icons[icon[1]] : null
    }
    widget.querySelectorAll = () => []
    widget.playArcIntro = function () { this.drawnFraction = this.targetFraction }
    widget.animateArc = function (target) { this.drawnFraction = target }

    const times = {
      fajr: now - 12 * 3600000, sunrise: now - 10 * 3600000,
      dhuhr: now - 6 * 3600000, asr: null,
      maghrib: now - 2 * 3600000, isha: now - 3600000
    }
    const data = {
      times, next_fajr: now + 5 * 3600000, date: "2026-03-30",
      timezone: "Europe/Stockholm", utc_offset: 0
    }
    const update = () => {
      const old = widget.dataset.calculation
      widget.dataset.calculation = JSON.stringify(data)
      widget.attributeChangedCallback("data-calculation", old, widget.dataset.calculation)
    }
    widget.dataset.calculation = JSON.stringify(data)
    widget.connectedCallback()

    assert.equal(widget.nextAt, data.next_fajr)
    assert.equal(roles.until.textContent, "until fajr")
    assert.equal(roles.countdown.textContent, "05:00:00")
    assert.equal(icons.asr.hidden, true)
    assert.equal(markers.asr.style.display, "none")
    assert.equal(roles["prayer-arc"].hidden, false)

    data.date = "2026-03-29"
    update()
    assert.equal(widget.nextAt, null)
    assert.equal(roles.countdown.textContent, "--:--:--")
    assert.equal(roles.until.textContent, "")

    data.date = "2026-03-31"
    data.times = {...times, fajr: now + 30 * 3600000, isha: now + 42 * 3600000, asr: now + 38 * 3600000}
    update()
    assert.equal(widget.nextAt, data.times.fajr)
    assert.equal(icons.asr.hidden, false)
    assert.equal(markers.asr.style.display, "")

    data.times.fajr = null
    update()
    assert.equal(roles["prayer-arc"].hidden, true)
    assert.equal(roles["arc-unavailable"].hidden, false)

    data.times = times
    data.timezone = null
    data.utc_offset = 2
    data.date = "2026-03-30"
    update()
    assert.equal(widget.nextAt, data.next_fajr)
    assert.equal(roles["prayer-arc"].hidden, false)
    assert.equal(roles["arc-unavailable"].hidden, true)

    data.timezone = "Europe/Stockholm"
    data.date = "2026-03-23"
    update()
    assert.equal(root.hidden, false)
    data.date = "2026-03-22"
    update()
    assert.equal(root.hidden, true)
    data.date = "2026-04-06"
    update()
    assert.equal(root.hidden, false)
    data.date = "2026-04-07"
    update()
    assert.equal(root.hidden, true)

    now += 24 * 3600000
    interval()
    assert.equal(root.hidden, false)

    data.timezone = null
    data.utc_offset = -4
    data.date = "2026-04-07"
    update()
    assert.equal(root.hidden, true)
  } finally {
    widget?.disconnectedCallback()
    Date.now = saved.now
    delete saved.now
    Object.assign(globalThis, saved)
  }
})
