export const NumberStepper = {
  mounted() {
    this.input = this.el.parentElement.querySelector('input[type="number"]')
    this.buttons = this.el.querySelectorAll("button[data-step]")
    this.syncDisabled = () => {
      const disabled = this.input.matches(":disabled") || this.input.readOnly
      for (const button of this.buttons) button.disabled = disabled
    }
    this.onClick = event => {
      const button = event.target.closest("button[data-step]")
      if (!button || !this.el.contains(button) || this.input.matches(":disabled") || this.input.readOnly) return

      const direction = Number(button.dataset.step)
      const previous = this.input.value
      if (this.input.step === "any") {
        const current = Number.isFinite(this.input.valueAsNumber) ? this.input.valueAsNumber : 0
        let next = Number((current + direction).toPrecision(15))
        if (this.input.min !== "") next = Math.max(next, Number(this.input.min))
        if (this.input.max !== "") next = Math.min(next, Number(this.input.max))
        this.input.valueAsNumber = next
      } else if (direction > 0) {
        this.input.stepUp()
      } else {
        this.input.stepDown()
      }

      if (this.input.value !== previous) {
        this.input.dispatchEvent(new Event("input", {bubbles: true}))
      }
    }
    this.el.addEventListener("click", this.onClick)
    this.observer = new MutationObserver(this.syncDisabled)
    this.observer.observe(this.input, {attributes: true, attributeFilter: ["disabled", "readonly"]})
    this.syncDisabled()
    this.el.dataset.ready = "true"
  },

  destroyed() {
    this.observer.disconnect()
    this.el.removeEventListener("click", this.onClick)
  }
}
