// Plays the sounds anyone on the guild's screen sharing pages triggers, one at a
// time, and throws the sound's emoji up the screen. The volume is remembered for
// next time. Browsers only play audio once the page was clicked, so a hint asks
// for a click when a sound couldn't play.
//
// It's a button of the bar under the screens, filled while the sounds can be
// heard, and the Popovers hook opens it.

import {Mutes} from "../pointer/mutes"

const FLASH_MS = 600
const THROW_MS = 2_000
// Indigo like the flash on a played sound, see-through so the name stays readable
const PROGRESS_COLOR = "rgb(99 102 241 / 0.6)"

export function load(key, fallback) {
  try {
    return localStorage.getItem(key) ?? fallback
  } catch {
    return fallback
  }
}

export function save(key, value) {
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
    this.barToggle = this.el.querySelector("[data-sounds-bar-toggle]")
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
  },

  destroyed() {
    this.stop()
    document.removeEventListener("click", this.hideBlockedHint)
    window.removeEventListener("storage", this.syncVolume)
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
    this.js().setAttribute(this.barToggle, "aria-pressed", String(!this.muted))
    this.js().setAttribute(this.barToggle, "title", this.muted ? "Soundboard (muted)" : "Soundboard")
    if (this.audio) this.audio.volume = this.volume()
  },

  play({id, emoji, url, by}) {
    // Sounds from members this person muted don't play, or show, for them
    if (Mutes.has("sounds", by)) return

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
