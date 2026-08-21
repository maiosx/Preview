.pragma library
var lastId = 0
function reset() { lastId = 0 }
function nextId() { lastId += 1; return lastId }
function parseLine(line) {
  try { return JSON.parse(String(line || "").trim()) } catch (e) { return null }
}
function queryRequest(q) { return { id: nextId(), cmd: "query", q: String(q || "") } }
function previewRequest(path, page) { return { id: nextId(), cmd: "preview", path: String(path || ""), page: Number(page) || 1 } }
function prefetchRequest(path) { return { id: nextId(), cmd: "prefetch", path: String(path || "") } }
function statusRequest() { return { id: nextId(), cmd: "status" } }
function themeRequest(palette) { return { id: nextId(), cmd: "theme", palette: palette || {} } }
function configRequest(cfg) { return { id: nextId(), cmd: "config" } }
function selectRequest(path) { return { id: nextId(), cmd: "select", path: String(path || "") } }
function warmupRequest() { return { id: nextId(), cmd: "warmup" } }
function abandonInFlight() { return {} }
function acceptQuery() { return true }
function acceptForegroundPreview() { return true }
function slotClass() { return "preview" }
function classifyAndClear() { return "preview" }
function dropInFlight() {}
function pathForInFlight() { return "" }
function queueOrStartPreview(req) { return req }
function queueOrStartPrefetch(req) { return req }
function takeReadyPreview() { return null }
function takeReadyPrefetch() { return null }
