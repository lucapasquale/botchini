// Arranges the pinned screens so they get the most pixels they can.
//
// The server renders a safe 16:9 grid (one column per screen pinned, capped by
// the window height). That is wrong as soon as the streams aren't 16:9 or the
// window isn't wide: two pinned 16:9 streams side by side on a phone get two
// thumbnails, and a 4:3 or an ultrawide stream is letterboxed into a 16:9 box.
//
// Here the arrangement is chosen from what is actually on screen: each stream's
// decoded resolution, how many are pinned and the viewer's window. Every way of
// breaking the pinned screens into rows is scored by the total area it shows
// after fitting the window, and the best one wins. Tiles keep their order and
// their DOM position (moving a <video> would remount its hook and drop the
// connection), so only sizes, offsets and row numbers are written.

export const FALLBACK_RATIO = 16 / 9
const MAX_RATIO = 4
const MIN_RATIO = 1 / 3

// Every way of cutting `count` ordered tiles into contiguous rows
export function rowOptions(count) {
  if (count <= 1) return [[[0, 1]]]
  if (count > 8) {
    // 2^(n-1) compositions are cheap until they aren't; above 8 only even rows
    return Array.from({length: count}, (_, rows) => splitEvenly(count, rows + 1))
  }
  const options = []
  for (let mask = 0; mask < 1 << (count - 1); mask++) {
    const rows = []
    let start = 0
    for (let i = 0; i < count - 1; i++) {
      if (mask & (1 << i)) {
        rows.push([start, i + 1])
        start = i + 1
      }
    }
    rows.push([start, count])
    options.push(rows)
  }
  return options
}

function splitEvenly(count, rows) {
  const out = []
  let start = 0
  for (let r = 0; r < rows; r++) {
    const size = Math.ceil((count - start) / (rows - r))
    out.push([start, start + size])
    start += size
  }
  return out
}

export function clampRatio(ratio) {
  return Number.isFinite(ratio) && ratio > 0 ? Math.min(MAX_RATIO, Math.max(MIN_RATIO, ratio)) : FALLBACK_RATIO
}

// Score one arrangement: widths follow from the row's share of `width`, each
// tile's height from its own ratio, and the whole thing shrinks uniformly when
// it doesn't fit `height`. Area is what we maximise; the smallest tile breaks ties
// so one screen never gets sacrificed for the rest.
function score(rows, ratios, width, height, gap) {
  const tiles = []
  let total = 0
  let rowsHeight = 0

  rows.forEach(([start, end], rowIndex) => {
    const size = end - start
    const tileWidth = (width - (size - 1) * gap) / size
    if (tileWidth <= 0) return null

    let rowHeight = 0
    for (let i = start; i < end; i++) rowHeight = Math.max(rowHeight, tileWidth / ratios[i])
    rowsHeight += rowHeight

    tiles.push({rowIndex, start, end, tileWidth, rowHeight})
    total += size * tileWidth * rowHeight
  })

  if (tiles.length !== rows.length) return null

  const planned = rowsHeight + (rows.length - 1) * gap
  const scale = planned > height ? height / planned : 1
  let smallest = Infinity
  for (const row of tiles) {
    for (let i = row.start; i < row.end; i++) {
      smallest = Math.min(smallest, row.tileWidth * scale * ((row.tileWidth / ratios[i]) * scale))
    }
  }

  return {rows: tiles, scale, total: total * scale * scale, smallest, planned: planned * scale}
}

// tiles: [{ratio}] in display order. Returns per-tile pixel boxes and the row count
export function planLayout(tiles, width, height, gap = 12) {
  if (!tiles.length || !(width > 0) || !(height > 0)) return null

  const ratios = tiles.map((tile) => clampRatio(tile.ratio))
  let best = null

  for (const rows of rowOptions(tiles.length)) {
    const candidate = score(rows, ratios, width, height, gap)
    if (!candidate) continue
    if (!best || candidate.total > best.total * 1.001 ||
        (Math.abs(candidate.total - best.total) <= best.total * 0.001 && candidate.smallest > best.smallest)) {
      best = candidate
    }
  }

  if (!best) return null

  const boxes = []
  best.rows.forEach((row, rowIndex) => {
    for (let i = row.start; i < row.end; i++) {
      const w = row.tileWidth * best.scale
      const h = (row.tileWidth / ratios[i]) * best.scale
      boxes.push({
        index: i,
        row: rowIndex,
        width: w,
        height: h,
        left: (i - row.start) * (w + gap * best.scale),
        // Centred in its row. The grid places the row itself, so this is an offset
        // inside it, never a position on the page
        top: (row.rowHeight * best.scale - h) / 2
      })
    }
  })

  return {tiles: boxes, rows: best.rows.length, width: width * best.scale, height: best.planned, scale: best.scale}
}

export const ScreenGrid = {
  mounted() {
    this.container = document.getElementById("screens")
    if (!this.container) return

    this.plan = null
    this.applied = false
    this.onResize = () => {
      cancelAnimationFrame(this.frame)
      this.frame = requestAnimationFrame(() => this.layout())
    }

    window.addEventListener("resize", this.onResize)
    this.observer = new ResizeObserver(this.onResize)
    this.observer.observe(this.container)

    // A stream can arrive at any resolution, and change it mid-share
    this.container.addEventListener("loadedmetadata", this.onResize, true)
    this.container.addEventListener("resize", this.onResize, true)

    this.layout()
  },

  updated() {
    this.layout()
  },

  destroyed() {
    cancelAnimationFrame(this.frame)
    window.removeEventListener("resize", this.onResize)
    this.observer?.disconnect()
    this.container?.removeEventListener("loadedmetadata", this.onResize, true)
    this.container?.removeEventListener("resize", this.onResize, true)
    this.clear()
  },

  tiles() {
    return [...this.container.querySelectorAll('[data-main="true"]')]
      .map((el) => ({el, order: Number(el.dataset.bigIndex ?? 0)}))
      .sort((a, b) => a.order - b.order)
  },

  ratios(tiles) {
    return tiles.map(({el}) => {
      const video = el.querySelector("video")
      return video?.videoWidth && video?.videoHeight ? video.videoWidth / video.videoHeight : FALLBACK_RATIO
    })
  },

  layout() {
    if (!this.container) return
    const tiles = this.tiles()

    // One pinned screen keeps the server's layout: a single 16:9 box capped by height
    if (tiles.length < 2) return this.clear()

    // Measure the width the page can give, not the width the server guessed
    const current = this.container.style.maxWidth
    if (current !== this.plannedWidth) this.serverMaxWidth = current
    this.container.style.maxWidth = ""
    const gap = this.gap()
    const width = this.container.clientWidth
    const height = this.availableHeight(gap)

    this.plan = planLayout(this.ratios(tiles).map((ratio) => ({ratio})), width, height, gap)
    if (!this.plan) {
      this.container.style.maxWidth = this.serverMaxWidth || ""
      return
    }

    this.plannedWidth = `${Math.round(this.plan.width)}px`
    this.container.style.maxWidth = this.plannedWidth
    this.container.style.setProperty("--strip-row", this.plan.rows + 2)
    this.container.style.setProperty("--bar-row", this.plan.rows + 3)
    this.container.style.setProperty("--chat-row", this.plan.rows + 4)

    tiles.forEach(({el}, index) => {
      const box = this.plan.tiles.find((b) => b.index === index)
      if (!box) return
      el.style.width = `${box.width}px`
      el.style.height = `${box.height}px`
      el.style.marginLeft = `${box.left}px`
      el.style.marginTop = `${box.top}px`
      el.style.alignSelf = "start"
      el.style.gridRowStart = String(box.row + 2)
      el.dataset.planned = "true"

      // The tile is a 16:9 box by default; let the picture fill the box the plan
      // gave this stream instead, so a 4:3 or a phone share uses all of it
      const viewer = el.querySelector("[data-screen-viewer]")
      if (viewer) {
        viewer.style.height = "100%"
        viewer.style.aspectRatio = "auto"
      }
    })

    this.applied = true
  },

  gap() {
    const styles = getComputedStyle(this.container)
    return parseFloat(styles.rowGap) || 12
  },

  // Height left for the pinned screens: the window, minus where the grid starts,
  // minus the header row, the strip/bar row and the note under it. Measured, not
  // guessed: the header and the bar are the two things that change with the layout
  availableHeight(gap) {
    const top = this.container.getBoundingClientRect().top
    const header = this.el.getBoundingClientRect().height
    const strip = this.container.querySelector('[data-main="false"]')
    const bar = document.getElementById("screen-bar")
    const note = this.container.parentElement?.querySelector(":scope > p")
    const below = Math.max(strip?.offsetHeight || 0, bar?.offsetHeight || 0)

    return Math.max(240, window.innerHeight - top - header - below - (note?.offsetHeight || 0) - gap * 2 - 16)
  },

  // Back to whatever the server rendered: sizes, rows and the 16:9 box
  clear() {
    if (!this.applied || !this.container) return
    for (const el of this.container.querySelectorAll("[data-planned]")) {
      for (const prop of ["width", "height", "margin-left", "margin-top", "align-self", "grid-row-start"]) {
        el.style.removeProperty(prop)
      }
      const viewer = el.querySelector("[data-screen-viewer]")
      if (viewer) {
        viewer.style.removeProperty("height")
        viewer.style.removeProperty("aspect-ratio")
      }
      delete el.dataset.planned
    }
    for (const prop of ["--strip-row", "--bar-row", "--chat-row"]) {
      this.container.style.removeProperty(prop)
    }
    this.container.style.maxWidth = this.serverMaxWidth || ""
    this.plannedWidth = undefined
    this.applied = false
    this.plan = null
  }
}
