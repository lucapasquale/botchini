// Draws pointers and their trails on a canvas, in the style their owner picked.
// Lines are curves that pass through every point the mouse reported, so they
// look smooth without cutting corners: sharp turns stay sharp

// Turns sharper than this are drawn as corners instead of being rounded
const CORNER_ANGLE = (80 * Math.PI) / 180

function turnAt(a, b, c) {
  const angle = Math.atan2(c.y - b.y, c.x - b.x) - Math.atan2(b.y - a.y, b.x - a.x)
  return Math.abs(Math.atan2(Math.sin(angle), Math.cos(angle)))
}

/**
 * Splits a line through the points into cubic curves, using centripetal
 * Catmull-Rom splines, which never overshoot or loop at tight turns
 */
export function curves(points) {
  const segments = []
  if (points.length < 2) return segments

  const corner = points.map((p, i) =>
    i > 0 && i < points.length - 1 && turnAt(points[i - 1], p, points[i + 1]) > CORNER_ANGLE
  )

  for (let i = 0; i < points.length - 1; i++) {
    const p1 = points[i]
    const p2 = points[i + 1]
    const p0 = i > 0 && !corner[i] ? points[i - 1] : p1
    const p3 = i < points.length - 2 && !corner[i + 1] ? points[i + 2] : p2

    segments.push({from: p1, c1: controlPoint(p0, p1, p2), c2: controlPoint(p3, p2, p1), to: p2})
  }

  return segments
}

// The control point leaving `p1` towards `p2`, given the point before it
function controlPoint(p0, p1, p2) {
  const d1 = Math.sqrt(Math.hypot(p1.x - p0.x, p1.y - p0.y))
  const d2 = Math.sqrt(Math.hypot(p2.x - p1.x, p2.y - p1.y))
  if (d1 < 1e-6 || d2 < 1e-6) return {x: p1.x + (p2.x - p1.x) / 3, y: p1.y + (p2.y - p1.y) / 3}

  const a = d1 * d1
  const b = d2 * d2
  const n = 2 * a + 3 * d1 * d2 + b
  const m = 3 * d1 * (d1 + d2)

  return {x: (a * p2.x - b * p0.x + n * p1.x) / m, y: (a * p2.y - b * p0.y + n * p1.y) / m}
}

function tracePath(ctx, segments) {
  ctx.beginPath()
  ctx.moveTo(segments[0].from.x, segments[0].from.y)
  for (const s of segments) ctx.bezierCurveTo(s.c1.x, s.c1.y, s.c2.x, s.c2.y, s.to.x, s.to.y)
}

function traceSegment(ctx, s) {
  ctx.beginPath()
  ctx.moveTo(s.from.x, s.from.y)
  ctx.bezierCurveTo(s.c1.x, s.c1.y, s.c2.x, s.c2.y, s.to.x, s.to.y)
}

function segmentLength(s) {
  return Math.hypot(s.to.x - s.from.x, s.to.y - s.from.y)
}

function rainbow(distance, time) {
  return `hsl(${(distance * 1.2 + time * 0.12) % 360} 95% 60%)`
}

// Where the line is after walking `step` pixels at a time along it, for pixel art
function samplesAlong(segments, step) {
  const points = []
  for (const s of segments) {
    const steps = Math.max(1, Math.ceil(segmentLength(s) / step))
    for (let i = 0; i < steps; i++) {
      const t = i / steps
      const u = 1 - t
      points.push({
        x: u * u * u * s.from.x + 3 * u * u * t * s.c1.x + 3 * u * t * t * s.c2.x + t * t * t * s.to.x,
        y: u * u * u * s.from.y + 3 * u * u * t * s.c1.y + 3 * u * t * t * s.c2.y + t * t * t * s.to.y
      })
    }
  }
  const last = segments[segments.length - 1]
  if (last) points.push(last.to)
  return points
}

function drawPixels(ctx, segments, color, width, alphaAt) {
  const seen = new Set()
  const samples = samplesAlong(segments, width / 2)

  samples.forEach((p, i) => {
    const gx = Math.floor(p.x / width)
    const gy = Math.floor(p.y / width)
    const key = `${gx},${gy}`
    if (seen.has(key)) return
    seen.add(key)

    ctx.globalAlpha = alphaAt(i / Math.max(1, samples.length - 1))
    ctx.fillStyle = color
    ctx.fillRect(gx * width, gy * width, width, width)
  })
}

// A line that's thin and faint at its start and bold at its end. Drawn as a few
// overlapping layers, each starting further along, since fading each little piece
// on its own leaves beads where the pieces overlap
const TAPER_LAYERS = 6

function drawTapered(ctx, segments, color, width, alpha) {
  for (let layer = 0; layer < TAPER_LAYERS; layer++) {
    const from = Math.floor((layer / TAPER_LAYERS) * segments.length)
    const part = segments.slice(from)
    if (part.length === 0) continue

    ctx.globalAlpha = alpha / (TAPER_LAYERS - layer + 1) + alpha * 0.1
    ctx.strokeStyle = color
    ctx.lineWidth = Math.max(1, width * ((layer + 1) / TAPER_LAYERS))
    tracePath(ctx, part)
    ctx.stroke()
  }
}

function lighten(color) {
  return color === "#ffffff" ? "rgba(203, 213, 225, 0.9)" : "rgba(255, 255, 255, 0.55)"
}

/**
 * A line drawn with the mouse button held, fully visible, in one width.
 * `alpha` fades the whole line as it vanishes
 */
export function drawStroke(ctx, points, look, alpha, time) {
  if (points.length === 0) return
  const {color, width, style} = look
  const segments = curves(points.length === 1 ? [points[0], points[0]] : points)

  ctx.save()
  ctx.lineCap = "round"
  ctx.lineJoin = "round"
  ctx.globalAlpha = alpha

  switch (style) {
    case "glossy":
      ctx.strokeStyle = color
      ctx.lineWidth = width
      tracePath(ctx, segments)
      ctx.stroke()
      ctx.translate(-width * 0.12, -width * 0.14)
      ctx.strokeStyle = lighten(color)
      ctx.lineWidth = width * 0.3
      tracePath(ctx, segments)
      ctx.stroke()
      break

    case "neon":
      ctx.shadowColor = color
      ctx.shadowBlur = width * 1.6
      ctx.strokeStyle = color
      ctx.lineWidth = width
      tracePath(ctx, segments)
      ctx.stroke()
      ctx.strokeStyle = "rgba(255, 255, 255, 0.9)"
      ctx.lineWidth = width * 0.35
      tracePath(ctx, segments)
      ctx.stroke()
      break

    case "rainbow": {
      let distance = 0
      ctx.lineWidth = width
      for (const s of segments) {
        ctx.strokeStyle = rainbow(distance, time)
        traceSegment(ctx, s)
        ctx.stroke()
        distance += segmentLength(s)
      }
      break
    }

    case "pixel":
      drawPixels(ctx, segments, color, width, () => alpha)
      break

    case "comet":
      // Thin and faint where the line started, bold where it ends, with a flicker
      ctx.shadowColor = color
      ctx.shadowBlur = width * 0.8
      drawTapered(ctx, segments, color, width, alpha * (0.85 + Math.random() * 0.15))
      break

    default:
      // Matte, and sparkle, whose sparkles come from the particles
      ctx.strokeStyle = color
      ctx.lineWidth = width
      tracePath(ctx, segments)
      ctx.stroke()
  }

  ctx.restore()
}

/**
 * The short tail following a pointer that isn't drawing: thin and faint at its
 * end, as wide as the pointer at its head. It covers the last split second, so
 * it's longer the faster the pointer moves
 */
export function drawTail(ctx, points, look, time) {
  if (points.length < 2) return
  const {color, width, style} = look
  const segments = curves(points)

  ctx.save()
  ctx.lineCap = "round"
  ctx.lineJoin = "round"

  if (style === "pixel") {
    drawPixels(ctx, segments, color, width * 0.7, t => 0.15 + 0.6 * t)
    ctx.restore()
    return
  }

  if (style === "neon" || style === "comet") {
    ctx.shadowColor = color
    ctx.shadowBlur = width
  }

  if (style === "rainbow") {
    // Every piece has its own color, so it's drawn piece by piece
    let distance = 0
    segments.forEach((s, i) => {
      const t = (i + 1) / segments.length
      ctx.globalAlpha = 0.15 + 0.6 * t
      ctx.lineWidth = Math.max(1, width * 0.9 * t)
      ctx.strokeStyle = rainbow(distance, time)
      traceSegment(ctx, s)
      ctx.stroke()
      distance += segmentLength(s)
    })
  } else {
    drawTapered(ctx, segments, color, width * 0.9, 0.8)
  }

  ctx.restore()
}

/**
 * The pointer itself, which replaces the mouse cursor while it's on
 */
export function drawDot(ctx, point, look, time, drawing) {
  const {color, width, style} = look
  const radius = Math.max(4, width * 0.55) * (drawing ? 1.15 : 1)
  const fill = style === "rainbow" ? rainbow(0, time) : color

  ctx.save()
  ctx.globalAlpha = 1

  if (style === "neon") {
    ctx.shadowColor = fill
    ctx.shadowBlur = width * 1.4
  }

  ctx.fillStyle = fill
  ctx.strokeStyle = color === "#ffffff" ? "rgba(17, 24, 39, 0.9)" : "rgba(255, 255, 255, 0.95)"
  ctx.lineWidth = 2

  if (style === "pixel") {
    const size = radius * 2
    ctx.fillRect(point.x - radius, point.y - radius, size, size)
    ctx.strokeRect(point.x - radius, point.y - radius, size, size)
  } else {
    ctx.beginPath()
    ctx.arc(point.x, point.y, radius, 0, 2 * Math.PI)
    ctx.fill()
    ctx.stroke()
  }

  if (style === "glossy") {
    ctx.fillStyle = lighten(color)
    ctx.beginPath()
    ctx.arc(point.x - radius * 0.3, point.y - radius * 0.35, radius * 0.35, 0, 2 * Math.PI)
    ctx.fill()
  }

  ctx.restore()
}

/**
 * Whose pointer it is, next to it
 */
export function drawName(ctx, point, name, look) {
  ctx.save()
  ctx.font = "600 12px ui-sans-serif, system-ui, sans-serif"
  const padding = 6
  const text = name.length > 24 ? `${name.slice(0, 23)}…` : name
  const width = ctx.measureText(text).width + padding * 2
  const offset = Math.max(4, look.width * 0.55) + 6
  const x = point.x + offset
  const y = point.y + offset

  ctx.globalAlpha = 0.92
  ctx.fillStyle = "rgba(17, 24, 39, 0.9)"
  ctx.strokeStyle = look.color === "#111827" ? "rgba(255, 255, 255, 0.6)" : look.color
  ctx.lineWidth = 1.5
  ctx.beginPath()
  ctx.roundRect(x, y, width, 20, 6)
  ctx.fill()
  ctx.stroke()

  ctx.fillStyle = "#ffffff"
  ctx.textBaseline = "middle"
  ctx.fillText(text, x + padding, y + 10.5)
  ctx.restore()
}

/**
 * Sparkles thrown off by sparkle pointers as they move
 */
export class Sparkles {
  constructor() {
    this.particles = []
  }

  spawn(x, y, color, count = 1) {
    for (let i = 0; i < count; i++) {
      const angle = Math.random() * 2 * Math.PI
      const speed = 20 + Math.random() * 60
      this.particles.push({
        x: x + (Math.random() - 0.5) * 8,
        y: y + (Math.random() - 0.5) * 8,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed + 20,
        size: 2 + Math.random() * 4,
        color: Math.random() < 0.5 ? "#ffffff" : color,
        born: performance.now(),
        life: 450 + Math.random() * 400
      })
    }
  }

  draw(ctx, now, dt) {
    this.particles = this.particles.filter(p => now - p.born < p.life)

    ctx.save()
    for (const p of this.particles) {
      p.x += p.vx * dt
      p.y += p.vy * dt
      const left = 1 - (now - p.born) / p.life
      ctx.globalAlpha = left
      ctx.fillStyle = p.color
      star(ctx, p.x, p.y, p.size * (0.5 + left / 2))
    }
    ctx.restore()
  }
}

// A four pointed sparkle
export function star(ctx, x, y, size) {
  ctx.beginPath()
  ctx.moveTo(x, y - size)
  ctx.quadraticCurveTo(x, y, x + size, y)
  ctx.quadraticCurveTo(x, y, x, y + size)
  ctx.quadraticCurveTo(x, y, x - size, y)
  ctx.quadraticCurveTo(x, y, x, y - size)
  ctx.fill()
}
