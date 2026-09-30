// Members someone muted on the screen sharing pages: their pointers aren't drawn
// and their sounds aren't played. Kept in the browser, and shared between its tabs

const KEY = "screens:muted"
const listeners = new Set()

function read() {
  try {
    const ids = JSON.parse(localStorage.getItem(KEY) ?? "[]")
    return new Set(Array.isArray(ids) ? ids.map(String) : [])
  } catch {
    return new Set()
  }
}

let muted = read()

function notify() {
  listeners.forEach(listener => listener())
}

window.addEventListener("storage", event => {
  if (event.key !== KEY) return
  muted = read()
  notify()
})

export const Mutes = {
  has(userId) {
    return muted.has(String(userId))
  },

  toggle(userId) {
    const id = String(userId)
    if (muted.has(id)) muted.delete(id)
    else muted.add(id)

    try {
      localStorage.setItem(KEY, JSON.stringify([...muted]))
    } catch {
      // Storage can be blocked, the mute then only lasts until the page closes
    }
    notify()
  },

  // Calls `listener` whenever someone is muted or unmuted, returning how to stop
  subscribe(listener) {
    listeners.add(listener)
    return () => listeners.delete(listener)
  }
}

// Mute buttons in the list of who's online
export const OnlineMutes = {
  mounted() {
    this.el.addEventListener("click", event => {
      const button = event.target.closest("[data-mute-user]")
      if (button) Mutes.toggle(button.dataset.muteUser)
    })
    this.unsubscribe = Mutes.subscribe(() => this.render())
    this.render()
  },

  updated() {
    this.render()
  },

  destroyed() {
    this.unsubscribe()
  },

  render() {
    this.el.querySelectorAll("[data-mute-user]").forEach(button => {
      const isMuted = Mutes.has(button.dataset.muteUser)
      const name = button.dataset.name
      button.textContent = isMuted ? "🔇" : "🔈"
      button.setAttribute("aria-pressed", String(isMuted))
      button.title = isMuted
        ? `Unmute ${name}'s pointer and sounds`
        : `Mute ${name}'s pointer and sounds`
      button.closest("li")?.classList.toggle("opacity-50", isMuted)
    })
  }
}
