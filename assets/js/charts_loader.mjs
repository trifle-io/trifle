// Loads the chart library bundle (js/charts.js) and keeps chart code from running
// before it has arrived.
//
// The library is about half of all JavaScript the app ships. Building it as a
// separate file lets the browser fetch it in parallel with app.js, and keeps it
// cached when a deploy changes app.js only.
//
// Chart hooks use the library synchronously, so no chart hook may run before the
// bundle has. Two things see to that:
//
//   1. connectWhenReady: the LiveSocket connects once the bundle is in (it is
//      normally already downloading via the layout's <link rel="preload">), or
//      after a short cap, so a slow chart download cannot hold up a page.
//   2. guardHook: a chart hook that mounts after the cap but before the bundle
//      waits. When the bundle arrives the hook is mounted in place, unless it
//      was destroyed in the meantime, and the server events it missed while
//      waiting are delivered to it. Nothing reloads and nothing else on the
//      page waits.

const GLOBAL_NAME = "TrifleECharts"
const DEFAULT_SRC = "/assets/charts.js"
const LIFECYCLE = ["beforeUpdate", "updated", "beforeDestroy", "destroyed", "disconnected", "reconnected"]

export function createChartsLoader({ window, document, connectCapMs = 1500, retryDelayMs = 1000 } = {}) {
  const library = () => window[GLOBAL_NAME]
  const loaded = () => Boolean(library())

  const source = () => {
    const link = document.getElementById("trifle-charts-bundle")
    return (link && link.getAttribute("href")) || DEFAULT_SRC
  }

  const inject = () =>
    new Promise((resolve, reject) => {
      if (loaded()) return resolve()
      const script = document.createElement("script")
      script.src = source()
      script.async = true
      script.onload = () => (loaded() ? resolve() : reject(new Error("chart bundle did not register")))
      script.onerror = () => reject(new Error("chart bundle failed to load"))
      document.head.appendChild(script)
    })

  // One retry: a single dropped request should not leave the session without charts.
  const ready = inject().catch(
    () => new Promise((resolve) => window.setTimeout(resolve, retryDelayMs)).then(inject)
  )
  // Callers attach their own handlers; this keeps a failed load from surfacing
  // as an unhandled rejection.
  ready.catch(() => {})

  // Stands in for the library wherever hooks expect it. Hooks only touch it once
  // mounted, which the guards below hold back until the bundle has run.
  const echarts = new Proxy(
    {},
    {
      get(_target, property) {
        const lib = library()
        return lib ? lib[property] : undefined
      },
      has(_target, property) {
        const lib = library()
        return lib ? property in lib : false
      }
    }
  )

  const connectWhenReady = (connect) => {
    if (loaded()) return connect()
    let done = false
    const once = () => {
      if (!done) {
        done = true
        connect()
      }
    }
    ready.then(once, once)
    window.setTimeout(once, connectCapMs)
  }

  // Server push events reach hooks as `phx:<name>` events on window. While a
  // guarded hook is waiting, those are recorded so they can be handed to the
  // handlers it registers once it mounts. Recording is on only while at least
  // one hook waits.
  const PUSH_PREFIX = "phx:"
  const IGNORED_PUSHES = new Set(["phx:page-loading-start", "phx:page-loading-stop"])
  let waiting = 0
  let recorded = []
  let originalDispatch = null

  const startRecording = () => {
    waiting += 1
    if (waiting > 1 || typeof window.dispatchEvent !== "function") return
    originalDispatch = window.dispatchEvent
    window.dispatchEvent = function (event) {
      if (event && typeof event.type === "string" && event.type.startsWith(PUSH_PREFIX) && !IGNORED_PUSHES.has(event.type)) {
        recorded.push({ name: event.type.slice(PUSH_PREFIX.length), detail: event.detail })
      }
      return originalDispatch.apply(this, arguments)
    }
  }

  const stopRecording = () => {
    waiting = Math.max(waiting - 1, 0)
    if (waiting > 0) return
    if (originalDispatch) window.dispatchEvent = originalDispatch
    originalDispatch = null
    recorded = []
  }

  // Mounts a hook that had to wait, then replays what it missed.
  const resume = (instance, hook, missedFrom) => {
    const missed = recorded.slice(missedFrom)
    const handlers = []
    const originalHandleEvent = instance.handleEvent

    if (typeof originalHandleEvent === "function") {
      instance.handleEvent = function (name, callback) {
        handlers.push({ name, callback })
        return originalHandleEvent.call(this, name, callback)
      }
    }

    try {
      if (hook.mounted) hook.mounted.call(instance)
    } finally {
      if (typeof originalHandleEvent === "function") {
        // Back to the prototype method LiveView provides.
        delete instance.handleEvent
        if (instance.handleEvent !== originalHandleEvent) instance.handleEvent = originalHandleEvent
      }
    }

    missed.forEach(({ name, detail }) => {
      handlers.forEach((handler) => {
        if (handler.name === name) handler.callback(detail)
      })
    })

    if (instance.__chartsUpdatedWhilePending && hook.updated) hook.updated.call(instance)
  }

  const guardHook = (hook) => {
    const guarded = { ...hook }

    guarded.mounted = function () {
      if (loaded()) return hook.mounted && hook.mounted.call(this)

      this.__chartsPending = true
      const missedFrom = recorded.length
      startRecording()

      const settle = (mount) => {
        const cancelled = this.__chartsCancelled
        this.__chartsPending = false
        try {
          if (mount && !cancelled) resume(this, hook, missedFrom)
        } finally {
          stopRecording()
        }
      }

      // If the bundle cannot be loaded at all the hook stays unmounted; the rest
      // of the page keeps working.
      ready.then(() => settle(true), () => settle(false))
    }

    LIFECYCLE.forEach((name) => {
      const original = hook[name]
      if (typeof original !== "function" && name !== "destroyed" && name !== "updated") return

      guarded[name] = function (...args) {
        if (this.__chartsPending) {
          // Never mounted: remember what matters and skip the hook's own code.
          if (name === "destroyed") this.__chartsCancelled = true
          if (name === "updated") this.__chartsUpdatedWhilePending = true
          return
        }
        if (this.__chartsCancelled) return
        return typeof original === "function" ? original.apply(this, args) : undefined
      }
    })

    return guarded
  }

  return { echarts, ready, loaded, connectWhenReady, guardHook }
}
