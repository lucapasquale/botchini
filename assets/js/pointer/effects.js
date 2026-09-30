// Special effects set off by drawing shapes. Each is drawn on the pointers'
// canvas around where the shape was, found again every frame so it follows the
// stream or page it was drawn on

import {star} from "./render"

const DURATIONS = {
  lightning: 700,
  star: 1400,
  heart: 2200,
  circle: 1000,
  spiral: 1200,
  target: 1400,
  infinity: 1600
}

const random = (min, max) => min + Math.random() * (max - min)

// A jagged bolt from above the screen down to the target, by splitting the line
// in halves and pushing each middle sideways a little less every time
function bolt(fromX, fromY, toX, toY) {
  let points = [{x: fromX, y: fromY}, {x: toX, y: toY}]
  let spread = Math.hypot(toX - fromX, toY - fromY) / 5

  for (let level = 0; level < 6; level++) {
    const next = [points[0]]
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1]
      const b = points[i]
      next.push({x: (a.x + b.x) / 2 + random(-spread, spread), y: (a.y + b.y) / 2}, b)
    }
    points = next
    spread /= 2
  }

  return points
}

function create(name) {
  const effect = {name, born: performance.now(), duration: DURATIONS[name]}

  switch (name) {
    case "star":
      effect.particles = Array.from({length: 18}, () => {
        const angle = random(0, 2 * Math.PI)
        const speed = random(250, 650)
        return {
          vx: Math.cos(angle) * speed,
          vy: Math.sin(angle) * speed,
          size: random(8, 16),
          color: Math.random() < 0.6 ? "#fde047" : "#ffffff",
          spin: random(-6, 6)
        }
      })
      break

    case "heart":
      effect.particles = Array.from({length: 16}, () => ({
        dx: random(-60, 60),
        speed: random(90, 190),
        sway: random(15, 40),
        phase: random(0, 2 * Math.PI),
        size: random(22, 42),
        delay: random(0, 350),
        emoji: ["❤️", "💖", "💕", "💗"][Math.floor(random(0, 4))]
      }))
      break

    case "lightning":
      effect.offset = random(-160, 160)
      effect.branches = Math.random() < 0.7 ? 2 : 1
      break

    case "infinity":
      trip()
      break

    case "spiral":
      effect.particles = Array.from({length: 28}, (_, i) => ({
        angle: (i / 28) * 2 * Math.PI,
        color: `hsl(${(i / 28) * 360} 95% 65%)`
      }))
      wobble()
      break
  }

  return effect
}

// Everything on the page spins for a moment, as if dizzy
function wobble() {
  const main = document.querySelector("main")
  if (!main || !main.animate) return

  main.animate(
    [
      {transform: "rotate(0deg) scale(1)"},
      {transform: "rotate(3deg) scale(0.98)"},
      {transform: "rotate(-3deg) scale(0.98)"},
      {transform: "rotate(2deg) scale(0.99)"},
      {transform: "rotate(-1deg) scale(1)"},
      {transform: "rotate(0deg) scale(1)"}
    ],
    {duration: DURATIONS.spiral, easing: "ease-in-out"}
  )
}

// The page's colors go upside down and around, like a glitch in the matrix
function trip() {
  const main = document.querySelector("main")
  if (!main || !main.animate) return

  main.animate(
    [
      {filter: "invert(0) hue-rotate(0deg)"},
      {filter: "invert(1) hue-rotate(180deg)", offset: 0.15},
      {filter: "invert(1) hue-rotate(360deg)", offset: 0.6},
      {filter: "invert(0) hue-rotate(360deg)"}
    ],
    {duration: DURATIONS.infinity, easing: "ease-in-out"}
  )
}

// A crosshair spinning in and locking onto the spot, like in a shooter
function drawTarget(ctx, at, t) {
  const lock = Math.min(1, t / 0.45)
  const eased = 1 - (1 - lock) ** 3
  const radius = 160 - 110 * eased
  const fade = t < 0.8 ? 1 : 1 - (t - 0.8) / 0.2
  const pulse = lock === 1 ? 1 + 0.08 * Math.sin(t * 40) : 1

  ctx.globalAlpha = fade
  ctx.strokeStyle = "#ef4444"
  ctx.shadowColor = "#ef4444"
  ctx.shadowBlur = 12
  ctx.lineWidth = 3

  ctx.save()
  ctx.translate(at.x, at.y)
  ctx.rotate((1 - eased) * Math.PI)

  ctx.beginPath()
  ctx.arc(0, 0, radius * pulse, 0, 2 * Math.PI)
  ctx.stroke()

  // The four ticks around the ring, and the corners closing in
  for (let i = 0; i < 4; i++) {
    ctx.rotate(Math.PI / 2)
    ctx.beginPath()
    ctx.moveTo(radius * pulse + 6, 0)
    ctx.lineTo(radius * pulse + 26, 0)
    ctx.stroke()

    ctx.beginPath()
    ctx.moveTo(radius * 1.35, radius * 0.9)
    ctx.lineTo(radius * 1.35, radius * 1.35)
    ctx.lineTo(radius * 0.9, radius * 1.35)
    ctx.stroke()
  }
  ctx.restore()

  ctx.fillStyle = "#ef4444"
  ctx.beginPath()
  ctx.arc(at.x, at.y, 5, 0, 2 * Math.PI)
  ctx.fill()

  if (lock === 1) {
    ctx.font = "700 14px ui-sans-serif, system-ui, sans-serif"
    ctx.textAlign = "center"
    ctx.fillText("LOCKED", at.x, at.y - radius - 34)
  }
}

function drawLightning(ctx, effect, at, t, width, height) {
  // Flickers a few times, like a real strike
  const flicker = [1, 0.15, 1, 0.3, 0.9, 0.5, 0.2][Math.min(6, Math.floor(t * 7))]
  if (!effect.path) effect.path = bolt(at.x + effect.offset, -20, at.x, at.y)

  if (t < 0.25) {
    ctx.globalAlpha = 0.35 * (1 - t / 0.25)
    ctx.fillStyle = "#e0f2fe"
    ctx.fillRect(0, 0, width, height)
  }

  ctx.globalAlpha = flicker * (1 - t * 0.6)
  ctx.lineCap = "round"
  ctx.lineJoin = "round"
  ctx.shadowColor = "#93c5fd"
  ctx.shadowBlur = 25

  const paths = [effect.path]
  if (!effect.branchPaths) {
    effect.branchPaths = Array.from({length: effect.branches}, () => {
      const from = effect.path[Math.floor(random(8, effect.path.length * 0.7))]
      return bolt(from.x, from.y, from.x + random(-140, 140), from.y + random(60, 160))
    })
  }
  paths.push(...effect.branchPaths)

  paths.forEach((path, i) => {
    for (const [color, lineWidth] of [["#bfdbfe", i === 0 ? 9 : 4], ["#ffffff", i === 0 ? 3.5 : 1.5]]) {
      ctx.strokeStyle = color
      ctx.lineWidth = lineWidth
      ctx.beginPath()
      ctx.moveTo(path[0].x, path[0].y)
      path.forEach(p => ctx.lineTo(p.x, p.y))
      ctx.stroke()
    }
  })

  // A burst where it hits
  ctx.fillStyle = "#ffffff"
  ctx.beginPath()
  ctx.arc(at.x, at.y, 18 * (1 - t), 0, 2 * Math.PI)
  ctx.fill()
}

function drawStars(ctx, effect, at, t, elapsed) {
  const seconds = elapsed / 1000
  for (const p of effect.particles) {
    const x = at.x + p.vx * seconds
    const y = at.y + p.vy * seconds + 180 * seconds * seconds
    ctx.globalAlpha = 1 - t

    // A streak behind each star
    ctx.strokeStyle = p.color
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.moveTo(x, y)
    ctx.lineTo(x - p.vx * 0.06, y - (p.vy + 360 * seconds) * 0.06)
    ctx.stroke()

    ctx.save()
    ctx.translate(x, y)
    ctx.rotate(p.spin * seconds)
    ctx.fillStyle = p.color
    fivePointStar(ctx, p.size)
    ctx.restore()
  }
}

function fivePointStar(ctx, size) {
  ctx.beginPath()
  for (let i = 0; i < 10; i++) {
    const radius = i % 2 === 0 ? size : size * 0.45
    const angle = -Math.PI / 2 + (i * Math.PI) / 5
    ctx.lineTo(Math.cos(angle) * radius, Math.sin(angle) * radius)
  }
  ctx.closePath()
  ctx.fill()
}

function drawHearts(ctx, effect, at, elapsed) {
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"
  for (const p of effect.particles) {
    const time = elapsed - p.delay
    if (time < 0) continue
    const seconds = time / 1000
    const left = 1 - time / (effect.duration - p.delay)
    ctx.globalAlpha = Math.max(0, Math.min(1, left * 1.5))
    ctx.font = `${p.size}px sans-serif`
    ctx.fillText(
      p.emoji,
      at.x + p.dx + Math.sin(p.phase + seconds * 4) * p.sway,
      at.y - p.speed * seconds
    )
  }
}

function drawShockwave(ctx, at, elapsed, duration) {
  for (let ring = 0; ring < 3; ring++) {
    const t = (elapsed - ring * 130) / (duration - 260)
    if (t < 0 || t > 1) continue
    const eased = 1 - (1 - t) ** 3
    ctx.globalAlpha = 0.9 * (1 - t)
    ctx.strokeStyle = ring === 1 ? "#67e8f9" : "#ffffff"
    ctx.lineWidth = 7 * (1 - t) + 1
    ctx.shadowColor = "#67e8f9"
    ctx.shadowBlur = 15
    ctx.beginPath()
    ctx.arc(at.x, at.y, 20 + eased * 300, 0, 2 * Math.PI)
    ctx.stroke()
  }
}

function drawSpiral(ctx, effect, at, t) {
  for (const p of effect.particles) {
    const angle = p.angle + t * 9
    const radius = 10 + t * 220
    ctx.globalAlpha = 1 - t
    ctx.fillStyle = p.color
    star(ctx, at.x + Math.cos(angle) * radius, at.y + Math.sin(angle) * radius, 6 * (1 - t) + 2)
  }
}

export class Effects {
  constructor() {
    this.active = []
  }

  // `locate` finds where the effect is on the screen now, or null when it's not on the page
  add(name, locate) {
    // Shapes drawn over a stream this page doesn't show don't set anything off here
    if (!DURATIONS[name] || !locate()) return
    this.active.push({...create(name), locate})
  }

  clear() {
    this.active = []
  }

  draw(ctx, now, width, height) {
    this.active = this.active.filter(effect => now - effect.born < effect.duration)

    for (const effect of this.active) {
      const at = effect.locate()
      if (!at) continue

      const elapsed = now - effect.born
      const t = elapsed / effect.duration

      ctx.save()
      switch (effect.name) {
        case "lightning":
          drawLightning(ctx, effect, at, t, width, height)
          break
        case "star":
          drawStars(ctx, effect, at, t, elapsed)
          break
        case "heart":
          drawHearts(ctx, effect, at, elapsed)
          break
        case "circle":
          drawShockwave(ctx, at, elapsed, effect.duration)
          break
        case "spiral":
          drawSpiral(ctx, effect, at, t)
          break
        case "target":
          drawTarget(ctx, at, t)
          break
      }
      ctx.restore()
    }
  }
}
