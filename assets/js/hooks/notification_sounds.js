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

export function playNotification(kind) {
  const volume = soundboardVolume()
  if (volume === 0) return

  try {
    context ??= new (window.AudioContext || window.webkitAudioContext)()
  } catch {
    return
  }

  // Browsers keep audio suspended until the page was clicked, and a chime that
  // plays long after the viewer came in would only confuse
  if (context.state !== "running") {
    context.resume().catch(() => {})
    return
  }

  const start = context.currentTime
  NOTES[kind].forEach((frequency, index) => {
    const at = start + index * NOTE_S
    const oscillator = context.createOscillator()
    const gain = context.createGain()

    oscillator.type = "sine"
    oscillator.frequency.value = frequency
    gain.gain.setValueAtTime(0.0001, at)
    gain.gain.linearRampToValueAtTime(GAIN * volume, at + ATTACK_S)
    gain.gain.exponentialRampToValueAtTime(0.0001, at + NOTE_S * 1.5)

    oscillator.connect(gain).connect(context.destination)
    oscillator.start(at)
    oscillator.stop(at + NOTE_S * 1.5)
  })
}
