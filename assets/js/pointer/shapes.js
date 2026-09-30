// Recognizes the shapes that set off special effects, from a single stroke drawn
// with the pointer. Based on the $1 unistroke recognizer (Wobbrock et al. 2007):
// the stroke is resampled, rotated, scaled and compared point by point with
// templates of each shape. Decoy templates of common doodles (lines, waves,
// checkmarks, squares) catch strokes that aren't meant to be anything

const POINTS = 64
const SIZE = 250
const ANGLE_RANGE = (45 * Math.PI) / 180
const ANGLE_PRECISION = (2 * Math.PI) / 180
const PHI = 0.5 * (-1 + Math.sqrt(5))
const HALF_DIAGONAL = 0.5 * Math.sqrt(2 * SIZE * SIZE)

// How close a stroke has to be to its best template, from 0 to 1
const MIN_SCORE = 0.8
// Strokes smaller than this, in pixels, are too small to mean anything
const MIN_SIZE = 60
// Closed shapes have to end near where they started, as a share of their size
const MAX_GAP = 0.35

const CLOSED_SHAPES = new Set(["circle", "star", "heart", "infinity"])

// A corner turns more than this within a short stretch of the stroke
const CORNER_ANGLE = (70 * Math.PI) / 180
const MIN_LIGHTNING_CORNERS = 2

// Counts the stroke's sharp turns, looking a few points before and after each point
// so small wobbles don't count
function sharpCorners(points) {
  const resampled = resample(points, 32)
  const reach = 2
  let corners = 0
  let lastCorner = -Infinity

  for (let i = reach; i < resampled.length - reach; i++) {
    const a = resampled[i - reach]
    const b = resampled[i]
    const c = resampled[i + reach]
    const turn = Math.abs(
      Math.atan2(Math.sin(Math.atan2(c.y - b.y, c.x - b.x) - Math.atan2(b.y - a.y, b.x - a.x)),
        Math.cos(Math.atan2(c.y - b.y, c.x - b.x) - Math.atan2(b.y - a.y, b.x - a.x)))
    )
    if (turn > CORNER_ANGLE && i - lastCorner > reach) {
      corners++
      lastCorner = i
    }
  }

  return corners
}

function distance(a, b) {
  return Math.hypot(b.x - a.x, b.y - a.y)
}

function pathLength(points) {
  let length = 0
  for (let i = 1; i < points.length; i++) length += distance(points[i - 1], points[i])
  return length
}

function centroid(points) {
  const sum = points.reduce((acc, p) => ({x: acc.x + p.x, y: acc.y + p.y}), {x: 0, y: 0})
  return {x: sum.x / points.length, y: sum.y / points.length}
}

function boundingBox(points) {
  const xs = points.map(p => p.x)
  const ys = points.map(p => p.y)
  const minX = Math.min(...xs)
  const minY = Math.min(...ys)
  return {x: minX, y: minY, width: Math.max(...xs) - minX, height: Math.max(...ys) - minY}
}

function resample(points, n) {
  const interval = pathLength(points) / (n - 1)
  const source = points.map(p => ({x: p.x, y: p.y}))
  const result = [source[0]]
  let accumulated = 0

  for (let i = 1; i < source.length; i++) {
    const d = distance(source[i - 1], source[i])
    if (accumulated + d >= interval && d > 0) {
      const t = (interval - accumulated) / d
      const q = {
        x: source[i - 1].x + t * (source[i].x - source[i - 1].x),
        y: source[i - 1].y + t * (source[i].y - source[i - 1].y)
      }
      result.push(q)
      source.splice(i, 0, q)
      accumulated = 0
    } else {
      accumulated += d
    }
  }

  // Rounding can leave the last point out
  while (result.length < n) result.push(source[source.length - 1])
  return result.slice(0, n)
}

function rotateBy(points, angle) {
  const c = centroid(points)
  const cos = Math.cos(angle)
  const sin = Math.sin(angle)
  return points.map(p => ({
    x: (p.x - c.x) * cos - (p.y - c.y) * sin + c.x,
    y: (p.x - c.x) * sin + (p.y - c.y) * cos + c.y
  }))
}

function indicativeAngle(points) {
  const c = centroid(points)
  return Math.atan2(c.y - points[0].y, c.x - points[0].x)
}

// Scaled keeping the aspect ratio, so lines and waves don't get stretched into squares
function scaleTo(points, size) {
  const box = boundingBox(points)
  const scale = size / Math.max(box.width, box.height, 1)
  return points.map(p => ({x: p.x * scale, y: p.y * scale}))
}

function translateToOrigin(points) {
  const c = centroid(points)
  return points.map(p => ({x: p.x - c.x, y: p.y - c.y}))
}

function normalize(points) {
  let result = resample(points, POINTS)
  result = rotateBy(result, -indicativeAngle(result))
  result = scaleTo(result, SIZE)
  return translateToOrigin(result)
}

function pathDistance(a, b) {
  let d = 0
  for (let i = 0; i < a.length; i++) d += distance(a[i], b[i])
  return d / a.length
}

function distanceAtAngle(points, template, angle) {
  return pathDistance(rotateBy(points, angle), template)
}

// Golden section search for the rotation that fits the template best
function distanceAtBestAngle(points, template) {
  let a = -ANGLE_RANGE
  let b = ANGLE_RANGE
  let x1 = PHI * a + (1 - PHI) * b
  let f1 = distanceAtAngle(points, template, x1)
  let x2 = (1 - PHI) * a + PHI * b
  let f2 = distanceAtAngle(points, template, x2)

  while (Math.abs(b - a) > ANGLE_PRECISION) {
    if (f1 < f2) {
      b = x2
      x2 = x1
      f2 = f1
      x1 = PHI * a + (1 - PHI) * b
      f1 = distanceAtAngle(points, template, x1)
    } else {
      a = x1
      x1 = x2
      f1 = f2
      x2 = (1 - PHI) * a + PHI * b
      f2 = distanceAtAngle(points, template, x2)
    }
  }

  return Math.min(f1, f2)
}

// Templates, in any unit since they're normalized. Shapes can be drawn either way
// around, so each comes reversed too

export function polyline(corners, steps = 16) {
  const points = []
  for (let i = 1; i < corners.length; i++) {
    const [ax, ay] = corners[i - 1]
    const [bx, by] = corners[i]
    for (let s = 0; s < steps; s++) {
      const t = s / steps
      points.push({x: ax + (bx - ax) * t, y: ay + (by - ay) * t})
    }
  }
  const [lx, ly] = corners[corners.length - 1]
  points.push({x: lx, y: ly})
  return points
}

export function curve(fn, from, to, steps = 96) {
  const points = []
  for (let i = 0; i <= steps; i++) points.push(fn(from + ((to - from) * i) / steps))
  return points
}

const reversed = points => [...points].reverse()
const mirrored = points => points.map(p => ({x: -p.x, y: p.y}))

function withVariants(name, shapes, {mirror = false} = {}) {
  const all = []
  for (const shape of shapes) {
    all.push(shape, reversed(shape))
    if (mirror) all.push(mirrored(shape), reversed(mirrored(shape)))
  }
  return all.map(points => ({name, points: normalize(points)}))
}

const circle = curve(t => ({x: Math.cos(t), y: Math.sin(t)}), -Math.PI / 2, 1.5 * Math.PI)
const ellipse = curve(t => ({x: 1.4 * Math.cos(t), y: Math.sin(t)}), -Math.PI / 2, 1.5 * Math.PI)

// People draw spirals with anywhere from 1.5 to 4 turns
const spirals = [1.5, 2.25, 3, 4].map(turns =>
  curve(t => ({x: t * Math.cos(t), y: t * Math.sin(t)}), 0.5, turns * 2 * Math.PI, 160)
)

const starCorners = [0, 1, 2, 3, 4, 5].map(k => {
  const angle = -Math.PI / 2 + (k * 4 * Math.PI) / 5
  return [Math.cos(angle), Math.sin(angle)]
})
const star = polyline(starCorners, 20)

const heartAt = t => ({
  x: 16 * Math.sin(t) ** 3,
  y: -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t))
})
// Hearts are drawn from the dip at the top or from the tip at the bottom
const heartFromTop = curve(heartAt, 0.02, 2 * Math.PI - 0.02)
const heartFromTip = curve(heartAt, Math.PI, 3 * Math.PI)

// A lemniscate, drawn starting from its middle or from one end
const infinityAt = t => ({x: Math.cos(t) / (1 + Math.sin(t) ** 2), y: (Math.sin(t) * Math.cos(t)) / (1 + Math.sin(t) ** 2)})
const infinityFromMiddle = curve(infinityAt, Math.PI / 2, 2.5 * Math.PI, 120)
const infinityFromEnd = curve(infinityAt, 0, 2 * Math.PI, 120)

const zigzag = polyline([[0, 0], [1, 0.6], [0, 1.2], [1, 1.8], [0, 2.4]])
const longZigzag = polyline([[0, 0], [1, 0.5], [0, 1], [1, 1.5], [0, 2], [1, 2.5]])
const bolt = polyline([[0.7, 0], [0.1, 1.2], [0.8, 1.2], [0.2, 2.6]])

const TEMPLATES = [
  ...withVariants("circle", [circle, ellipse]),
  ...withVariants("spiral", spirals, {mirror: true}),
  ...withVariants("star", [star], {mirror: true}),
  ...withVariants("heart", [heartFromTop, heartFromTip], {mirror: true}),
  ...withVariants("lightning", [zigzag, longZigzag, bolt], {mirror: true}),
  ...withVariants("infinity", [infinityFromMiddle, infinityFromEnd], {mirror: true}),
  // Decoys
  ...withVariants("none", [
    polyline([[0, 0], [1, 0]]),
    polyline([[0, 0], [1, 0.1], [2, 0]]),
    curve(t => ({x: Math.cos(t), y: Math.sin(t)}), Math.PI, 2 * Math.PI),
    curve(t => ({x: t, y: 0.35 * Math.sin(t)}), 0, 4 * Math.PI),
    curve(t => ({x: t, y: 0.6 * Math.sin(t)}), 0, 2 * Math.PI),
    polyline([[0, 0], [0.4, 0.5], [1.2, -0.6]]),
    polyline([[0, 0], [0, 1], [0.8, 1]]),
    polyline([[0, 0], [0.5, 1], [1, 0]]),
    polyline([[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]),
    polyline([[0, 0], [1, 0], [0.5, 0.9], [0, 0]]),
    polyline([[0, 0], [1, 0], [0.8, -0.2], [1, 0], [0.8, 0.2]]),
  ], {mirror: true})
]

/**
 * The shape a stroke of screen points looks like, or null. Returns the shape's
 * name and its middle, which is where its effect goes off
 */
export function recognize(points) {
  if (points.length < 10) return null

  const box = boundingBox(points)
  if (Math.max(box.width, box.height) < MIN_SIZE) return null

  const candidate = normalize(points)
  let best = {name: null, score: 0}

  for (const template of TEMPLATES) {
    const score = 1 - distanceAtBestAngle(candidate, template.points) / HALF_DIAGONAL
    if (score > best.score) best = {name: template.name, score}
  }

  if (best.name === null || best.name === "none" || best.score < MIN_SCORE) return null

  if (CLOSED_SHAPES.has(best.name)) {
    const gap = distance(points[0], points[points.length - 1])
    if (gap > MAX_GAP * Math.max(box.width, box.height)) return null
  }

  // Lightning is all sharp corners, which wobbly scribbles don't have
  if (best.name === "lightning" && sharpCorners(points) < MIN_LIGHTNING_CORNERS) return null

  return {
    name: best.name,
    score: best.score,
    center: {x: box.x + box.width / 2, y: box.y + box.height / 2},
    width: box.width,
    height: box.height
  }
}
