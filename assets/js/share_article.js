export const ShareArticle = {
  mounted() {
    this.label = this.el.querySelector("[data-label]")
    this.originalLabel = this.label.textContent
    this.onClick = async () => {
      const url = window.location.href

      if (navigator.share) {
        try {
          await navigator.share({title: this.el.dataset.title, url})
          return
        } catch (error) {
          if (error.name === "AbortError") return
          console.warn("Native sharing failed:", error)
        }
      }

      if (navigator.clipboard?.writeText) {
        try {
          await navigator.clipboard.writeText(url)
          this.label.textContent = this.el.dataset.copied
          clearTimeout(this.resetTimer)
          this.resetTimer = setTimeout(() => {
            this.label.textContent = this.originalLabel
          }, 2000)
          return
        } catch (error) {
          console.warn("Copying the share link failed:", error)
        }
      }

      window.prompt(this.el.dataset.copyPrompt, url)
    }

    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    clearTimeout(this.resetTimer)
  }
}
