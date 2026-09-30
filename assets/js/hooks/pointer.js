// Pointers members show each other on the screen sharing pages. With the pointer
// on, the mouse cursor becomes a dot with a short tail that everyone on the
// server's pages sees, and holding the mouse button draws. Drawings stay while
// the button is held, and vanish 3 seconds after it's let go, unless the member
// starts drawing again before that. Shapes drawn in one stroke can set off special
// effects, and a circle with a click in its middle is a target.
//
// Positions travel relative to what the pointer is over: a stream's picture, so
// it lands on the same spot of the game for everyone, or the page, as a share of
// its width. Each page gets them in batches, and plays them back slightly delayed
// so remote pointers move smoothly instead of jumping from batch to batch

import {drawDot, drawName, drawStroke, drawTail, Sparkles} from "../pointer/render"
import {Effects} from "../pointer/effects"
import {recognize} from "../pointer/shapes"
import {Mutes} from "../pointer/mutes"

const SEND_INTERVAL_MS = 50
const MAX_BATCH = 40
// How far behind remote pointers are played, to smooth out the network
const PLAYBACK_DELAY_MS = 120
// How much of its path a pointer's tail shows
const TAIL_MS = 140
// Drawings stay this long after the button is let go, fading out at the end
const DRAWING_STAYS_MS = 3_000
const DRAWING_FADE_MS = 500
// Moving less than this while holding the button is still a click
const DRAW_THRESHOLD_PX = 4
// Positions closer than this to the last one are hand shake
const MIN_MOVE_PX = 1.5
// Pointers not heard of for this long left without saying so
const STALE_MS = 60_000
// Effects a page can set off, the server allows one every 1.5 seconds
const EFFECT_INTERVAL_MS = 1_500
// After a circle, how long a click in its middle still makes it a target, and how
// close to the middle, as a share of the circle's size
const TARGET_WAIT_MS = 700
const TARGET_CENTER = 0.3

const STYLES = ["matte", "glossy", "neon", "sparkle", "rainbow", "pixel", "comet"]
const DEFAULTS = {on: false, color: 5, style: "neon", width: 10, hideOthers: false, muteEffects: false}
const SETTINGS_KEY = "pointer:settings"

function loadSettings() {
  try {
    const saved = JSON.parse(localStorage.getItem(SETTINGS_KEY) ?? "{}")
    const settings = {...DEFAULTS, ...saved}
    if (!STYLES.includes(settings.style)) settings.style = DEFAULTS.style
    if (!(settings.color >= 0 && settings.color <= 9)) settings.color = DEFAULTS.color
    settings.width = Math.min(24, Math.max(4, Math.round(Number(settings.width) || DEFAULTS.width)))
    return settings
  } catch {
    return {...DEFAULTS}
  }
}

function saveSettings(settings) {
  try {
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings))
  } catch {
    // Storage can be blocked, the settings just aren't remembered then
  }
}

const round = value => Math.round(value * 10_000) / 10_000
const clamp = (value, min, max) => Math.min(Math.max(value, min), max)

// The part of a video element showing the picture, without the black bars
function pictureRect(video) {
  const rect = video.getBoundingClientRect()
  if (!video.videoWidth || !video.videoHeight) return rect

  const scale = Math.min(rect.width / video.videoWidth, rect.height / video.videoHeight)
  const width = video.videoWidth * scale
  const height = video.videoHeight * scale
  return {
    left: rect.left + (rect.width - width) / 2,
    top: rect.top + (rect.height - height) / 2,
    width,
    height
  }
}

const anchorKey = anchor => `${anchor.k}:${anchor.i}`

function newUser(id, userId, name) {
  return {
    id,
    userId,
    name,
    look: {color: "#3b82f6", style: "neon", width: 10},
    queue: [],
    offset: null,
    head: null,
    trail: [],
    strokes: [],
    drawing: false,
    releasedAt: null,
    lastSeen: performance.now()
  }
}

export const Pointer = {
  mounted() {
    this.pageKey = this.el.dataset.pageKey
    this.settings = loadSettings()
    this.palette = [...this.el.querySelectorAll("[data-pointer-color]")].map(el => el.dataset.hex)
    this.users = new Map()
    this.me = newUser("me", null, "")
    this.effects = new Effects()
    this.sparkles = new Sparkles()
    this.pending = []
    this.lastEffectAt = -Infinity

    this.setupCanvas()
    this.setupSettings()
    this.setupInput()

    this.handleEvent("pointer:move", message => this.receiveMove(message))
    this.handleEvent("pointer:off", ({s}) => this.receiveOff(s))
    this.handleEvent("pointer:effect", message => this.receiveEffect(message))

    this.sendTimer = setInterval(() => this.flush(), SEND_INTERVAL_MS)
    this.lastFrame = performance.now()
    this.frame = requestAnimationFrame(now => this.render(now))
    this.applySettings()
  },

  destroyed() {
    this.sendOff()
    clearInterval(this.sendTimer)
    cancelAnimationFrame(this.frame)
    this.teardownInput()
    window.removeEventListener("resize", this.onResize)
    this.canvas.remove()
    document.documentElement.classList.remove("pointer-on")
  },

  // Canvas

  setupCanvas() {
    this.canvas = document.createElement("canvas")
    this.canvas.setAttribute("aria-hidden", "true")
    Object.assign(this.canvas.style, {
      position: "fixed",
      inset: "0",
      width: "100vw",
      height: "100vh",
      pointerEvents: "none",
      zIndex: "45"
    })
    document.body.appendChild(this.canvas)
    this.ctx = this.canvas.getContext("2d")

    this.onResize = () => {
      const ratio = window.devicePixelRatio || 1
      this.canvas.width = Math.round(window.innerWidth * ratio)
      this.canvas.height = Math.round(window.innerHeight * ratio)
      this.ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
    }
    window.addEventListener("resize", this.onResize)
    this.onResize()
  },

  // Where anchored positions are on the screen right now. Rectangles are only
  // measured once a frame, however many points use them
  rectFor(anchor) {
    const key = anchorKey(anchor)
    if (this.rects.has(key)) return this.rects.get(key)

    let rect = null
    if (anchor.k === "s") {
      const video = document.querySelector(`[data-pointer-stream="${CSS.escape(anchor.i)}"]`)
      if (video) rect = pictureRect(video)
    } else if (anchor.i === this.pageKey) {
      rect = document.querySelector("[data-pointer-page]")?.getBoundingClientRect() ?? null
    }

    this.rects.set(key, rect)
    return rect
  },

  toScreen(point) {
    const rect = this.rectFor(point.a)
    if (!rect) return null
    const scaleY = point.a.k === "s" ? rect.height : rect.width
    return {x: rect.left + point.x * rect.width, y: rect.top + point.y * scaleY}
  },

  // What's under the screen position: a stream's picture, or else the page
  anchorAt(clientX, clientY) {
    for (const video of document.querySelectorAll("[data-pointer-stream]")) {
      const rect = pictureRect(video)
      if (
        rect.width > 0 &&
        clientX >= rect.left &&
        clientX <= rect.left + rect.width &&
        clientY >= rect.top &&
        clientY <= rect.top + rect.height
      ) {
        return {k: "s", i: video.dataset.pointerStream}
      }
    }
    return {k: "p", i: this.pageKey}
  },

  fromScreen(anchor, clientX, clientY) {
    this.rects = new Map()
    const rect = this.rectFor(anchor)
    if (!rect || rect.width === 0) return null

    const scaleY = anchor.k === "s" ? rect.height : rect.width
    const x = (clientX - rect.left) / rect.width
    const y = (clientY - rect.top) / scaleY
    // The server only takes positions around the stream or page
    return anchor.k === "s"
      ? {x: round(clamp(x, -1, 2)), y: round(clamp(y, -1, 2))}
      : {x: round(clamp(x, -1, 2)), y: round(clamp(y, -1, 50))}
  },

  // Settings

  setupSettings() {
    this.toggleButton = this.el.querySelector("[data-pointer-toggle]")
    this.widthInput = this.el.querySelector("[data-pointer-width]")
    this.widthLabel = this.el.querySelector("[data-pointer-width-label]")
    this.preview = this.el.querySelector("[data-pointer-preview]")
    this.hideOthersButton = this.el.querySelector("[data-pointer-hide-others]")
    this.muteEffectsButton = this.el.querySelector("[data-pointer-mute-effects]")

    this.toggleButton.addEventListener("click", () => this.update({on: !this.settings.on}))
    this.el.querySelectorAll("[data-pointer-color]").forEach(button => {
      button.addEventListener("click", () => this.update({color: Number(button.dataset.pointerColor)}))
    })
    this.el.querySelectorAll("[data-pointer-style]").forEach(button => {
      button.addEventListener("click", () => this.update({style: button.dataset.pointerStyle}))
    })
    this.widthInput.addEventListener("input", () => this.update({width: Number(this.widthInput.value)}))
    this.hideOthersButton.addEventListener("click", () =>
      this.update({hideOthers: !this.settings.hideOthers})
    )
    this.muteEffectsButton.addEventListener("click", () => {
      this.update({muteEffects: !this.settings.muteEffects})
      if (this.settings.muteEffects) this.effects.clear()
    })

    // Other tabs follow, like the soundboard's volume
    this.onStorage = event => {
      if (event.key !== SETTINGS_KEY) return
      const wasOn = this.settings.on
      this.settings = loadSettings()
      if (wasOn && !this.settings.on) this.sendOff()
      this.applySettings()
    }
    window.addEventListener("storage", this.onStorage)
  },

  update(changes) {
    const wasOn = this.settings.on
    this.settings = {...this.settings, ...changes}
    saveSettings(this.settings)
    if (wasOn && !this.settings.on) this.sendOff()
    this.applySettings()
  },

  myLook() {
    return {
      color: this.palette[this.settings.color] ?? "#3b82f6",
      style: this.settings.style,
      width: this.settings.width
    }
  },

  applySettings() {
    const {on, color, style, width, hideOthers, muteEffects} = this.settings
    this.me.look = this.myLook()

    document.documentElement.classList.toggle("pointer-on", on)
    this.toggleButton.textContent = on ? "✨ My pointer is on" : "✨ Turn my pointer on"
    this.toggleButton.setAttribute("aria-pressed", String(on))
    this.toggleButton.classList.toggle("bg-indigo-600", !on)
    this.toggleButton.classList.toggle("bg-green-600", on)

    this.el.querySelectorAll("[data-pointer-color]").forEach(button => {
      button.setAttribute("aria-pressed", String(Number(button.dataset.pointerColor) === color))
    })
    this.el.querySelectorAll("[data-pointer-style]").forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.pointerStyle === style))
    })
    this.widthInput.value = String(width)
    this.widthLabel.textContent = `${width}px`

    for (const [button, value] of [[this.hideOthersButton, hideOthers], [this.muteEffectsButton, muteEffects]]) {
      button.setAttribute("aria-pressed", String(value))
      button.querySelector("[data-switch]").textContent = value ? "On" : "Off"
      button.classList.toggle("ring-1", value)
      button.classList.toggle("ring-indigo-400", value)
    }

    if (!on) {
      this.me.head = null
      this.me.trail = []
    }
    this.drawPreview()
  },

  // A sample squiggle in the chosen look, next to the width slider
  drawPreview() {
    const canvas = this.preview
    const ratio = window.devicePixelRatio || 1
    const width = canvas.clientWidth || 280
    const height = canvas.clientHeight || 56
    canvas.width = width * ratio
    canvas.height = height * ratio
    const ctx = canvas.getContext("2d")
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
    ctx.clearRect(0, 0, width, height)

    const points = []
    for (let i = 0; i <= 24; i++) {
      const t = i / 24
      points.push({x: 20 + t * (width - 60), y: height / 2 + Math.sin(t * 2 * Math.PI) * (height / 2 - 14)})
    }
    drawStroke(ctx, points, this.myLook(), 1, performance.now())
    drawDot(ctx, {x: width - 24, y: height / 2}, this.myLook(), performance.now(), false)
  },

  // Input

  setupInput() {
    this.onMove = event => this.pointerMoved(event)
    this.onDown = event => this.pointerDown(event)
    this.onUp = event => this.pointerUp(event)
    this.onLeave = () => this.pointerLeft()
    // A drag ends with a click on whatever it ended over, which it isn't meant for
    this.onClick = event => {
      if (!this.swallowClick) return
      this.swallowClick = false
      event.preventDefault()
      event.stopPropagation()
    }
    this.onDragStart = event => {
      if (this.settings.on) event.preventDefault()
    }

    document.addEventListener("pointermove", this.onMove, {passive: true})
    document.addEventListener("pointerdown", this.onDown, true)
    document.addEventListener("pointerup", this.onUp, true)
    document.addEventListener("pointercancel", this.onUp, true)
    document.addEventListener("click", this.onClick, true)
    document.addEventListener("dragstart", this.onDragStart, true)
    document.documentElement.addEventListener("mouseleave", this.onLeave)
    window.addEventListener("blur", this.onLeave)
  },

  teardownInput() {
    document.removeEventListener("pointermove", this.onMove)
    document.removeEventListener("pointerdown", this.onDown, true)
    document.removeEventListener("pointerup", this.onUp, true)
    document.removeEventListener("pointercancel", this.onUp, true)
    document.removeEventListener("click", this.onClick, true)
    document.removeEventListener("dragstart", this.onDragStart, true)
    document.documentElement.removeEventListener("mouseleave", this.onLeave)
    window.removeEventListener("blur", this.onLeave)
    window.removeEventListener("storage", this.onStorage)
  },

  // Over the floating menu the normal cursor comes back, to click its buttons
  overMenu(event) {
    return event.target instanceof Element && event.target.closest("#soundboard")
  },

  pointerMoved(event) {
    if (!this.settings.on || event.pointerType === "touch") return

    if (this.overMenu(event) && !this.me.drawing && !this.pressed) {
      this.me.head = null
      this.me.trail = []
      return
    }

    if (this.pressed && !this.me.drawing) {
      const moved = Math.hypot(event.clientX - this.pressed.x, event.clientY - this.pressed.y)
      if (moved >= DRAW_THRESHOLD_PX) this.startDrawing()
    }

    // Browsers group fast moves into one event, the grouped ones make smoother lines
    const events = event.getCoalescedEvents?.() ?? []
    for (const e of events.length ? events : [event]) this.addPoint(e.clientX, e.clientY)
  },

  pointerDown(event) {
    if (!this.settings.on || event.button !== 0 || event.pointerType === "touch") return
    if (this.overMenu(event)) return
    if (event.target.closest?.("input, textarea, select, [contenteditable]")) return

    this.pressed = {x: event.clientX, y: event.clientY}
  },

  startDrawing() {
    this.swallowClick = true
    this.me.drawing = true
    this.me.releasedAt = null
    // The line keeps what it's over at its start, so it stays in one piece
    this.strokeAnchor = this.anchorAt(this.pressed.x, this.pressed.y)
    this.strokeScreen = [{x: this.pressed.x, y: this.pressed.y}]
    this.me.strokes.push({look: this.myLook(), points: []})
    this.addPoint(this.pressed.x, this.pressed.y, true)
  },

  pointerUp(event) {
    if (!this.pressed) return
    this.pressed = null

    if (!this.me.drawing) {
      this.clickedInCircle(event)
      return
    }

    this.addPoint(event.clientX, event.clientY, true)
    this.me.drawing = false
    this.me.releasedAt = performance.now()
    // The last position goes out with the button up, which ends the line for everyone
    this.queuePoint(this.strokeAnchor, event.clientX, event.clientY, 0)

    const shape = recognize(this.strokeScreen)
    if (shape?.name === "circle") this.waitForTarget(shape)
    else if (shape) this.setOffEffect(shape, this.strokeAnchor)
    this.strokeAnchor = null

    // Browsers send the click right after the button goes up, when they send one
    // at all, so a later click is a real one
    setTimeout(() => (this.swallowClick = false))
  },

  pointerLeft() {
    if (!this.settings.on || this.me.drawing) return
    this.me.head = null
    this.me.trail = []
    this.sendOff()
  },

  addPoint(clientX, clientY, force = false) {
    const now = performance.now()
    const last = this.lastScreen
    if (!force && last && Math.hypot(clientX - last.x, clientY - last.y) < MIN_MOVE_PX) return
    this.lastScreen = {x: clientX, y: clientY}

    const anchor = this.me.drawing ? this.strokeAnchor : this.anchorAt(clientX, clientY)
    const position = this.fromScreen(anchor, clientX, clientY)
    if (!position) return

    const point = {a: anchor, x: position.x, y: position.y, t: now}
    this.me.head = point
    this.me.lastSeen = now

    if (this.me.drawing) {
      this.me.strokes[this.me.strokes.length - 1].points.push(point)
      this.strokeScreen.push({x: clientX, y: clientY})
    } else {
      this.me.trail.push(point)
    }

    if (this.me.look.style === "sparkle" && Math.random() < 0.5) {
      this.sparkles.spawn(clientX, clientY, this.me.look.color, this.me.drawing ? 2 : 1)
    }

    this.queuePoint(anchor, clientX, clientY, this.me.drawing ? 1 : 0, position)
  },

  queuePoint(anchor, clientX, clientY, held, position = this.fromScreen(anchor, clientX, clientY)) {
    if (!position) return
    this.pending.push({a: anchor, p: [position.x, position.y, Math.round(performance.now()), held]})
  },

  // Sends what moved since the last batch, one batch per thing it was over
  flush() {
    if (this.pending.length === 0) return
    const pending = this.pending
    this.pending = []
    const {color, style, width} = this.settings

    let batch = null
    const send = () => {
      if (!batch) return
      // Too many positions for one batch only happens after a hiccup, keep every other
      let points = batch.points
      while (points.length > MAX_BATCH) points = points.filter((_, i) => i % 2 === 0 || i === points.length - 1)
      this.pushEvent("pointer:move", {a: batch.a, p: points, c: color, st: style, w: width})
    }

    for (const item of pending) {
      if (!batch || anchorKey(batch.a) !== anchorKey(item.a)) {
        send()
        batch = {a: item.a, points: []}
      }
      batch.points.push(item.p)
    }
    send()
  },

  sendOff() {
    this.pending = []
    try {
      this.pushEvent("pointer:off", {})
    } catch {
      // The page is going away, and the others forget its pointer on their own
    }
  },

  // A circle is a shockwave, unless a click in its middle soon after makes it a target
  waitForTarget(shape) {
    clearTimeout(this.circle?.timer)
    const anchor = this.strokeAnchor
    const size = Math.max(shape.width, shape.height)
    const circle = {shape, anchor, size}
    circle.timer = setTimeout(() => {
      this.circle = null
      this.setOffEffect(shape, anchor)
    }, TARGET_WAIT_MS)
    this.circle = circle
  },

  clickedInCircle(event) {
    const circle = this.circle
    if (!circle) return

    const {center} = circle.shape
    if (Math.hypot(event.clientX - center.x, event.clientY - center.y) > circle.size * TARGET_CENTER) return

    clearTimeout(circle.timer)
    this.circle = null
    // The click was for the target, not for whatever is under it
    this.swallowClick = true
    setTimeout(() => (this.swallowClick = false))
    this.setOffEffect({...circle.shape, name: "target"}, circle.anchor)
  },

  setOffEffect(shape, anchor) {
    const now = performance.now()
    if (now - this.lastEffectAt < EFFECT_INTERVAL_MS) return
    this.lastEffectAt = now

    const position = this.fromScreen(anchor, shape.center.x, shape.center.y)
    if (!position) return

    this.pushEvent("pointer:effect", {e: shape.name, a: anchor, x: position.x, y: position.y})
    this.showEffect(shape.name, anchor, position)
  },

  // Remote pointers

  receiveMove({s, u, n, a, p, c, st, w}) {
    let user = this.users.get(s)
    if (!user) {
      user = newUser(s, u, n)
      this.users.set(s, user)
    }

    const now = performance.now()
    user.lastSeen = now
    user.name = n
    user.look = {color: this.palette[c] ?? "#3b82f6", style: st, width: w}

    // Plays positions back at the pace they were sent, a little behind, on this
    // page's clock. The delay is only reset when the network got much faster or slower
    const lastTime = p[p.length - 1][2]
    const offset = now - lastTime + PLAYBACK_DELAY_MS
    if (user.offset === null || Math.abs(offset - user.offset) > 250) user.offset = offset

    for (const [x, y, t, held] of p) {
      user.queue.push({a, x, y, t: t + user.offset, held: held === 1})
    }
    // Pointers that went quiet a while ago come back without a long catch up
    if (user.queue.length > 200) user.queue = user.queue.slice(-200)
  },

  receiveOff(senderId) {
    const user = this.users.get(senderId)
    if (!user) return
    user.queue = []
    user.head = null
    user.trail = []
    if (user.drawing) {
      user.drawing = false
      user.releasedAt = performance.now()
    }
  },

  receiveEffect({u, e, a, x, y}) {
    if (Mutes.has(u)) return
    this.showEffect(e, a, {x, y})
  },

  showEffect(name, anchor, position) {
    if (this.settings.muteEffects) return
    const point = {a: anchor, x: position.x, y: position.y}
    this.effects.add(name, () => {
      this.rects = this.rects ?? new Map()
      return this.toScreen(point)
    })
  },

  // Moves remote pointers along to where they were at `now`
  play(user, now) {
    while (user.queue.length && user.queue[0].t <= now) {
      const point = user.queue.shift()
      user.head = point

      if (point.held) {
        if (!user.drawing) {
          user.drawing = true
          user.releasedAt = null
          user.strokes.push({look: {...user.look}, points: []})
          user.trail = []
        }
        user.strokes[user.strokes.length - 1].points.push(point)
      } else {
        if (user.drawing) {
          user.drawing = false
          user.releasedAt = point.t
        }
        user.trail.push(point)
      }

      if (user.look.style === "sparkle" && Math.random() < 0.4) {
        const at = this.toScreen(point)
        if (at) this.sparkles.spawn(at.x, at.y, user.look.color, point.held ? 2 : 1)
      }
    }
  },

  // Rendering

  render(now) {
    this.frame = requestAnimationFrame(time => this.render(time))
    const dt = Math.min(0.1, (now - this.lastFrame) / 1000)
    this.lastFrame = now
    this.rects = new Map()

    const ctx = this.ctx
    ctx.clearRect(0, 0, window.innerWidth, window.innerHeight)

    for (const [id, user] of this.users) {
      this.play(user, now)
      if (now - user.lastSeen > STALE_MS && !user.queue.length) {
        this.users.delete(id)
        continue
      }
      if (this.settings.hideOthers || Mutes.has(user.userId)) continue
      this.drawUser(ctx, user, now, true)
    }

    if (this.settings.on) this.drawUser(ctx, this.me, now, false)
    else this.drawStrokes(ctx, this.me, now)

    this.sparkles.draw(ctx, now, dt)
    if (!this.settings.muteEffects) this.effects.draw(ctx, now, window.innerWidth, window.innerHeight)
  },

  drawStrokes(ctx, user, now) {
    if (user.strokes.length === 0) return

    // Drawings vanish together, a while after the button was let go
    let alpha = 1
    if (!user.drawing && user.releasedAt !== null) {
      const age = now - user.releasedAt
      if (age >= DRAWING_STAYS_MS) {
        user.strokes = []
        return
      }
      alpha = Math.min(1, (DRAWING_STAYS_MS - age) / DRAWING_FADE_MS)
    }

    for (const stroke of user.strokes) {
      const points = stroke.points.map(p => this.toScreen(p)).filter(Boolean)
      drawStroke(ctx, points, stroke.look, alpha, now)
    }
  },

  drawUser(ctx, user, now, remote) {
    this.drawStrokes(ctx, user, now)
    if (!user.head) return

    // The tail covers the last split second of movement, so it shrinks away when
    // the pointer stops. Remote positions were moved to this page's clock when played
    const since = now - TAIL_MS
    user.trail = user.trail.filter(p => p.t >= since - 50)
    if (!user.drawing) {
      const tail = user.trail.filter(p => p.t >= since).map(p => this.toScreen(p)).filter(Boolean)
      drawTail(ctx, tail, user.look, now)
    }

    const head = this.toScreen(user.head)
    if (!head) return
    drawDot(ctx, head, user.look, now, user.drawing)
    if (remote) drawName(ctx, head, user.name, user.look)
  }
}
