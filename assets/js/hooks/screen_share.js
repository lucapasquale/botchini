// WebRTC hooks for screen sharing. The browser always makes the offer and the
// server answers, with ICE candidates trickled both ways through the LiveView.

// Tuned for games: the source's full resolution at up to 60 fps, only for
// friends, so the bitrate can be high. Browsers were reporting CPU-limited
// encoders most of the time at 1080p60 under a 20 Mbps ceiling, which viewers see
// as stutter, so the ceiling is lower and tabs are capped at 30 fps
const MAX_BITRATE = 8_000_000
const MAX_FRAMERATE = 60
// Tabs are slides, pages and video: half the frames and sharper ones suit them
const TAB_MAX_FRAMERATE = 30
// Browsers start sending low and take a while to trust the connection, which
// makes the first seconds blurry, so Chrome and Edge are told to start higher
const START_BITRATE_KBPS = 4_000
const RETRY_DELAY_MS = 2_000
// Stereo Opus at this bitrate is enough for music
const AUDIO_BITRATE = 128_000
// How often pages tell the server how their connection is doing, for its metrics
const STATS_INTERVAL_MS = 10_000

class Connection {
  constructor(hook, onConnectionState, params = {}) {
    this.hook = hook
    this.params = params
    this.pendingCandidates = []
    this.pc = new RTCPeerConnection({iceServers: JSON.parse(hook.el.dataset.iceServers)})

    this.pc.onicecandidate = ({candidate}) => {
      if (candidate) hook.pushEvent("ice_candidate", {...params, ...candidate.toJSON()})
    }
    this.pc.onconnectionstatechange = () => onConnectionState(this.pc.connectionState)
  }

  // Resolves once the server answer is applied, rejects with a message to show
  async negotiate({startBitrateKbps} = {}) {
    await this.pc.setLocalDescription(withStereoAudio(await this.pc.createOffer()))

    const reply = await new Promise(resolve => {
      this.hook.pushEvent("offer", {...this.params, ...this.pc.localDescription.toJSON()}, resolve)
    })
    if (reply.error) throw new Error(reply.error)

    const answer = startBitrateKbps ? withStartBitrate(reply.answer, startBitrateKbps) : reply.answer
    await this.pc.setRemoteDescription(answer)
    this.pendingCandidates.forEach(candidate => this.pc.addIceCandidate(candidate))
    this.pendingCandidates = []
  }

  // Candidates can arrive before the answer is applied, and adding them then fails
  addRemoteCandidate(candidate) {
    if (this.pc.remoteDescription) {
      this.pc.addIceCandidate(candidate).catch(error => console.warn("Bad ICE candidate", error))
    } else {
      this.pendingCandidates.push(candidate)
    }
  }

  close() {
    this.pc.onconnectionstatechange = null
    this.pc.close()
  }
}

// Chrome plays and sends Opus in mono, at about 32 kbps, unless the SDP asks for
// stereo. The server answers with the parameters offered, and would turn down
// the audio if it asked for them itself
function withStereoAudio({type, sdp}) {
  const payload = sdp.match(/^a=rtpmap:(\d+) opus\/48000\/2/im)?.[1]
  if (!payload) return {type, sdp}

  const params = `stereo=1;sprop-stereo=1;maxaveragebitrate=${AUDIO_BITRATE}`
  // SDP lines end in \r\n, and . would match the \r
  const fmtp = new RegExp(`^a=fmtp:${payload} [^\\r\\n]*`, "m")
  sdp = fmtp.test(sdp)
    ? sdp.replace(fmtp, line => `${line};${params}`)
    : sdp.replace(new RegExp(`^a=rtpmap:${payload} [^\\r\\n]*`, "m"), line => `${line}\r\na=fmtp:${payload} ${params}`)

  return {type, sdp}
}

// Chrome and Edge read the bitrate to start sending at from the answer's video
// formats, and other browsers ignore it
function withStartBitrate({type, sdp}, kbps) {
  const param = `x-google-start-bitrate=${kbps}`
  const payloads = [...sdp.matchAll(/^a=rtpmap:(\d+) (?:H264|VP8)\//gm)].map(([, payload]) => payload)

  for (const payload of payloads) {
    // SDP lines end in \r\n, and . would match the \r
    const fmtp = new RegExp(`^a=fmtp:${payload} [^\\r\\n]*`, "m")
    sdp = fmtp.test(sdp)
      ? sdp.replace(fmtp, line => `${line};${param}`)
      : sdp.replace(new RegExp(`^a=rtpmap:${payload} [^\\r\\n]*`, "m"), line => `${line}\r\na=fmtp:${payload} ${param}`)
  }

  return {type, sdp}
}

// WebRTC's stats count up from the start, so reports take the difference with
// the previous ones. Values a browser doesn't have are left out
function rtpStats(report, type) {
  const stats = {}
  report.forEach(entry => {
    if (entry.type === type && (entry.kind === "video" || entry.kind === "audio")) stats[entry.kind] = entry
  })
  return stats
}

const change = (now, before, key) => (now[key] ?? 0) - (before[key] ?? 0)
const percent = (part, whole) => (whole > 0 ? (Math.max(part, 0) / whole) * 100 : undefined)
const seconds = (now, before) => (now && before ? (now.timestamp - before.timestamp) / 1000 : 0)

function receivedVideo(now, before) {
  const elapsed = seconds(now, before)
  if (elapsed <= 0) return undefined

  const [decoded, dropped] = [change(now, before, "framesDecoded"), change(now, before, "framesDropped")]
  const [received, lost] = [change(now, before, "packetsReceived"), change(now, before, "packetsLost")]
  const emitted = change(now, before, "jitterBufferEmittedCount")

  return {
    kbps: (change(now, before, "bytesReceived") * 8) / 1000 / elapsed,
    fps: now.framesPerSecond ?? decoded / elapsed,
    height: now.frameHeight,
    frames_dropped_percent: percent(dropped, decoded + dropped),
    freezes: now.freezeCount === undefined ? undefined : change(now, before, "freezeCount"),
    // A count alone can't tell four hitches from one four second stall, and the
    // time a report covers grows when browsers throttle timers in background tabs,
    // so the freeze's own duration and the interval both go along with it
    frozen_percent:
      now.totalFreezesDuration === undefined
        ? undefined
        : percent(change(now, before, "totalFreezesDuration"), elapsed),
    elapsed_ms: elapsed * 1000,
    packet_loss_percent: percent(lost, received + Math.max(lost, 0)),
    jitter_ms: now.jitter * 1000,
    jitter_buffer_ms: emitted > 0 ? (change(now, before, "jitterBufferDelay") / emitted) * 1000 : undefined
  }
}

function receivedAudio(report, now, before) {
  const elapsed = seconds(now, before)
  if (elapsed <= 0) return undefined

  const [received, lost] = [change(now, before, "packetsReceived"), change(now, before, "packetsLost")]
  const fmtp = report.get(now.codecId)?.sdpFmtpLine ?? ""

  return {
    kbps: (change(now, before, "bytesReceived") * 8) / 1000 / elapsed,
    packet_loss_percent: percent(lost, received + Math.max(lost, 0)),
    concealed_percent: percent(change(now, before, "concealedSamples"), change(now, before, "totalSamplesReceived")),
    jitter_ms: now.jitter * 1000,
    stereo: /(^|;)\s*stereo=1/.test(fmtp)
  }
}

function sent(now, before) {
  const elapsed = seconds(now, before)
  if (elapsed <= 0) return undefined

  return {
    kbps: (change(now, before, "bytesSent") * 8) / 1000 / elapsed,
    fps: now.framesPerSecond,
    height: now.frameHeight
  }
}

export const ScreenBroadcast = {
  mounted() {
    this.stream = null
    this.connection = null
    this.preview = this.el.querySelector("#screen-broadcast-preview")
    this.status = this.el.querySelector("[data-screen-status]")

    // Screen capture needs a user gesture, so buttons are handled here instead of
    // through phx-click, which would lose it on the round trip to the server
    this.el.addEventListener("click", event => {
      if (event.target.closest("[data-screen-start]")) this.start()
      if (event.target.closest("[data-screen-switch]")) this.switchSource()
      if (event.target.closest("[data-screen-stop]")) this.stop()
    })

    this.handleEvent("screen:ice_candidate", candidate => this.connection?.addRemoteCandidate(candidate))
    this.handleEvent("screen:ended", () => this.teardown())
    this.statsTimer = setInterval(() => this.reportStats(), STATS_INTERVAL_MS)
  },

  // What the browser sends, and why it's holding back quality, if it is
  async reportStats() {
    const pc = this.connection?.pc
    if (pc?.connectionState !== "connected") return

    const report = await pc.getStats()
    const now = rtpStats(report, "outbound-rtp")
    const before = this.lastStats?.pc === pc ? this.lastStats : null
    this.lastStats = {pc, ...now}
    if (!before) return

    const remote = rtpStats(report, "remote-inbound-rtp").video
    const video = now.video && before.video ? sent(now.video, before.video) : undefined

    this.pushEvent("broadcast_stats", {
      video: video && {
        ...video,
        rtt_ms: remote?.roundTripTime === undefined ? undefined : remote.roundTripTime * 1000,
        packet_loss_percent: remote?.fractionLost === undefined ? undefined : remote.fractionLost * 100
      },
      audio: now.audio && before.audio ? sent(now.audio, before.audio) : undefined,
      quality_limitation: now.video?.qualityLimitationReason
    })
  },

  // The new LiveView process doesn't know about the old connection, and the room
  // drops it once the previous process is gone, so sharing has to be negotiated again
  reconnected() {
    if (this.stream) this.connect()
  },

  destroyed() {
    clearInterval(this.statsTimer)
    this.teardown()
  },

  async start() {
    try {
      this.stream = await this.capture()
    } catch (error) {
      // The user closed the picker
      if (error.name !== "NotAllowedError") this.setStatus(`Couldn't capture the screen: ${error.message}`)
      return
    }

    this.showSharingControls(true)
    await this.connect()
  },

  async connect() {
    this.connection?.close()
    this.setStatus("Connecting...")

    const connection = new Connection(this, state => this.onConnectionState(connection, state))
    this.connection = connection

    const [video] = this.stream.getVideoTracks()
    const [audio] = this.stream.getAudioTracks()
    const encoding = {
      maxBitrate: MAX_BITRATE,
      maxFramerate: this.isTab() ? TAB_MAX_FRAMERATE : MAX_FRAMERATE
    }

    // Both transceivers always exist, so switching sources only replaces tracks
    // and never needs a renegotiation, even when the new source has no audio
    this.videoSender = connection.pc.addTransceiver(video, {
      direction: "sendonly",
      streams: [this.stream],
      sendEncodings: [encoding]
    }).sender
    this.audioSender = connection.pc.addTransceiver(audio ?? "audio", {
      direction: "sendonly",
      streams: [this.stream]
    }).sender
    this.tune()

    try {
      await connection.negotiate({startBitrateKbps: START_BITRATE_KBPS})
      // Some browsers ignore encoding parameters set before negotiating
      this.tune()
    } catch (error) {
      this.teardown()
      this.setStatus(error.message)
    }
  },

  async switchSource() {
    let stream
    try {
      stream = await this.capture()
    } catch (_error) {
      return
    }

    this.stopTracks()
    this.stream = stream
    await this.videoSender.replaceTrack(stream.getVideoTracks()[0])
    await this.audioSender.replaceTrack(stream.getAudioTracks()[0] ?? null)
    this.tune()
  },

  stop() {
    this.teardown()
    this.pushEvent("stop", {})
  },

  async capture() {
    const stream = await navigator.mediaDevices.getDisplayMedia({
      video: {frameRate: {ideal: MAX_FRAMERATE, max: MAX_FRAMERATE}},
      audio: true,
      systemAudio: "include",
      selfBrowserSurface: "exclude"
    })

    this.preview.srcObject = stream
    this.showAudioNotice(stream)
    // "browser" is a tab, "window" and "monitor" can be anything, games included
    this.surface = stream.getVideoTracks()[0].getSettings().displaySurface ?? null
    this.pushEvent("source", {surface: this.surface})
    // Clicking the browser's own "Stop sharing" bar ends the share too
    stream.getVideoTracks()[0].addEventListener("ended", () => {
      if (this.stream === stream) this.stop()
    })

    return stream
  },

  // Browsers silently leave audio out when they can't or weren't allowed to
  // capture it, so the broadcaster knows why viewers hear nothing
  showAudioNotice(stream) {
    const notice = this.el.querySelector("[data-screen-audio]")
    const hasAudio = stream && stream.getAudioTracks().length > 0

    notice.hidden = !stream || hasAudio
    notice.textContent = navigator.userAgent.includes("Firefox")
      ? "No sound is being shared: Firefox can't share audio, use Chrome or Edge for that."
      : "No sound is being shared: pick a tab or your entire screen and turn on audio sharing in the picker."
  },

  // When the connection or the CPU can't keep up, lowers both resolution and
  // frame rate a little. Keeping the frame rate instead drops to 720p or lower,
  // and keeping the resolution makes games stutter
  tune() {
    const track = this.stream?.getVideoTracks()[0]
    if (!track) return

    // Games read better smooth, slides and pages read better sharp, and the
    // browser gives up quality along the hinted axis when it has to
    track.contentHint = this.isTab() ? "detail" : "motion"

    if (this.videoSender) {
      const params = this.videoSender.getParameters()
      params.degradationPreference = "balanced"
      const encodings = params.encodings?.length ? params.encodings : [{}]

      for (const encoding of encodings) {
        encoding.maxBitrate = MAX_BITRATE
        encoding.maxFramerate = this.isTab() ? TAB_MAX_FRAMERATE : MAX_FRAMERATE
      }

      params.encodings = encodings
      this.videoSender.setParameters(params).catch(() => {})
    }
  },

  isTab() {
    return this.surface === "browser"
  },

  onConnectionState(connection, state) {
    if (connection !== this.connection) return

    if (state === "connected") this.setStatus("You're live!")
    if (state === "disconnected") this.setStatus("Connection lost, reconnecting...")
    if (state === "failed") {
      this.setStatus("Connection failed, retrying...")
      setTimeout(() => {
        if (this.connection === connection) this.connect()
      }, RETRY_DELAY_MS)
    }
  },

  teardown() {
    this.connection?.close()
    this.connection = null
    this.stopTracks()
    this.stream = null
    this.preview.srcObject = null
    this.showAudioNotice(null)
    this.showSharingControls(false)
  },

  stopTracks() {
    this.stream?.getTracks().forEach(track => track.stop())
  },

  showSharingControls(sharing) {
    this.el.querySelector("[data-screen-start]").hidden = sharing
    this.el.querySelector("[data-screen-switch]").hidden = !sharing
    this.el.querySelector("[data-screen-stop]").hidden = !sharing
    if (!sharing) this.setStatus("")
  },

  setStatus(text) {
    this.status.textContent = text
  }
}

export const ScreenViewer = {
  mounted() {
    this.roomId = this.el.dataset.roomId
    this.video = this.el.querySelector("video")
    this.status = this.el.querySelector("[data-screen-status]")
    this.handleEvent(`screen:${this.roomId}:ice_candidate`, candidate => this.connection?.addRemoteCandidate(candidate))
    this.handleEvent(`screen:${this.roomId}:ended`, () => this.teardown())
    this.handleEvent(`screen:${this.roomId}:reconnect`, () => this.connect())
    this.mountControls()
    this.mountInfo()
    this.connect()
    this.statsTimer = setInterval(() => this.reportStats(), STATS_INTERVAL_MS)
  },

  // The badge on a pinned screen: what the stream is, at what size, and how many
  // frames per second actually arrive in this browser. It lives inside the tile,
  // and only exists while the screen is pinned
  mountInfo() {
    const info = this.el.querySelector("[data-stream-info]")
    if (!info) return this.unmountInfo()
    if (this.info === info) return this.updateResolution()

    this.unmountInfo()
    this.info = info
    this.resolution = info.querySelector("[data-stream-info-resolution]")
    this.fps = info.querySelector("[data-stream-info-fps]")

    this.updateResolution()
    this.video.addEventListener("loadedmetadata", () => this.updateResolution())
    this.video.addEventListener("resize", () => this.updateResolution())
    this.fpsTimer = setInterval(() => this.updateFps(), 1000)
  },

  unmountInfo() {
    clearInterval(this.fpsTimer)
    this.fpsTimer = null
    this.info = null
    this.resolution = null
    this.fps = null
    this.lastQuality = null
  },

  // What the publisher sends, not what the tile is sized at
  updateResolution() {
    if (!this.resolution) return
    const {videoWidth: width, videoHeight: height} = this.video
    this.resolution.textContent = width && height ? `${width}×${height}` : "—"
  },

  // Decoded frames over the last second: what the viewer really sees, so a stream
  // that arrives at 12 fps says so even if the publisher claims 60
  updateFps() {
    if (!this.fps) return
    const quality = this.video.getVideoPlaybackQuality?.() || this.video.webkitGetVideoPlaybackQuality?.()
    const frames = quality?.totalVideoFrames
    const now = performance.now()
    const before = this.lastQuality
    this.lastQuality = {frames, at: now}

    if (before?.frames === undefined || frames === undefined || this.video.paused) return
    const elapsed = now - before.at
    if (elapsed <= 0) return
    this.fps.textContent = `${Math.round(((frames - before.frames) * 1000) / elapsed)} fps`
  },

  // How the screen comes through: smooth, lossy, frozen, stereo...
  async reportStats() {
    const pc = this.connection?.pc
    if (pc?.connectionState !== "connected") return

    const report = await pc.getStats()
    const now = rtpStats(report, "inbound-rtp")
    const before = this.lastStats?.pc === pc ? this.lastStats : null
    this.lastStats = {pc, ...now}
    if (!before) return

    this.pushEvent("viewer_stats", {
      room_id: this.roomId,
      video: now.video && before.video ? receivedVideo(now.video, before.video) : undefined,
      audio: now.audio && before.audio ? receivedAudio(report, now.audio, before.audio) : undefined
    })
  },

  // Streams start muted, as browsers only autoplay those. The slider brings back
  // the last volume when unmuting
  mountControls() {
    this.controls = this.el.querySelector("[data-video-controls]")
    this.playButton = this.controls.querySelector("[data-video-play]")
    this.muteButton = this.controls.querySelector("[data-video-mute]")
    this.volumeInput = this.controls.querySelector("[data-video-volume]")
    this.fullscreenButton = this.controls.querySelector("[data-video-fullscreen]")
    this.lastVolume = 1

    this.playButton.addEventListener("click", () => {
      if (this.video.paused) this.video.play().catch(() => {})
      else this.video.pause()
    })

    this.muteButton.addEventListener("click", () => {
      if (this.isMuted()) {
        this.video.volume = this.lastVolume
        this.video.muted = false
      } else {
        this.video.muted = true
      }
    })

    this.volumeInput.addEventListener("input", () => {
      const volume = Number(this.volumeInput.value)
      this.video.volume = volume
      this.video.muted = volume === 0
      if (volume > 0) this.lastVolume = volume
    })

    // Phones without full screen for elements can still show the video alone
    this.fullscreenButton.addEventListener("click", () => {
      if (document.fullscreenElement) document.exitFullscreen()
      else if (this.el.requestFullscreen) this.el.requestFullscreen().catch(() => {})
      else this.video.webkitEnterFullscreen?.()
    })

    this.renderControls = this.renderControls.bind(this)
    for (const event of ["play", "pause", "volumechange"]) this.video.addEventListener(event, this.renderControls)
    this.el.addEventListener("fullscreenchange", this.renderControls)
    this.renderControls()
  },

  isMuted() {
    return this.video.muted || this.video.volume === 0
  },

  renderControls() {
    const paused = this.video.paused
    const muted = this.isMuted()
    const fullscreen = document.fullscreenElement === this.el

    this.controls.toggleAttribute("data-paused", paused)
    this.controls.toggleAttribute("data-muted", muted)
    this.controls.toggleAttribute("data-fullscreen", fullscreen)
    this.playButton.title = paused ? "Play" : "Pause"
    this.muteButton.title = muted ? "Unmute" : "Mute"
    this.fullscreenButton.title = fullscreen ? "Exit full screen" : "Full screen"
    this.volumeInput.value = muted ? 0 : this.video.volume
  },

  reconnected() {
    this.connect()
  },

  // A pinned screen gains the badge (and an unpinned one loses it) without the
  // hook being remounted, so pick it up here
  updated() {
    this.mountInfo()
  },

  destroyed() {
    clearInterval(this.statsTimer)
    this.unmountInfo()
    this.teardown()
  },

  async connect() {
    this.connection?.close()

    const connection = new Connection(this, state => this.onConnectionState(connection, state), {
      room_id: this.roomId
    })
    this.connection = connection

    connection.pc.addTransceiver("video", {direction: "recvonly"})
    connection.pc.addTransceiver("audio", {direction: "recvonly"})
    connection.pc.ontrack = ({streams: [stream]}) => {
      if (this.video.srcObject !== stream) this.video.srcObject = stream
    }

    try {
      await connection.negotiate()
    } catch (error) {
      this.status.textContent = `${error.message}, retrying...`
      this.retry(connection)
    }
  },

  onConnectionState(connection, state) {
    if (connection !== this.connection) return

    if (state === "connected") this.status.textContent = ""
    if (state === "failed") {
      this.status.textContent = "Connection lost, reconnecting..."
      this.retry(connection)
    }
  },

  retry(connection) {
    setTimeout(() => {
      if (this.connection === connection) this.connect()
    }, RETRY_DELAY_MS)
  },

  teardown() {
    this.connection?.close()
    this.connection = null
    this.video.srcObject = null
  }
}
