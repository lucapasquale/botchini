// WebRTC hooks for screen sharing. The browser always makes the offer and the
// server answers, with ICE candidates trickled both ways through the LiveView.

// Screens are mostly static, so a high bitrate keeps text sharp without
// costing much, while motion content gets smoother frames instead
const MAX_BITRATE = 8_000_000
const MAX_FRAMERATE = 60
const RETRY_DELAY_MS = 2_000

class Connection {
  constructor(hook, onConnectionState) {
    this.hook = hook
    this.pendingCandidates = []
    this.pc = new RTCPeerConnection({iceServers: JSON.parse(hook.el.dataset.iceServers)})

    this.pc.onicecandidate = ({candidate}) => {
      if (candidate) hook.pushEvent("ice_candidate", candidate.toJSON())
    }
    this.pc.onconnectionstatechange = () => onConnectionState(this.pc.connectionState)
  }

  // Resolves once the server answer is applied, rejects with a message to show
  async negotiate() {
    await this.pc.setLocalDescription(await this.pc.createOffer())

    const reply = await new Promise(resolve => {
      this.hook.pushEvent("offer", this.pc.localDescription.toJSON(), resolve)
    })
    if (reply.error) throw new Error(reply.error)

    await this.pc.setRemoteDescription(reply.answer)
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

export const ScreenBroadcast = {
  mounted() {
    this.stream = null
    this.connection = null
    this.preview = this.el.querySelector("#screen-broadcast-preview")
    this.status = this.el.querySelector("[data-screen-status]")
    this.hint = this.el.querySelector("[data-screen-hint]")

    // Screen capture needs a user gesture, so buttons are handled here instead of
    // through phx-click, which would lose it on the round trip to the server
    this.el.addEventListener("click", event => {
      if (event.target.closest("[data-screen-start]")) this.start()
      if (event.target.closest("[data-screen-switch]")) this.switchSource()
      if (event.target.closest("[data-screen-stop]")) this.stop()
    })
    this.hint.addEventListener("change", () => this.applyHint())

    this.handleEvent("screen:ice_candidate", candidate => this.connection?.addRemoteCandidate(candidate))
    this.handleEvent("screen:ended", () => this.teardown())
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
    this.applyHint()

    try {
      await connection.negotiate()
      // Some browsers ignore encoding parameters set before negotiating
      this.applyHint()
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
    this.applyHint()
  },

  stop() {
    this.teardown()
    this.pushEvent("stop", {})
  },

  async capture() {
    const stream = await navigator.mediaDevices.getDisplayMedia({
      video: {frameRate: {ideal: 30, max: MAX_FRAMERATE}},
      audio: true,
      systemAudio: "include",
      selfBrowserSurface: "exclude"
    })

    this.preview.srcObject = stream
    this.showAudioNotice(stream)
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

  applyHint() {
    const track = this.stream?.getVideoTracks()[0]
    if (!track) return

    const motion = this.hint.value === "motion"
    track.contentHint = motion ? "motion" : "detail"

    if (this.videoSender) {
      const params = this.videoSender.getParameters()
      params.degradationPreference = motion ? "maintain-framerate" : "maintain-resolution"
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
    this.video = this.el.querySelector("#screen-viewer-video")
    this.status = document.getElementById("screen-viewer-status")
    this.handleEvent("screen:ice_candidate", candidate => this.connection?.addRemoteCandidate(candidate))
    this.handleEvent("screen:ended", () => this.teardown())
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

    const connection = new Connection(this, state => this.onConnectionState(connection, state))
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
