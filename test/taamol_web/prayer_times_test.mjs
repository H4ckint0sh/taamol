import test from "node:test"
import assert from "node:assert/strict"

test("the site widget uses Växjö's date and timezone without requesting location", async () => {
  const saved = {
    HTMLElement: globalThis.HTMLElement,
    customElements: globalThis.customElements,
    document: globalThis.document,
    fetch: globalThis.fetch,
    Date: globalThis.Date,
    cancelAnimationFrame: globalThis.cancelAnimationFrame
  }
  let widgetClass
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
