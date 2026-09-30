// Shows a <time datetime="..."> element's time in the visitor's timezone, as the
// server renders it in UTC.

function render(el) {
  const time = new Date(el.getAttribute("datetime"))
  if (Number.isNaN(time.getTime())) return

  el.textContent = time.toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"})
}

export const LocalTime = {
  mounted() {
    render(this.el)
  },

  updated() {
    render(this.el)
  }
}
