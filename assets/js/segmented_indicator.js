const selectedOption = ':scope > [aria-current="page"], :scope > [aria-selected="true"], :scope > [aria-pressed="true"]'

export const SegmentedIndicator = {
  mounted() {
    this.group = this.el.parentElement
    this.frame = null
    this.schedule = () => {
      if (this.frame !== null) return
      this.frame = requestAnimationFrame(() => {
        this.frame = null
        this.positionIndicator()
      })
    }

    this.mutations = new MutationObserver(() => {
      this.observeOptions()
      this.schedule()
    })
    this.mutations.observe(this.group, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["aria-current", "aria-selected", "aria-pressed"]
    })

    if (typeof ResizeObserver !== "undefined") {
      this.resize = new ResizeObserver(this.schedule)
      this.resize.observe(this.group)
      this.observeOptions()
    }
    window.addEventListener("resize", this.schedule)
    this.positionIndicator()
  },

  observeOptions() {
    if (!this.resize) return
    for (const child of this.group.children) {
      if (child !== this.el) this.resize.observe(child)
    }
  },

  positionIndicator() {
    const selected = this.group.querySelector(selectedOption)
    if (!selected) {
      this.el.dataset.ready = "false"
      this.el.style.opacity = "0"
      return
    }

    this.el.style.width = `${selected.offsetWidth}px`
    this.el.style.height = `${selected.offsetHeight}px`
    this.el.style.transform = `translate(${selected.offsetLeft}px, ${selected.offsetTop}px)`
    this.el.dataset.ready = "true"
    this.el.style.opacity = "1"
  },

  destroyed() {
    this.mutations.disconnect()
    if (this.resize) this.resize.disconnect()
    window.removeEventListener("resize", this.schedule)
    if (this.frame !== null) cancelAnimationFrame(this.frame)
  }
}
