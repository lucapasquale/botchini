// Short chimes for the broadcaster: two rising notes when a viewer joins and two
// falling ones when they leave. They're synthesized, so there's nothing to load,
// and they follow the volume and mute the soundboard remembers.

const NOTES = {
  join: [659.25, 880],
  leave: [523.25, 392]
}
const NOTE_S = 0.12
const ATTACK_S = 0.01
// Chimes are a hint and shouldn't cover the stream's own sound, so they stay quieter than sounds
const GAIN = 0.3
// The broadcaster's other tabs are told about the same viewer at about the same time
const SAME_CHIME_MS = 1_000

let context = null

function soundboardVolume() {
  try {
    if (localStorage.getItem("soundboard:muted") === "true") return 0

    const volume = Number(localStorage.getItem("soundboard:volume") ?? 0.7)
    return Number.isFinite(volume) ? Math.min(Math.max(volume, 0), 1) : 0.7
  } catch {
    return 0.7
  }
}

// Browsers keep audio suspended until the page was clicked, and a chime that
// plays long after the viewer came in would only confuse
function runningContext() {
  try {
    context ??= new (window.AudioContext || window.webkitAudioContext)()
  } catch {
    return null
  }

  if (context.state === "running") return context

  context.resume().catch(() => {})
  return null
}

export function playNotification(kind) {
  const volume = soundboardVolume()
  const audio = volume > 0 && runningContext()
  if (!audio) return

  // Only the first tab that can play it chimes, as the broadcaster usually has
  // their own page and the server's page open. Tabs that can't play sound don't
  // take the lock, so they never silence the others
  if (!navigator.locks) return chime(audio, kind, volume)

  navigator.locks
    .request(`botchini:chime:${kind}`, {ifAvailable: true}, async lock => {
      if (!lock) return

      chime(audio, kind, volume)
      await new Promise(resolve => setTimeout(resolve, SAME_CHIME_MS))
    })
    .catch(() => {})
}

function chime(audio, kind, volume) {
  const start = audio.currentTime

  NOTES[kind].forEach((frequency, index) => {
    const at = start + index * NOTE_S
    const oscillator = audio.createOscillator()
    const gain = audio.createGain()

    oscillator.type = "sine"
    oscillator.frequency.value = frequency
    gain.gain.setValueAtTime(0.0001, at)
    gain.gain.linearRampToValueAtTime(GAIN * volume, at + ATTACK_S)
    gain.gain.exponentialRampToValueAtTime(0.0001, at + NOTE_S * 1.5)

    oscillator.connect(gain).connect(audio.destination)
    oscillator.start(at)
    oscillator.stop(at + NOTE_S * 1.5)
  })
}
