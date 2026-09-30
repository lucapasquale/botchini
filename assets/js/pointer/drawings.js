// Recognizes drawings made of several strokes, like the eggplant easter egg, which
// people draw in all sorts of ways: in one line or piece by piece, in any order,
// direction and angle. Based on the $P point cloud recognizer (Vatavu et al. 2012):
// all the drawing's strokes become one cloud of points, which is compared with
// clouds of example drawings regardless of the order the points were drawn in.
// Decoy examples of other drawings catch the ones that aren't meant to be anything

import {curve, polyline} from "./shapes"

const POINTS = 32
// How much closer a drawing has to be to its best example than to any decoy.
// Scribbles are about as close to everything, so they don't make it
const MIN_MARGIN = 1.12
// Drawings smaller than this, in pixels, are too small to mean anything
const MIN_SIZE = 80

function resample(strokes, n) {
  const points = strokes.flatMap((stroke, id) => stroke.map(p => ({x: p.x, y: p.y, id})))
  let length = 0
  for (let i = 1; i < points.length; i++) {
    if (points[i].id === points[i - 1].id) length += Math.hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
  }
  const interval = length / (n - 1)
  const result = [points[0]]
  let accumulated = 0

  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1]
    const b = points[i]
    if (a.id !== b.id) continue
    const d = Math.hypot(b.x - a.x, b.y - a.y)
    if (accumulated + d >= interval && d > 0) {
      const t = (interval - accumulated) / d
      const q = {x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y), id: a.id}
      result.push(q)
      points.splice(i, 0, q)
      accumulated = 0
    } else {
      accumulated += d
    }
  }

  while (result.length < n) result.push(points[points.length - 1])
  return result.slice(0, n)
}

function normalize(strokes) {
  let points = resample(strokes, POINTS)
  const xs = points.map(p => p.x)
  const ys = points.map(p => p.y)
  const size = Math.max(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys), 1e-6)
  points = points.map(p => ({x: p.x / size, y: p.y / size}))
  const cx = points.reduce((sum, p) => sum + p.x, 0) / points.length
  const cy = points.reduce((sum, p) => sum + p.y, 0) / points.length
  return points.map(p => ({x: p.x - cx, y: p.y - cy}))
}

// Matches each point with the closest one left in the other cloud, trusting the
// first matches the most
function cloudDistance(a, b, start) {
  const matched = new Array(b.length).fill(false)
  let sum = 0
  let i = start

  do {
    let best = Infinity
    let index = -1
    for (let j = 0; j < b.length; j++) {
      if (matched[j]) continue
      const d = Math.hypot(a[i].x - b[j].x, a[i].y - b[j].y)
      if (d < best) {
        best = d
        index = j
      }
    }
    matched[index] = true
    sum += (1 - ((i - start + a.length) % a.length) / a.length) * best
    i = (i + 1) % a.length
  } while (i !== start)

  return sum
}

function greedyCloudMatch(points, template) {
  const step = Math.floor(Math.sqrt(points.length))
  let min = Infinity
  for (let i = 0; i < points.length; i += step) {
    min = Math.min(min, cloudDistance(points, template, i), cloudDistance(template, points, i))
  }
  // Per point, so it doesn't depend on how many points there are
  return min / points.length
}

// Examples

const arc = (cx, cy, r, from, to, steps = 24) =>
  curve(t => ({x: cx + r * Math.cos(t), y: cy + r * Math.sin(t)}), from, to, steps)

// Pointing up, with the balls around the origin
function eggplantDrawings(shaft, width, ball) {
  const base = -0.1
  const top = base - shaft
  const outline = [
    ...polyline([[-width, base], [-width, top]], 20),
    ...arc(0, top, width, Math.PI, 2 * Math.PI, 12),
    ...polyline([[width, top], [width, base]], 20)
  ]
  const leftBall = arc(-ball, ball * 0.6, ball, -0.3, 2 * Math.PI - 0.3, 28)
  const rightBall = arc(ball, ball * 0.6, ball, Math.PI + 0.3, 3 * Math.PI + 0.3, 28)
  const hangingBalls = [
    ...arc(-ball, ball * 0.6, ball, Math.PI, 0, 20).reverse(),
    ...arc(ball, ball * 0.6, ball, Math.PI, 0, 20).reverse()
  ]

  return [
    // In one line, from a ball, up and down the shaft, around the other ball
    [[...arc(-ball, ball * 0.6, ball, -0.5, -2 * Math.PI - 0.3, 28), ...outline, ...arc(ball, ball * 0.6, ball, Math.PI + 0.5, 3 * Math.PI, 28)]],
    // The shaft, then each ball
    [outline, leftBall, rightBall],
    // The shaft, then the balls hanging below it in one go
    [outline, hangingBalls],
    // The shaft with a line across its tip
    [outline, polyline([[-width, top + width * 0.6], [width, top + width * 0.6]], 8), hangingBalls]
  ]
}

const circleAt = (cx, cy, r) => arc(cx, cy, r, 0, 2 * Math.PI, 40)
const heartAt = t => ({
  x: (16 * Math.sin(t) ** 3) / 16,
  y: -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t)) / 16
})
const starCorners = [0, 1, 2, 3, 4, 5].map(k => {
  const angle = -Math.PI / 2 + (k * 4 * Math.PI) / 5
  return [Math.cos(angle), Math.sin(angle)]
})

// Other drawings, which aren't eggplants
const DECOYS = [
  [circleAt(0, 0, 1)],
  [curve(heartAt, 0.02, 2 * Math.PI - 0.02)],
  [polyline(starCorners, 16)],
  [curve(t => ({x: t * Math.cos(t), y: t * Math.sin(t)}), 0.5, 5 * Math.PI, 120)],
  [curve(t => ({x: Math.cos(t) / (1 + Math.sin(t) ** 2), y: (Math.sin(t) * Math.cos(t)) / (1 + Math.sin(t) ** 2)}), 0, 2 * Math.PI, 90)],
  [polyline([[0, 0], [1, 0.6], [0, 1.2], [1, 1.8], [0, 2.4]])],
  [polyline([[0, 0], [2, 0]])],
  [polyline([[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]])],
  [polyline([[0, 0], [1, 0], [0.5, 0.9], [0, 0]])],
  // A smiley
  [circleAt(0, 0, 1), circleAt(-0.35, -0.3, 0.08), circleAt(0.35, -0.3, 0.08), arc(0, 0.05, 0.5, 0.3, Math.PI - 0.3, 20)],
  // Glasses, or eyes
  [circleAt(-0.6, 0, 0.45), circleAt(0.6, 0, 0.45)],
  // A house
  [polyline([[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]), polyline([[-0.1, 0], [0.5, -0.6], [1.1, 0]])],
  // An X, and a plus
  [polyline([[0, 0], [1, 1]]), polyline([[1, 0], [0, 1]])],
  [polyline([[0.5, 0], [0.5, 1]]), polyline([[0, 0.5], [1, 0.5]])],
  // An arrow
  [polyline([[0, 0], [2, 0]]), polyline([[1.6, -0.3], [2, 0], [1.6, 0.3]])],
  // A mushroom, or a tree
  [arc(0, 0, 0.8, Math.PI, 2 * Math.PI, 30), polyline([[-0.8, 0], [0.8, 0]]), polyline([[-0.2, 0], [-0.2, 1], [0.2, 1], [0.2, 0]])],
  // A snowman
  [circleAt(0, 0, 0.6), circleAt(0, -0.95, 0.35)],
  // A lollipop, or a balloon on a string
  [polyline([[0, 0], [0, 2]]), circleAt(0, -0.5, 0.5)],
  [circleAt(0, -0.5, 0.5), polyline([[0, 0], [0.1, 0.7], [-0.1, 1.4], [0, 2]])],
  // Arrows, made in one line or two
  [polyline([[0, 0], [2, 0], [1.6, -0.3], [2, 0], [1.6, 0.3]])],
  [polyline([[0, 0], [2, 0]]), polyline([[1.5, -0.4], [2, 0], [1.5, 0.4]])],
  [polyline([[0, 0], [0.6, 0.1], [1.2, -0.1], [2, 0]]), polyline([[1.6, -0.3], [2, 0], [1.6, 0.3]])],
  // Underlining something and circling it
  [polyline([[0, 0], [2, 0.05]]), circleAt(1, -0.6, 0.4)],
  [polyline([[0, 0], [2, 0]]), polyline([[0, 0.2], [2, 0.2]])]
]

function rotate(strokes, angle) {
  const cos = Math.cos(angle)
  const sin = Math.sin(angle)
  return strokes.map(stroke => stroke.map(p => ({x: p.x * cos - p.y * sin, y: p.x * sin + p.y * cos})))
}

// Drawings are compared as they are, so the examples come at every angle
const ANGLES = [0, 1, 2, 3, 4, 5, 6, 7].map(k => (k * Math.PI) / 4)

function examples(name, drawings) {
  return drawings.flatMap(strokes => ANGLES.map(angle => ({name, points: normalize(rotate(strokes, angle))})))
}

const EXAMPLES = [
  ...examples("eggplant", [
    ...eggplantDrawings(1.8, 0.28, 0.42),
    ...eggplantDrawings(1.1, 0.32, 0.45),
    ...eggplantDrawings(2.6, 0.24, 0.38)
  ]),
  ...examples("none", DECOYS)
]

/**
 * What a drawing made of strokes of screen points looks like, or null. Returns
 * its name and its middle, which is where its effect goes off
 */
export function recognizeDrawing(strokes, {minMargin = MIN_MARGIN} = {}) {
  const drawn = strokes.filter(stroke => stroke.length > 1)
  const all = drawn.flat()
  if (all.length < 10) return null

  const xs = all.map(p => p.x)
  const ys = all.map(p => p.y)
  const box = {x: Math.min(...xs), y: Math.min(...ys), width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys)}
  if (Math.max(box.width, box.height) < MIN_SIZE) return null

  const points = normalize(drawn)
  let best = {name: null, distance: Infinity}
  let decoy = Infinity
  for (const example of EXAMPLES) {
    const distance = greedyCloudMatch(points, example.points)
    if (example.name === "none") decoy = Math.min(decoy, distance)
    else if (distance < best.distance) best = {name: example.name, distance}
  }

  const margin = decoy / best.distance
  if (margin < minMargin) return null
  return {name: best.name, margin, center: {x: box.x + box.width / 2, y: box.y + box.height / 2}}
}
