import test from "node:test"
import assert from "node:assert/strict"
import {NumberStepper} from "../../assets/js/number_stepper.js"

test("number steppers update the input, respect bounds and disabled state, and notify forms", () => {
  const previousObserver = globalThis.MutationObserver
  let observer, click, events = 0
  globalThis.MutationObserver = class {
    constructor(callback) { this.callback = callback; observer = this }
    observe() {}
    disconnect() { this.disconnected = true }
  }

  try {
    const down = {dataset: {step: "-1"}}
    const up = {dataset: {step: "1"}}
    const input = {
      value: "2",
      step: "1",
      min: "0",
      max: "3",
      readOnly: false,
      disabled: false,
      matches() { return this.disabled },
      get valueAsNumber() { return this.value === "" ? NaN : Number(this.value) },
      set valueAsNumber(value) { this.value = String(value) },
      stepUp() { this.value = String(Math.min(Number(this.value) + 1, Number(this.max))) },
      stepDown() { this.value = String(Math.max(Number(this.value) - 1, Number(this.min))) },
      dispatchEvent(event) { assert.equal(event.type, "input"); assert.equal(event.bubbles, true); events++ }
    }
    const el = {
      dataset: {},
      parentElement: {querySelector: () => input},
      querySelectorAll: () => [down, up],
      contains: button => button === down || button === up,
      addEventListener(_name, listener) { click = listener },
      removeEventListener() { click = null }
    }
    const hook = {...NumberStepper, el}
    const press = button => click({target: {closest: () => button}})

    hook.mounted()
    assert.equal(el.dataset.ready, "true")
    press(up)
    assert.equal(input.value, "3")
    press(up)
    assert.equal(events, 1)
    press(down)
    assert.equal(input.value, "2")
    assert.equal(events, 2)

    input.step = "any"
    input.value = "1.25"
    press(up)
    assert.equal(input.value, "2.25")
    input.value = "2.75"
    press(up)
    assert.equal(input.value, "3")
    input.value = ""
    press(down)
    assert.equal(input.value, "0")

    input.readOnly = true
    observer.callback()
    assert.equal(up.disabled, true)
    const before = events
    press(up)
    assert.equal(events, before)

    hook.destroyed()
    assert.equal(observer.disconnected, true)
    assert.equal(click, null)
  } finally {
    globalThis.MutationObserver = previousObserver
  }
})
