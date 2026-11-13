const pickerTypes = new Set(["date", "time", "datetime-local", "month", "week"])

export function openDateTimePicker(event) {
  const input = event.target
  if (event.defaultPrevented || event.detail === 0 || event.button !== 0 ||
      input?.tagName !== "INPUT" || !pickerTypes.has(input.type) ||
      input.readOnly || input.matches(":disabled") || typeof input.showPicker !== "function") return

  try {
    input.showPicker()
    event.preventDefault()
  } catch (error) {
    console.warn("Could not open the native date or time picker", error)
  }
}
