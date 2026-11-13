import test from "node:test"
import assert from "node:assert/strict"
import {cityPrayerTime, CityPrayerTime, CityToday, CitySearch} from "../../assets/js/city_prayer_time.js"

test("formats each prayer in the city's time zone across a DST change", () => {
  const before = Date.parse("2026-03-29T00:30:00Z")
  const after = Date.parse("2026-03-29T01:30:00Z")

  assert.equal(cityPrayerTime(String(before), "Europe/Stockholm", "24h"), "01:30")
  assert.equal(cityPrayerTime(String(after), "Europe/Stockholm", "24h"), "03:30")
  assert.equal(cityPrayerTime(String(after), "Asia/Tehran", "12h"), "5:00 AM")
  assert.equal(cityPrayerTime(String(after), "Europe/Stockholm", "X"), String(after / 1000))
  assert.equal(cityPrayerTime("-----", "Europe/Stockholm", "24h"), "-----")
  assert.throws(() => cityPrayerTime(String(after), "Invalid/Zone", "24h"))
})

test("updates the displayed time when the date or zone changes", () => {
  const hook = {
    ...CityPrayerTime,
    el: {dataset: {timestamp: String(Date.parse("2026-03-29T01:30:00Z")), timezone: "Europe/Stockholm", format: "24h"}}
  }
  hook.mounted()
  assert.equal(hook.el.textContent, "03:30")
  hook.el.dataset.timezone = "Asia/Tehran"
  hook.updated()
  assert.equal(hook.el.textContent, "05:00")
})

test("requests today's city date once per zone unless the user chose a date", () => {
  const events = []
  const hook = {
    ...CityToday,
    el: {dataset: {timezone: "Europe/Stockholm", autoDate: "true"}},
    pushEvent: (name, data) => events.push({name, data})
  }
  hook.mounted()
  hook.updated()
  assert.equal(events.length, 1)
  assert.equal(events[0].name, "city-today")
  assert.equal(events[0].data.timezone, "Europe/Stockholm")
  assert.match(events[0].data.date, /^\d{4}-\d{2}-\d{2}$/)
  hook.el.dataset.autoDate = "false"
  hook.el.dataset.timezone = "Asia/Tehran"
  hook.updated()
  assert.equal(events.length, 1)
})

test("city search invalidates old results and supports keyboard selection", () => {
  const events = []
  const handlers = {}
  let clicked = false
  let focused = false
  const input = {
    value: "Sto",
    getAttribute: () => "true",
    focus() { focused = true }
  }
  const result = {
    focus() { focused = true },
    click() { clicked = true }
  }
  const el = {
    querySelector(selector) { return selector === "#city-search-input" ? input : result },
    addEventListener(name, callback) { handlers[name] = callback },
    removeEventListener(name) { delete handlers[name] },
    contains(target) { return target === input }
  }
  const previousDocument = globalThis.document
  globalThis.document = {addEventListener() {}, removeEventListener() {}}

  try {
    const hook = {...CitySearch, el, pushEvent: (name, data) => events.push({name, data})}
    hook.mounted()
    handlers.input({target: input})
    assert.deepEqual(events[0], {name: "city-query-changed", data: {query: "Sto"}})

    let prevented = false
    handlers.keydown({target: input, key: "Enter", preventDefault() { prevented = true }})
    assert.equal(prevented, true)
    assert.equal(clicked, true)

    handlers.keydown({target: input, key: "Escape", preventDefault() {}})
    assert.equal(events.at(-1).name, "close-city-search")
    assert.equal(focused, true)
    hook.destroyed()
    assert.deepEqual(handlers, {})
  } finally {
    globalThis.document = previousDocument
  }
})
