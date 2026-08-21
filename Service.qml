import QtQuick
import Quickshell
import Quickshell.Io
import "js/Format.js" as Format

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  readonly property string pluginId: "io.github.maiosx.preview"
  readonly property string home: Quickshell.env("HOME") || "/tmp"
  property var lastResults: []
  property var lastPreview: ({})
  property int resultsRevision: 0
  property int previewRevision: 0
  property string backend: "search"
  property string lastStatus: "ready"
  property string searchNeedle: ""
  property bool searchRunning: false
  property string previewPath: ""

  readonly property string searchBody: "q=\"$1\"; home=\"$2\"; fd_bin=$(command -v fd || command -v fdfind || true); " +
    "if [ -z \"$q\" ]; then exit 0; fi; " +
    "if [ -n \"$fd_bin\" ]; then \"$fd_bin\" -a -H -i -F --max-results 50 --max-depth 16 -E .git -E node_modules -E .cache -- \"$q\" \"$home\"; exit 0; fi; " +
    "if command -v plocate >/dev/null 2>&1; then plocate -i -l 50 -N -- \"$q\"; exit 0; fi; " +
    "find \"$home\" -maxdepth 8 \\( -name .git -o -name node_modules -o -name .cache \\) -prune -o -iname \"*$q*\" -print 2>/dev/null | head -n 50"

  function escapeHtml(s) {
    return String(s || "").replace(/&/g, "&" + "amp;").replace(/</g, "&" + "lt;").replace(/>/g, "&" + "gt;")
  }
  function applyPathList(text, usedBackend) {
    var lines = String(text || "").split(/\r?\n/)
    var hits = []
    var seen = ({})
    for (var i = 0; i < lines.length && hits.length < 40; i++) {
      var p = String(lines[i] || "").replace(/^\s+|\s+$/g, "").replace(/^'+|'+$/g, "")
      if (!p.length || p.charAt(0) !== "/") continue
      if (seen[p]) continue
      seen[p] = true
      var slash = p.lastIndexOf("/")
      var name = slash >= 0 ? p.slice(slash + 1) : p
      if (!name.length) continue
      var lower = name.toLowerCase()
      if (lower.indexOf(".pyc") === lower.length - 4 || lower.indexOf(".pyo") === lower.length - 4) continue
      if (lower.indexOf(".trashinfo") >= 0) continue
      hits.push({ path: p, name: name, kind: Format.kindOf(p, false), score: 100, mtime: 0, size: 0 })
    }
    root.lastResults = hits
    root.backend = usedBackend || "search"
    root.resultsRevision += 1
    root.lastStatus = "hits:" + hits.length
  }
  function sanitize(q) { return String(q || "").replace(/[*?[\]\\'"]/g, "") }
  function query(q) {
    root.searchNeedle = root.sanitize(q)
    if (!root.searchNeedle.length) {
      root.lastResults = []
      root.backend = "idle"
      root.resultsRevision += 1
      root.lastStatus = "idle"
      root.searchRunning = false
      return String(root.resultsRevision)
    }
    Qt.callLater(root.startSearch)
    return String(root.resultsRevision + 1)
  }
  function startSearch() {
    if (searchProc.running) { searchProc.running = false; Qt.callLater(root.startSearch); return }
    searchProc.command = ["sh", "-c", root.searchBody, "preview-search", root.searchNeedle, root.home]
    searchProc.running = true
    root.searchRunning = true
    root.lastStatus = "searching"
  }
  function applyTextPreview(raw) {
    var s = String(raw || "")
    var binary = s.indexOf("\0") >= 0
    var large = s.length > 200000
    if (large) s = s.slice(0, 200000)
    if (binary) {
      var hex = ""
      var n = Math.min(s.length, 256)
      for (var i = 0; i < n; i++) {
        var c = s.charCodeAt(i) & 255
        hex += (c < 16 ? "0" : "") + c.toString(16) + ((i + 1) % 16 === 0 ? "\n" : " ")
      }
      root.lastPreview = { kind: "hex", path: root.previewPath, label: Format.basename(root.previewPath), hex: hex }
    } else {
      root.lastPreview = { kind: "code", path: root.previewPath, html: "<pre>" + root.escapeHtml(s) + "</pre>", large: large, label: Format.basename(root.previewPath) }
    }
    root.previewRevision += 1
  }
  function requestPreview(path, page) {
    var p = String(path || "")
    root.previewPath = p
    if (!p.length) { root.lastPreview = ({}); root.previewRevision += 1; return "0" }
    var kind = Format.kindOf(p, false)
    if (kind === "image") {
      root.lastPreview = Format.localPreview(p)
      root.previewRevision += 1
      return String(root.previewRevision)
    }
    if (kind === "pdf") {
      pdfProc.running = false
      pdfProc.command = ["sh", "-c", "if command -v pdftotext >/dev/null 2>&1; then pdftotext -f 1 -l 1 -layout \"$1\" -; else echo POPPLER_MISSING; fi", "preview-pdf", p]
      pdfProc.running = true
      return String(root.previewRevision + 1)
    }
    previewFile.path = p
    previewFile.reload()
    return String(root.previewRevision + 1)
  }
  function preview(arg) {
    var path = String(arg || "")
    if (path.length && path.charAt(0) === "{") {
      try { path = String(JSON.parse(path).path || "") } catch (e) {}
    }
    return root.requestPreview(path, 1)
  }
  function prefetch(path) { return root.requestPreview(path, 1) }
  function openPath(path) {
    if (path) Quickshell.execDetached(["xdg-open", path])
    return "ok"
  }
  function reveal(path) {
    if (!path) return "empty"
    Quickshell.execDetached(["sh", "-c", "if [ -d \"$1\" ]; then exec xdg-open \"$1\"; else exec xdg-open \"$(dirname \"$1\")\"; fi", "sh", path])
    return "ok"
  }
  function snapshotJson() {
    return JSON.stringify({
      resultsRevision: root.resultsRevision,
      previewRevision: root.previewRevision,
      results: root.lastResults,
      preview: root.lastPreview,
      indexing: root.searchRunning,
      backend: root.backend,
      lastStatus: root.lastStatus
    })
  }
  FileView {
    id: previewFile
    printErrors: false
    watchChanges: false
    onLoaded: root.applyTextPreview(text())
    onLoadFailed: {
      root.lastPreview = { kind: "hex", path: root.previewPath, label: "couldn't read file" }
      root.previewRevision += 1
    }
  }
  Process {
    id: pdfProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "")
        if (t.indexOf("POPPLER_MISSING") === 0) {
          root.lastPreview = { kind: "pdf", path: root.previewPath, need_poppler: true, label: "PDF" }
          root.previewRevision += 1
        } else root.applyTextPreview(t)
      }
    }
  }
  Process {
    id: searchProc
    running: false
    stdout: StdioCollector {
      id: searchOut
      waitForEnd: true
      onStreamFinished: { root.applyPathList(text, "search"); root.searchRunning = false }
    }
    onExited: function(code) {
      root.searchRunning = false
      var collected = String(searchOut.text || "")
      if (root.lastStatus === "searching") root.applyPathList(collected, "search")
    }
  }
  IpcHandler {
    target: "io.github.maiosx.preview"
    function ping(arg: string): string { return "ok" }
    function status(arg: string): string { return root.snapshotJson() }
    function snapshot(arg: string): string { return root.snapshotJson() }
    function query(q: string): string { return String(root.query(q)) }
    function preview(path: string): string { return root.preview(path) }
    function prefetch(path: string): string { return root.prefetch(path) }
    function open(path: string): string { return root.openPath(path) }
    function reveal(path: string): string { return root.reveal(path) }
    function warmup(arg: string): string { return "ok" }
    function toggle(arg: string): string {
      Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId, arg && arg.length ? arg : "{}"])
      return "ok"
    }
  }
  Component.onCompleted: {
    root.lastResults = []
    root.backend = "idle"
    root.resultsRevision += 1
  }
}
