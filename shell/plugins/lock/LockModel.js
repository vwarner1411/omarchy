function blankDelaySeconds(idleConfig, fallback) {
  var config = idleConfig || {}
  var displayOff = Number(config.displayOff)
  var lock = Number(config.lock)

  if (!isFinite(displayOff) || displayOff < 0 || !isFinite(lock) || lock < 0) return fallback
  return Math.max(0, Math.floor(displayOff) - Math.floor(lock))
}

if (typeof module !== "undefined") {
  module.exports = {
    blankDelaySeconds: blankDelaySeconds
  }
}
