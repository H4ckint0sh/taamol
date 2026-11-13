import test from "node:test"
import assert from "node:assert/strict"
import {openDateTimePicker} from "../../assets/js/date_time_picker.js"

test("clicking date and time inputs opens the native picker", () => {
  for (const type of ["date", "time", "datetime-local", "month", "week"]) {
    let opened = 0
    let prevented = false
    const input = {
      tagName: "INPUT", type, readOnly: false,
      matches: () => false,
      showPicker() { opened++ }
    }
    openDateTimePicker({
      target: input, detail: 1, button: 0,
      preventDefault() { prevented = true }
    })
    assert.equal(opened, 1, type)
    assert.equal(prevented, true, type)
  }
})

test("other inputs, keyboard clicks and unavailable pickers keep their normal behavior", () => {
  let opened = 0
  let prevented = 0
  const input = {
    tagName: "INPUT", type: "date", readOnly: false,
    matches: () => false,
    showPicker() { opened++ }
  }
  const click = (target, overrides = {}) => openDateTimePicker({
    target, detail: 1, button: 0,
    preventDefault() { prevented++ },
    ...overrides
  })

  click({...input, type: "text"})
  click({...input, readOnly: true})
  click({...input, matches: () => true})
  click({...input, showPicker: undefined})
  click(input, {detail: 0})
  click(input, {button: 2})
  click(input, {defaultPrevented: true})
  click({tagName: "BUTTON"})
  assert.equal(opened, 0)
  assert.equal(prevented, 0)

  const warn = console.warn
  let reported = false
  console.warn = () => { reported = true }
  try {
    click({...input, showPicker() { throw new Error("unavailable") }})
    assert.equal(reported, true)
    assert.equal(prevented, 0)
  } finally {
    console.warn = warn
  }
})
