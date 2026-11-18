import test from "node:test"
import assert from "node:assert/strict"
import { createChartsLoader } from "../js/charts_loader.mjs"

// A minimal browser: scripts appended to <head> are recorded and finished by
// the test (load or error), timers are run by hand.
function fakeBrowser({ href = "/assets/charts-abc123.js" } = {}) {
  const scripts = []
  const timers = []
  const listeners = []
  const window = {
    reloads: 0,
    assigned: [],
    setTimeout: (fn, ms) => timers.push({ fn, ms }),
    location: {
      reload: () => (window.reloads += 1),
      assign: (url) => window.assigned.push(url)
    }
  }
  const document = {
    head: { appendChild: (script) => scripts.push(script) },
    createElement: () => ({}),
    getElementById: (id) =>
      id === "trifle-charts-bundle" && href ? { getAttribute: () => href } : null,
    addEventListener: (type, fn, capture) => listeners.push({ type, fn, capture })
  }
  const finish = (index, ok = true) => {
    if (ok) {
      window.TrifleECharts = { init: () => "chart", format: { formatTime: () => "t" } }
      scripts[index].onload()
    } else {
      scripts[index].onerror()
    }
  }
  const runTimers = () => timers.splice(0).forEach((timer) => timer.fn())
  const settle = () => new Promise((resolve) => setImmediate(resolve))
  return { window, document, scripts, timers, listeners, finish, runTimers, settle }
}

test("loads the bundle from the fingerprinted URL in the layout", () => {
  const browser = fakeBrowser()
  createChartsLoader(browser)

  assert.equal(browser.scripts.length, 1)
  assert.equal(browser.scripts[0].src, "/assets/charts-abc123.js")
})

test("falls back to the plain path when the layout has no preload link", () => {
  const browser = fakeBrowser({ href: null })
  createChartsLoader(browser)

  assert.equal(browser.scripts[0].src, "/assets/charts.js")
})

test("the echarts stand-in forwards to the library once it is there", async () => {
  const browser = fakeBrowser()
  const loader = createChartsLoader(browser)

  assert.equal(loader.loaded(), false)
  assert.equal(loader.echarts.init, undefined)
  assert.equal(typeof loader.echarts.connect === "function", false)

  browser.finish(0)
  await loader.ready

  assert.equal(loader.loaded(), true)
  assert.equal(loader.echarts.init(), "chart")
  assert.equal(loader.echarts.format.formatTime(), "t")
})

test("connects only after the bundle has run", async () => {
  const browser = fakeBrowser()
  const loader = createChartsLoader(browser)
  let connects = 0
  loader.connectWhenReady(() => (connects += 1))

  await browser.settle()
  assert.equal(connects, 0)

  browser.finish(0)
  await browser.settle()
  assert.equal(connects, 1)

  // The cap firing later must not connect a second time.
  browser.runTimers()
  assert.equal(connects, 1)
})

test("connects immediately when the bundle is already there", () => {
  const browser = fakeBrowser()
  browser.window.TrifleECharts = { init() {} }
  const loader = createChartsLoader(browser)
  let connects = 0
  loader.connectWhenReady(() => (connects += 1))

  assert.equal(connects, 1)
  assert.equal(browser.scripts.length, 0)
})

test("a slow bundle does not hold up the connection past the cap", async () => {
  const browser = fakeBrowser()
  const loader = createChartsLoader({ ...browser, connectCapMs: 1500 })
  let connects = 0
  loader.connectWhenReady(() => (connects += 1))

  assert.deepEqual(browser.timers.map((timer) => timer.ms), [1500])
  browser.runTimers()
  assert.equal(connects, 1)

  browser.finish(0)
  await browser.settle()
  assert.equal(connects, 1)
})

test("a failed load is retried once, and the app still connects if it fails again", async () => {
  const browser = fakeBrowser()
  const loader = createChartsLoader(browser)
  let connects = 0
  loader.connectWhenReady(() => (connects += 1))

  browser.finish(0, false)
  await browser.settle()
  assert.equal(connects, 0)

  // The retry timer and the connect cap are both pending; run the retry only.
  const retry = browser.timers.find((timer) => timer.ms === 1000)
  retry.fn()
  await browser.settle()
  assert.equal(browser.scripts.length, 2)

  browser.finish(1, false)
  await browser.settle()
  assert.equal(connects, 1)
  await assert.rejects(loader.ready)
})

test("a guarded hook runs normally once the bundle is in", async () => {
  const browser = fakeBrowser()
  const loader = createChartsLoader(browser)
  browser.finish(0)
  await loader.ready

  const calls = []
  const hook = loader.guardHook({
    mounted() { calls.push(["mounted", this.el]) },
    updated() { calls.push(["updated", this.el]) },
    destroyed() { calls.push(["destroyed", this.el]) },
    helper() { return "kept" }
  })

  const instance = { ...hook, el: "node" }
  instance.mounted()
  instance.updated()
  instance.destroyed()

  assert.deepEqual(calls, [["mounted", "node"], ["updated", "node"], ["destroyed", "node"]])
  assert.equal(instance.helper(), "kept")
  assert.equal(browser.window.reloads, 0)
})

// What LiveView gives a hook: handleEvent on the prototype, registering a
// window listener for `phx:<name>`.
function hookInstance(browser, hook) {
  class ViewHook {
    handleEvent(name, callback) {
      browser.window.addEventListener(`phx:${name}`, (event) => callback(event.detail))
    }
  }
  return Object.assign(new ViewHook(), hook)
}

function withEvents(browser) {
  const listeners = {}
  browser.window.addEventListener = (type, fn) => (listeners[type] ||= []).push(fn)
  browser.window.dispatchEvent = (event) => {
    ;(listeners[event.type] || []).forEach((fn) => fn(event))
    return true
  }
  browser.push = (name, detail) => browser.window.dispatchEvent({ type: `phx:${name}`, detail })
  return browser
}

test("a hook that mounts before the bundle is mounted in place when it arrives, with no reload", async () => {
  const browser = withEvents(fakeBrowser())
  const loader = createChartsLoader(browser)
  const calls = []
  const instance = hookInstance(browser, loader.guardHook({
    mounted() {
      calls.push("mounted")
      this.handleEvent("chart_data", (payload) => calls.push(["chart_data", payload]))
    },
    updated() { calls.push("updated") },
    destroyed() { calls.push("destroyed") }
  }))

  instance.mounted()
  assert.deepEqual(calls, [])

  browser.finish(0)
  await browser.settle()

  assert.deepEqual(calls, ["mounted"])
  assert.equal(browser.window.reloads, 0)

  // From here on it behaves like any hook.
  browser.push("chart_data", { n: 1 })
  instance.updated()
  instance.destroyed()
  assert.deepEqual(calls, ["mounted", ["chart_data", { n: 1 }], "updated", "destroyed"])
})

test("server events pushed while a hook waited are delivered to it once, in order", async () => {
  const browser = withEvents(fakeBrowser())
  const loader = createChartsLoader(browser)
  const seen = []
  const other = []

  // A hook that was already mounted must not receive anything twice.
  browser.window.addEventListener("phx:chart_data", (event) => other.push(event.detail))

  const instance = hookInstance(browser, loader.guardHook({
    mounted() {
      this.handleEvent("chart_data", (payload) => seen.push(payload))
      this.handleEvent("other_event", (payload) => seen.push(["other", payload]))
    }
  }))

  browser.push("chart_data", "before-mount")
  instance.mounted()
  browser.push("chart_data", "first")
  browser.push("unrelated", "ignored")
  browser.push("other_event", "second")
  browser.push("chart_data", "third")

  browser.finish(0)
  await browser.settle()

  assert.deepEqual(seen, ["first", ["other", "second"], "third"])
  assert.deepEqual(other, ["before-mount", "first", "third"])

  // Recording has stopped and the original dispatch is back: live events
  // arrive exactly once.
  browser.push("chart_data", "live")
  assert.deepEqual(seen, ["first", ["other", "second"], "third", "live"])
  assert.deepEqual(other, ["before-mount", "first", "third", "live"])
})

test("an update that arrived while waiting is applied after mounting", async () => {
  const browser = withEvents(fakeBrowser())
  const loader = createChartsLoader(browser)
  const calls = []
  const instance = hookInstance(browser, loader.guardHook({
    mounted() { calls.push("mounted") },
    updated() { calls.push("updated") }
  }))

  instance.mounted()
  instance.updated()
  instance.updated()
  browser.finish(0)
  await browser.settle()

  assert.deepEqual(calls, ["mounted", "updated"])
})

test("a hook destroyed while waiting is never mounted, and nothing reloads", async () => {
  const browser = withEvents(fakeBrowser())
  const loader = createChartsLoader(browser)
  const calls = []
  const instance = hookInstance(browser, loader.guardHook({
    mounted() { calls.push("mounted") },
    destroyed() { calls.push("destroyed") }
  }))
  const dispatch = browser.window.dispatchEvent

  instance.mounted()
  assert.notEqual(browser.window.dispatchEvent, dispatch)
  instance.destroyed()

  browser.finish(0)
  await browser.settle()

  assert.deepEqual(calls, [])
  assert.equal(browser.window.reloads, 0)
  assert.equal(browser.window.dispatchEvent, dispatch)
})

test("when the bundle cannot be loaded, waiting hooks stay unmounted and the page is left alone", async () => {
  const browser = withEvents(fakeBrowser())
  const loader = createChartsLoader(browser)
  const calls = []
  const instance = hookInstance(browser, loader.guardHook({ mounted() { calls.push("mounted") } }))
  const dispatch = browser.window.dispatchEvent
  instance.mounted()

  browser.finish(0, false)
  await browser.settle()
  browser.timers.find((timer) => timer.ms === 1000).fn()
  await browser.settle()
  browser.finish(1, false)
  await browser.settle()

  assert.deepEqual(calls, [])
  assert.equal(browser.window.reloads, 0)
  assert.equal(browser.window.dispatchEvent, dispatch)
})

test("the loader does not touch clicks or navigation", () => {
  const browser = fakeBrowser()
  const loader = createChartsLoader(browser)

  assert.equal(browser.listeners.length, 0)
  assert.equal(loader.installNavigationGuard, undefined)
})
