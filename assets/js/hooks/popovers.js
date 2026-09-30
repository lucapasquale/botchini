// Popovers of the guild page, like the soundboard above the bar or the list of
// who's online. A button with `data-popover-toggle` opens the `data-popover` its
// `aria-controls` names, and only one is open at a time. Clicking outside of it
// or pressing Escape closes it.
//
// The attributes are set through `this.js()`, so they survive the LiveView
// re-rendering the popovers, like the soundboard during a cooldown

export const Popovers = {
  mounted() {
    this.openId = null

    this.onClick = event => {
      const toggle = event.target.closest?.("[data-popover-toggle]")
      if (toggle && this.el.contains(toggle)) {
        const id = toggle.getAttribute("aria-controls")
        this.open(this.openId === id ? null : id)
        return
      }

      // Clicks in the open popover are for its buttons
      const panel = this.openId && document.getElementById(this.openId)
      if (panel && !panel.contains(event.target)) this.open(null)
    }

    this.onKeydown = event => {
      if (event.key !== "Escape" || !this.openId) return
      const toggle = this.toggleFor(this.openId)
      this.open(null)
      toggle?.focus()
    }

    document.addEventListener("click", this.onClick)
    document.addEventListener("keydown", this.onKeydown)
  },

  destroyed() {
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("keydown", this.onKeydown)
  },

  toggleFor(id) {
    return this.el.querySelector(`[data-popover-toggle][aria-controls="${CSS.escape(id)}"]`)
  },

  open(id) {
    if (this.openId) this.setOpen(this.openId, false)
    this.openId = id
    if (id) this.setOpen(id, true)
  },

  setOpen(id, open) {
    const panel = document.getElementById(id)
    const toggle = this.toggleFor(id)
    if (!panel) return

    if (open) this.js().removeAttribute(panel, "hidden")
    else this.js().setAttribute(panel, "hidden", "")
    if (toggle) this.js().setAttribute(toggle, "aria-expanded", String(open))
    // Popovers that draw something, like the pointer's preview, need to be visible to measure it
    if (open) panel.dispatchEvent(new CustomEvent("popover:open", {bubbles: true}))
  }
}

// The chat's box empties once its message is sent, keeping the focus to write the next one
export const ChatForm = {
  mounted() {
    // The LiveView reads the message when the form is submitted, before this runs
    this.el.addEventListener("submit", () => setTimeout(() => this.el.reset()))
  }
}
