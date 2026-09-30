// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {ScreenBroadcast, ScreenViewer} from "./hooks/screen_share"
import {LocalTime} from "./hooks/local_time"
import {playNotification} from "./hooks/notification_sounds"
import {Soundboard} from "./hooks/soundboard"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // Read on every connect, so screen keys (kept in the URL fragment to never
  // reach the server logs) reach the LiveView on reconnects too
  params: () => {
    const params = {_csrf_token: csrfToken}
    if (location.hash.length > 1) params.key = location.hash.slice(1)
    return params
  },
  hooks: {LocalTime, ScreenBroadcast, ScreenViewer, Soundboard}
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Streamers hear viewers come and go on their own page and on the server's page
window.addEventListener("phx:screen:viewer_joined", () => playNotification("join"))
window.addEventListener("phx:screen:viewer_left", () => playNotification("leave"))

// Screen links keep their keys in the URL fragment, which the server never sees,
// so it's kept here while the visitor logs in with Discord
const LOGIN_RETURN = "botchini:login_return"

document.addEventListener("click", event => {
  const link = event.target.closest("[data-login]")
  if (!link) return

  try {
    sessionStorage.setItem(LOGIN_RETURN, link.dataset.returnTo + location.hash)
  } catch (_error) {}
})

if (location.pathname === "/auth/return") {
  let destination = null

  try {
    destination = sessionStorage.getItem(LOGIN_RETURN)
    sessionStorage.removeItem(LOGIN_RETURN)
  } catch (_error) {}

  const valid = /^\/screens(#.*)?$/.test(destination || "")
  location.replace(valid ? destination : "/screens")
}

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

