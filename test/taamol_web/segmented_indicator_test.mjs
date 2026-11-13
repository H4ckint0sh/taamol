import test from "node:test"
import assert from "node:assert/strict"
import {SegmentedIndicator} from "../../assets/js/segmented_indicator.js"

test("tracks selection, resizing, and an unselected custom value", () => {
  const previous = {
    MutationObserver: globalThis.MutationObserver,
    ResizeObserver: globalThis.ResizeObserver,
    window: globalThis.window,
    requestAnimationFrame: globalThis.requestAnimationFrame,
    cancelAnimationFrame: globalThis.cancelAnimationFrame
  }
  let mutation, resize, frame, removed = false
  class Observer {
    constructor(callback) { this.callback = callback }
    observe() {}
    disconnect() { this.disconnected = true }
  }
  globalThis.MutationObserver = class extends Observer {
    constructor(callback) { super(callback); mutation = this }
  }
  globalThis.ResizeObserver = class extends Observer {
    constructor(callback) { super(callback); resize = this }
  }
  globalThis.window = {
    addEventListener() {},
    removeEventListener() { removed = true }
  }
  globalThis.requestAnimationFrame = callback => { frame = callback; return 1 }
  globalThis.cancelAnimationFrame = () => {}

  try {
    const first = {offsetLeft: 130, offsetTop: 4, offsetWidth: 75, offsetHeight: 24}
    const second = {offsetLeft: 4, offsetTop: 4, offsetWidth: 120, offsetHeight: 24}
    let selected = first
    const group = {children: [first, second], querySelector: () => selected}
    const hook = {...SegmentedIndicator, el: {parentElement: group, dataset: {}, style: {}}}

    hook.mounted()
    assert.equal(hook.el.style.transform, "translate(130px, 4px)")
    assert.equal(hook.el.style.width, "75px")
    assert.equal(hook.el.dataset.ready, "true")

    selected = second
    mutation.callback()
    frame()
    assert.equal(hook.el.style.transform, "translate(4px, 4px)")
    assert.equal(hook.el.style.width, "120px")

    second.offsetWidth = 100
    resize.callback()
    frame()
    assert.equal(hook.el.style.width, "100px")

    selected = null
    mutation.callback()
    frame()
    assert.equal(hook.el.dataset.ready, "false")
    assert.equal(hook.el.style.opacity, "0")

    hook.destroyed()
    assert.equal(mutation.disconnected, true)
    assert.equal(resize.disconnected, true)
    assert.equal(removed, true)
  } finally {
    Object.assign(globalThis, previous)
  }
})
