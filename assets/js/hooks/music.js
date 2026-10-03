// Plays the song playing on the guild's page, at the same spot as everyone else.
// The jukebox on the server keeps the time: whenever something changes it says
// which song is playing, where it was and whether it's going, and this follows
// from there, counting the time since. A song that drifts off, like after the tab
// slept, is moved back in line.
//
// The volume is only for this page, and remembered for next time. Browsers only
// play audio once the page was clicked, so a hint asks for a click when the song
// couldn't play. It's a button of the bar under the screens, and the Popovers
// hook opens it.

import {load, save} from "./soundboard"

const TICK_MS = 250
// Checking every few ticks leaves a song that's buffering time to catch up
const DRIFT_CHECK_TICKS = 8
const MAX_DRIFT_S = 1

function formatTime(seconds) {
  const total = Math.floor(seconds)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const secs = String(total % 60).padStart(2, "0")

  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${secs}` : `${minutes}:${secs}`
}

export const Music = {
  mounted() {
    this.audio = this.el.querySelector("audio")
    this.muteButton = this.el.querySelector("[data-music-mute]")
    this.volumeInput = this.el.querySelector("[data-music-volume]")
    this.blockedHint = this.el.querySelector("[data-music-blocked]")
    this.sync = null
    this.ticks = 0

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

    // Other tabs of the page follow volume changes, so muting one mutes them all
    this.syncVolume = event => {
      if (event.key?.startsWith("music:")) this.loadVolume()
    }
    window.addEventListener("storage", this.syncVolume)

    // The click that hides the hint is the one browsers wanted to play the song
    this.unblock = () => {
      if (this.blockedHint.hidden) return
      this.blockedHint.hidden = true
      this.follow()
    }
    document.addEventListener("click", this.unblock)

    // The spot in the song can only be set once the browser knows how long it is
    this.audio.addEventListener("loadedmetadata", () => this.follow())

    this.handleEvent("music:sync", sync => {
      this.sync = {...sync, at: performance.now()}
      this.follow()
      this.renderProgress()
    })

    this.ticker = setInterval(() => this.tick(), TICK_MS)
  },

  destroyed() {
    clearInterval(this.ticker)
    this.audio.pause()
    document.removeEventListener("click", this.unblock)
    window.removeEventListener("storage", this.syncVolume)
  },

  // Ears hear loudness logarithmically, so the slider is squared like the soundboard's
  volume() {
    const value = Number(this.volumeInput.value)
    return this.muted ? 0 : value * value
  },

  loadVolume() {
    this.volumeInput.value = load("music:volume", this.volumeInput.defaultValue)
    this.muted = load("music:muted", "false") === "true"
    this.renderVolume()
  },

  saveVolume() {
    save("music:volume", this.volumeInput.value)
    save("music:muted", String(this.muted))
    this.renderVolume()
  },

  renderVolume() {
    this.muteButton.textContent = this.muted ? "🔇" : "🔊"
    this.muteButton.title = this.muted ? "Unmute music" : "Mute music"
    this.audio.volume = this.volume()
    // Browsers let muted audio play without a click
    this.audio.muted = this.volume() === 0
    if (this.audio.muted) this.blockedHint.hidden = true
    this.follow()
  },

  // Where the song is now, in seconds
  position() {
    const {position, playing, duration, at} = this.sync
    const ms = position + (playing ? performance.now() - at : 0)
    return Math.min(ms, duration ?? ms) / 1000
  },

  follow() {
    const sync = this.sync
    const audio = this.audio

    // Nothing playing, or the song is still downloading
    if (!sync?.src) {
      audio.pause()
      if (audio.hasAttribute("src")) {
        audio.removeAttribute("src")
        audio.load()
      }
      delete audio.dataset.track
      return
    }

    if (audio.dataset.track !== sync.track) {
      audio.dataset.track = sync.track
      audio.src = sync.src
    }

    if (
      audio.readyState >= HTMLMediaElement.HAVE_METADATA &&
      Math.abs(audio.currentTime - this.position()) > MAX_DRIFT_S
    ) {
      audio.currentTime = this.position()
    }

    // A song that ended waits for the jukebox to move on, instead of starting over
    if (sync.playing && audio.paused && !audio.ended) {
      audio.play().catch(error => {
        if (error.name === "NotAllowedError") this.blockedHint.hidden = false
      })
    } else if (!sync.playing && !audio.paused) {
      audio.pause()
    }
  },

  tick() {
    if (!this.sync) return
    this.renderProgress()

    this.ticks = (this.ticks + 1) % DRIFT_CHECK_TICKS
    if (this.ticks === 0 && this.sync.playing && !this.audio.paused) this.follow()
  },

  // The jukebox's time, so it moves even for those who muted the music
  renderProgress() {
    const bar = this.el.querySelector("[data-music-progress]")
    const elapsed = this.el.querySelector("[data-music-elapsed]")
    if (!bar || !elapsed || !this.sync?.duration) return

    const seconds = this.position()
    bar.style.width = `${Math.min((seconds * 1000) / this.sync.duration, 1) * 100}%`
    elapsed.textContent = formatTime(seconds)
  }
}
