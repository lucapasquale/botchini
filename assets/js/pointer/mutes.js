// Members someone muted on the screen sharing pages, separately for their sounds
// and their pointer, which stop playing or being drawn for them. Kept in the
// browser, and shared between its tabs

const KINDS = ["sounds", "pointer"]
const key = kind => `screens:muted:${kind}`
// Before sounds and pointers were muted separately, one list muted both
const OLD_KEY = "screens:muted"
const listeners = new Set()

function read(storageKey) {
  try {
    const ids = JSON.parse(localStorage.getItem(storageKey) ?? "[]")
    return new Set(Array.isArray(ids) ? ids.map(String) : [])
  } catch {
    return new Set()
  }
}

function write(kind) {
  try {
    localStorage.setItem(key(kind), JSON.stringify([...muted[kind]]))
  } catch {
    // Storage can be blocked, the mute then only lasts until the page closes
  }
}

const muted = Object.fromEntries(KINDS.map(kind => [kind, read(key(kind))]))

const old = read(OLD_KEY)
if (old.size > 0) {
  for (const kind of KINDS) {
    old.forEach(id => muted[kind].add(id))
    write(kind)
  }
  try {
    localStorage.removeItem(OLD_KEY)
  } catch {
    // Nothing to clean up then
  }
}

function notify() {
  listeners.forEach(listener => listener())
}

window.addEventListener("storage", event => {
  const kind = KINDS.find(k => event.key === key(k))
  if (!kind) return
  muted[kind] = read(key(kind))
  notify()
})

export const Mutes = {
  // `kind` is "sounds" or "pointer"
  has(kind, userId) {
    return muted[kind].has(String(userId))
  },

  toggle(kind, userId) {
    const id = String(userId)
    if (muted[kind].has(id)) muted[kind].delete(id)
    else muted[kind].add(id)
    write(kind)
    notify()
  },

  // Calls `listener` whenever someone is muted or unmuted, returning how to stop
  subscribe(listener) {
    listeners.add(listener)
    return () => listeners.delete(listener)
  }
}

const LABELS = {
  sounds: {on: "🔊", off: "🔇", what: "sounds"},
  pointer: {on: "✨", off: "🚫", what: "pointer"}
}

// Mute buttons in the list of who's online
export const OnlineMutes = {
  mounted() {
    this.el.addEventListener("click", event => {
      const button = event.target.closest("[data-mute-user]")
      if (button) Mutes.toggle(button.dataset.mute, button.dataset.muteUser)
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
      const kind = button.dataset.mute
      const label = LABELS[kind]
      const isMuted = Mutes.has(kind, button.dataset.muteUser)
      const name = button.dataset.name
      button.textContent = isMuted ? label.off : label.on
      button.setAttribute("aria-pressed", String(isMuted))
      button.title = isMuted ? `Unmute ${name}'s ${label.what}` : `Mute ${name}'s ${label.what}`
    })

    // Members muted for everything fade out in the list
    this.el.querySelectorAll("li").forEach(item => {
      const buttons = [...item.querySelectorAll("[data-mute-user]")]
      const allMuted = buttons.length > 0 && buttons.every(b => b.getAttribute("aria-pressed") === "true")
      item.classList.toggle("opacity-50", allMuted)
    })
  }
}
