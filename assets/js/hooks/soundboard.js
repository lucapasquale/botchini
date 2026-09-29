// Plays the sounds anyone on the guild's screen sharing pages triggers, one at a
// time, and throws the sound's emoji up the screen. The volume is remembered for
// next time. Browsers only play audio once the page was clicked, so a hint asks
// for a click when a sound couldn't play.
//
// The soundboard floats over the page as a button members drag anywhere on the
// screen, which opens the sounds next to it. Its place is remembered too.

const FLASH_MS = 600
const THROW_MS = 2_000
// Indigo like the flash on a played sound, see-through so the name stays readable
const PROGRESS_COLOR = "rgb(99 102 241 / 0.6)"

// Size of the floating button, how far it keeps from the screen's edges, and how
// far a press moves before it's a drag instead of a click
const BUTTON_PX = 56
const MARGIN_PX = 12
const DRAG_THRESHOLD_PX = 5
// Matches the panel's max-h-[70dvh]
const MAX_HEIGHT_RATIO = 0.7
const MIN_VISIBLE_SOUNDS = 4

const clamp = (value, min, max) => Math.min(Math.max(value, min), Math.max(min, max))

function savedPosition() {
  try {
    const {x, y} = JSON.parse(load("soundboard:position", "null")) ?? {}
    return Number.isFinite(x) && Number.isFinite(y) ? {x, y} : null
  } catch {
    return null
  }
}

function load(key, fallback) {
  try {
    return localStorage.getItem(key) ?? fallback
  } catch {
    return fallback
  }
}

function save(key, value) {
  try {
    localStorage.setItem(key, value)
  } catch {
    // Storage can be blocked, the setting just isn't remembered then
  }
}

export const Soundboard = {
  mounted() {
    this.muteButton = this.el.querySelector("[data-sounds-mute]")
    this.volumeInput = this.el.querySelector("[data-sounds-volume]")
    this.blockedHint = this.el.querySelector("[data-sounds-blocked]")
    this.audio = null

    this.loadVolume()

    this.volumeInput.addEventListener("input", () => {
      this.muted = Number(this.volumeInput.value) === 0
      this.saveVolume()
    })
    this.muteButton.addEventListener("click", () => {
      this.muted = !this.muted
      // Unmuting from zero would stay silent, so it goes back to a middle volume
      if (!this.muted && Number(this.volumeInput.value) === 0) this.volumeInput.value = "0.5"
      this.saveVolume()
    })

    // Other tabs of the soundboard follow volume changes, so muting one mutes them all
    this.syncVolume = event => {
      if (event.key?.startsWith("soundboard:")) this.loadVolume()
    }
    window.addEventListener("storage", this.syncVolume)

    this.hideBlockedHint = () => (this.blockedHint.hidden = true)
    document.addEventListener("click", this.hideBlockedHint)

    this.handleEvent("sound:play", sound => this.play(sound))
    this.handleEvent("sound:stop", () => this.stop())

    this.mountFloating()
  },

  destroyed() {
    this.stop()
    document.removeEventListener("click", this.hideBlockedHint)
    window.removeEventListener("storage", this.syncVolume)
    window.removeEventListener("resize", this.onResize)
  },

  mountFloating() {
    this.card = this.el.querySelector("[data-sounds-card]")
    this.toggle = this.el.querySelector("[data-sounds-toggle]")
    this.panel = this.el.querySelector("[data-sounds-panel]")
    this.scroll = this.el.querySelector("[data-sounds-scroll]")
    this.resizer = this.el.querySelector("[data-sounds-resize]")
    this.open = false
    // Height the member resized the sounds to, or null to fit them up to the tallest
    this.panelHeight = Number(load("soundboard:height", "")) || null
    this.resizer.addEventListener("pointerdown", event => this.startResize(event))

    // The button's top left corner, starting on the right just below the header
    const saved = savedPosition()
    const header = document.querySelector("header")
    this.x = saved?.x ?? window.innerWidth - BUTTON_PX - MARGIN_PX
    this.y = saved?.y ?? (header ? header.getBoundingClientRect().bottom : 0) + MARGIN_PX

    this.el.querySelectorAll("[data-drag-handle]").forEach(handle => {
      handle.addEventListener("pointerdown", event => this.startDrag(event))
    })
    // A drag ends with a click on the button, which mustn't open or close it
    this.toggle.addEventListener("click", () => {
      if (this.dragged) return
      this.setOpen(!this.open)
    })

    this.onResize = () => {
      this.applyHeight()
      this.place()
    }
    window.addEventListener("resize", this.onResize)

    this.place()
    this.js().removeClass(this.el, "invisible")
  },

  setOpen(open) {
    this.open = open
    // The sounds open towards the middle of the screen, so they fit next to the button
    this.openLeft = this.x + BUTTON_PX / 2 > window.innerWidth / 2
    this.openUp = this.y + BUTTON_PX / 2 > window.innerHeight / 2

    if (open) this.js().removeAttribute(this.panel, "hidden")
    else this.js().setAttribute(this.panel, "hidden", "")
    this.js().setAttribute(this.toggle, "aria-expanded", String(open))
    const direction = this.openLeft ? "row-reverse" : "row"
    const align = this.openUp ? "flex-end" : "flex-start"
    this.js().setAttribute(this.card, "style", `flex-direction: ${direction}; align-items: ${align}`)
    // The grip goes on the edge away from the button, which is the one that moves
    this.js().setAttribute(this.resizer, "style", `order: ${this.openUp ? -1 : 1}`)
    this.applyHeight()
    this.place()
  },

  // The tallest is what the sounds get without resizing, the shortest still shows 4 of them
  maxHeight() {
    return window.innerHeight * MAX_HEIGHT_RATIO
  },

  minHeight() {
    const fourth = this.el.querySelectorAll("[data-sound]")[MIN_VISIBLE_SOUNDS - 1]
    if (!fourth) return 0

    const panel = this.panel.getBoundingClientRect()
    const scroll = this.scroll.getBoundingClientRect()
    const fourthBottom = fourth.getBoundingClientRect().bottom + this.scroll.scrollTop
    const padding = parseFloat(getComputedStyle(this.scroll).paddingBottom)

    return fourthBottom - panel.top + padding + (panel.bottom - scroll.bottom)
  },

  applyHeight() {
    if (!this.open || this.panelHeight === null) {
      this.js().removeAttribute(this.panel, "style")
      return
    }

    const height = clamp(this.panelHeight, this.minHeight(), this.maxHeight())
    this.js().setAttribute(this.panel, "style", `height: ${height}px`)
  },

  startResize(event) {
    if (event.button !== 0) return
    event.preventDefault()

    const startY = event.clientY
    const startHeight = this.panel.getBoundingClientRect().height

    const move = moveEvent => {
      const dy = moveEvent.clientY - startY
      // Pulling the grip away from the button makes the sounds taller
      const height = startHeight + (this.openUp ? -dy : dy)
      this.panelHeight = clamp(height, this.minHeight(), this.maxHeight())
      this.applyHeight()
      this.place()
    }

    const end = () => {
      window.removeEventListener("pointermove", move)
      window.removeEventListener("pointerup", end)
      window.removeEventListener("pointercancel", end)
      save("soundboard:height", String(Math.round(this.panelHeight)))
    }

    window.addEventListener("pointermove", move)
    window.addEventListener("pointerup", end)
    window.addEventListener("pointercancel", end)
  },

  // Where the whole soundboard goes for the button to be at x and y, kept on the screen
  place() {
    const {width, height} = this.el.getBoundingClientRect()
    const left = this.open && this.openLeft ? this.x + BUTTON_PX - width : this.x
    const top = this.open && this.openUp ? this.y + BUTTON_PX - height : this.y

    this.moveTo(left, top)
  },

  moveTo(left, top) {
    const {width, height} = this.el.getBoundingClientRect()
    left = clamp(left, MARGIN_PX, window.innerWidth - width - MARGIN_PX)
    top = clamp(top, MARGIN_PX, window.innerHeight - height - MARGIN_PX)
    this.js().setAttribute(this.el, "style", `left: ${left}px; top: ${top}px`)

    // The button stays where it ended up, e.g. pushed away from an edge
    const button = this.toggle.getBoundingClientRect()
    this.x = button.left
    this.y = button.top
  },

  startDrag(event) {
    // Buttons inside the handles, like Stop, are still clicked normally
    const button = event.target.closest("button")
    if (event.button !== 0 || (button && button !== this.toggle)) return

    const start = {x: event.clientX, y: event.clientY}
    const origin = this.el.getBoundingClientRect()
    this.dragged = false

    const move = moveEvent => {
      const dx = moveEvent.clientX - start.x
      const dy = moveEvent.clientY - start.y
      if (!this.dragged && Math.hypot(dx, dy) < DRAG_THRESHOLD_PX) return

      this.dragged = true
      this.moveTo(origin.left + dx, origin.top + dy)
    }

    const end = () => {
      window.removeEventListener("pointermove", move)
      window.removeEventListener("pointerup", end)
      window.removeEventListener("pointercancel", end)
      if (this.dragged) save("soundboard:position", JSON.stringify({x: this.x, y: this.y}))
      // Cleared after the click that follows the drag
      setTimeout(() => (this.dragged = false))
    }

    window.addEventListener("pointermove", move)
    window.addEventListener("pointerup", end)
    window.addEventListener("pointercancel", end)
  },

  // Ears hear loudness logarithmically, so the slider is squared to make its
  // low end quiet enough for 10% to sound very different from 90%
  volume() {
    const value = Number(this.volumeInput.value)
    return this.muted ? 0 : value * value
  },

  loadVolume() {
    this.volumeInput.value = load("soundboard:volume", this.volumeInput.defaultValue)
    this.muted = load("soundboard:muted", "false") === "true"
    this.renderVolume()
  },

  saveVolume() {
    save("soundboard:volume", this.volumeInput.value)
    save("soundboard:muted", String(this.muted))
    this.renderVolume()
  },

  renderVolume() {
    this.muteButton.textContent = this.muted ? "🔇" : "🔊"
    this.muteButton.title = this.muted ? "Unmute sounds" : "Mute sounds"
    if (this.audio) this.audio.volume = this.volume()
  },

  play({id, emoji, url}) {
    this.flash(id)
    this.throwEmoji(emoji)

    // A new sound cuts off the one playing
    this.stop()
    const audio = new Audio(url)
    audio.volume = this.volume()
    audio.addEventListener("ended", () => {
      if (this.audio === audio) this.stop()
    })
    this.audio = audio
    this.trackProgress(id, audio)

    audio.play().catch(error => {
      if (error.name === "NotAllowedError") this.blockedHint.hidden = false
    })
  },

  stop() {
    cancelAnimationFrame(this.progressFrame)
    this.el.querySelectorAll("[data-sound]").forEach(button => (button.style.backgroundImage = ""))
    if (!this.audio) return

    this.audio.pause()
    this.audio = null
  },

  // The playing sound's button fills up from the left like a progress bar. It's
  // redrawn every frame, so it also survives the button being re-rendered
  trackProgress(id, audio) {
    const tick = () => {
      if (this.audio !== audio) return

      const button = this.el.querySelector(`[data-sound="${CSS.escape(id)}"]`)
      const percent = audio.duration ? (audio.currentTime / audio.duration) * 100 : 0
      if (button) {
        button.style.backgroundImage =
          `linear-gradient(to right, ${PROGRESS_COLOR} ${percent}%, transparent ${percent}%)`
      }

      this.progressFrame = requestAnimationFrame(tick)
    }

    this.progressFrame = requestAnimationFrame(tick)
  },

  flash(id) {
    const button = this.el.querySelector(`[data-sound="${CSS.escape(id)}"]`)
    if (!button) return

    button.classList.add("ring-2", "ring-indigo-400")
    clearTimeout(button.flashTimeout)
    button.flashTimeout = setTimeout(
      () => button.classList.remove("ring-2", "ring-indigo-400"),
      FLASH_MS
    )
  },

  // The emoji flies from the bottom of the screen to around its middle, then fades
  throwEmoji(emoji) {
    const el = document.createElement("div")
    el.textContent = emoji
    el.setAttribute("aria-hidden", "true")
    // A little randomness so sounds played in a row don't stack on each other
    const left = 30 + Math.random() * 40
    const spin = Math.random() * 40 - 20
    Object.assign(el.style, {
      position: "fixed",
      left: `${left}vw`,
      bottom: "0",
      fontSize: "6rem",
      lineHeight: "1",
      pointerEvents: "none",
      zIndex: "50"
    })
    document.body.appendChild(el)

    const animation = el.animate(
      [
        {transform: "translate(-50%, 100%) scale(0.6) rotate(0deg)", opacity: 1},
        {transform: `translate(-50%, -45vh) scale(1.3) rotate(${spin}deg)`, opacity: 1, offset: 0.35},
        {transform: `translate(-50%, -50vh) scale(1.4) rotate(${spin}deg)`, opacity: 0}
      ],
      {duration: THROW_MS, easing: "ease-out"}
    )
    animation.onfinish = () => el.remove()
  }
}
