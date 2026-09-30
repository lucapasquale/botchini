// WebRTC hooks for screen sharing. The browser always makes the offer and the
// server answers, with ICE candidates trickled both ways through the LiveView.

import {playNotification} from "./notification_sounds"

// Tuned for games: the source's full resolution at up to 60 fps, only for
// friends, so the bitrate can be high
const MAX_BITRATE = 20_000_000
const MAX_FRAMERATE = 60
// Browsers start sending low and take a while to trust the connection, which
// makes the first seconds blurry, so Chrome and Edge are told to start higher
const START_BITRATE_KBPS = 10_000
const RETRY_DELAY_MS = 2_000

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
    await this.pc.setLocalDescription(await this.pc.createOffer())

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
    this.handleEvent("screen:viewer_joined", () => playNotification("join"))
    this.handleEvent("screen:viewer_left", () => playNotification("leave"))
  },

  // The new LiveView process doesn't know about the old connection, and the room
  // drops it once the previous process is gone, so sharing has to be negotiated again
  reconnected() {
    if (this.stream) this.connect()
  },

  destroyed() {
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
    const encoding = {maxBitrate: MAX_BITRATE, maxFramerate: MAX_FRAMERATE}

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
    this.pushEvent("source", {surface: stream.getVideoTracks()[0].getSettings().displaySurface ?? null})
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

    track.contentHint = "motion"

    if (this.videoSender) {
      const params = this.videoSender.getParameters()
      params.degradationPreference = "balanced"
      this.videoSender.setParameters(params).catch(() => {})
    }
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
    this.connect()
  },

  reconnected() {
    this.connect()
  },

  destroyed() {
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
