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
  property string diskLabel: ""
  property real diskUsedFrac: 0
  property double diskTotal: 0

  readonly property int previewBytes: 200000

  readonly property string searchBody: "q=\"$1\"; start=\"$2\"; " +
    "home=$(cd \"$start\" 2>/dev/null && pwd -P || printf '%s' \"$start\"); " +
    "case \"$home\" in /home/*|/root) ;; *) exit 0 ;; esac; " +
    "if [ -z \"$q\" ] || [ ! -d \"$home\" ]; then exit 0; fi; " +
    "inside() { while IFS= read -r p; do " +
    "  [ -z \"$p\" ] && continue; " +
    "  d=$(dirname \"$p\"); b=$(basename \"$p\"); " +
    "  rp=$(cd \"$d\" 2>/dev/null && printf '%s/%s\\n' \"$(pwd -P)\" \"$b\" || printf '%s\\n' \"$p\"); " +
    "  case \"$rp\" in \"$home\"|\"$home\"/*) printf '%s\\n' \"$rp\" ;; esac; " +
    "done; }; " +
    "fd_bin=$(command -v fd || command -v fdfind || true); " +
    "if [ -n \"$fd_bin\" ]; then " +
    "  \"$fd_bin\" -a -i -F -t f --one-file-system --max-results 80 --max-depth 8 " +
    "    -E node_modules -E .git -E dist -E target -E __pycache__ -E .venv -E venv " +
    "    -E .cache -E .local -E .npm -E .cargo -E .flatpak " +
    "    -- \"$q\" \"$home\" 2>/dev/null | inside; " +
    "  exit 0; " +
    "fi; " +
    "find -P \"$home\" -xdev -maxdepth 8 " +
    "  \\( -name node_modules -o -name .git -o -name dist -o -name target -o -name .venv -o -name .cache -o -name .local \\) -prune " +
    "  -o -type f -iname \"*$q*\" -print 2>/dev/null | inside | head -n 50"

  readonly property string readBody: "head -c 200000 \"$1\""

  readonly property string pdfBody: "if ! command -v pdftotext >/dev/null 2>&1; then printf '%s\\n' POPPLER_MISSING; exit 0; fi; " +
    "ulimit -t 3 2>/dev/null; ulimit -v 524288 2>/dev/null; ulimit -f 4096 2>/dev/null; " +
    "if command -v timeout >/dev/null 2>&1; then exec timeout -k 1 4 pdftotext -f 1 -l 1 -layout \"$1\" -; " +
    "else exec pdftotext -f 1 -l 1 -layout \"$1\" -; fi"

  function underHome(p) {
    var home = String(root.home || "")
    if (home.length < 6 || home === "/" || home === "/home") return false
    while (home.length > 1 && home.charAt(home.length - 1) === "/") home = home.slice(0, home.length - 1)
    if (p === home) return true
    if (p.indexOf(home + "/") !== 0) return false
    if (p.indexOf("/../") >= 0) return false
    return true
  }
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
      if (!root.underHome(p)) continue
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
  function diskHuman(n) {
    var v = Number(n) || 0
    var tb = 1024 * 1024 * 1024 * 1024
    var gb = 1024 * 1024 * 1024
    if (v >= tb) return (v / tb).toFixed(1) + " TB"
    if (v >= gb) {
      var g = v / gb
      return (g >= 10 ? g.toFixed(0) : g.toFixed(1)) + " GB"
    }
    return Format.humanSize(v)
  }
  function applyDf(text) {
    var lines = String(text || "").split(/\r?\n/)
    var row = ""
    for (var i = 0; i < lines.length; i++) {
      var t = String(lines[i] || "").replace(/^\s+|\s+$/g, "")
      if (t.length && t.indexOf("Size") < 0 && t.indexOf("Avail") < 0) row = t
    }
    if (!row.length) return
    var parts = row.split(/\s+/)
    var size = Number(parts[0])
    var avail = Number(parts[1])
    if (!(size > 0)) return
    root.diskTotal = size
    root.diskUsedFrac = Math.max(0, Math.min(1, (size - avail) / size))
    root.diskLabel = root.diskHuman(avail) + " free of " + root.diskHuman(size)
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
    var large = s.length >= root.previewBytes
    if (s.length > root.previewBytes) s = s.slice(0, root.previewBytes)
    if (binary) {
      var hex = ""
      var n = Math.min(s.length, 256)
      for (var i = 0; i < n; i++) {
        var c = s.charCodeAt(i) & 255
        hex += (c < 16 ? "0" : "") + c.toString(16) + ((i + 1) % 16 === 0 ? "\n" : " ")
      }
      root.lastPreview = { kind: "hex", path: root.previewPath, label: Format.basename(root.previewPath), hex: hex, text: hex }
    } else {
      root.lastPreview = {
        kind: "code",
        path: root.previewPath,
        html: "<pre>" + root.escapeHtml(s) + "</pre>",
        text: s,
        large: large,
        label: Format.basename(root.previewPath)
      }
    }
    root.previewRevision += 1
  }
  function requestPreview(path, page) {
    var p = String(path || "")
    root.previewPath = p
    if (!p.length) { root.lastPreview = ({}); root.previewRevision += 1; return "0" }
    if (!root.underHome(p)) { root.lastPreview = ({}); root.previewRevision += 1; return "0" }
    var kind = Format.kindOf(p, false)
    if (kind === "image") {
      root.lastPreview = Format.localPreview(p)
      root.previewRevision += 1
      return String(root.previewRevision)
    }
    if (kind === "pdf") {
      if (pdfProc.running) pdfProc.running = false
      pdfKill.restart()
      pdfProc.command = ["sh", "-c", root.pdfBody, "preview-pdf", p]
      pdfProc.running = true
      return String(root.previewRevision + 1)
    }
    if (textProc.running) textProc.running = false
    readKill.restart()
    textProc.command = ["sh", "-c", root.readBody, "preview-read", p]
    textProc.running = true
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
    var p = String(path || "")
    if (!p.length || !root.underHome(p)) return "empty"
    var quoted = "'" + p.replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["hyprctl", "dispatch", "exec", "xdg-open " + quoted])
    return "ok"
  }
  function reveal(path) {
    if (!path || !root.underHome(String(path))) return "empty"
    var quoted = "'" + String(path).replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["hyprctl", "dispatch", "exec", "xdg-open " + quoted])
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
      lastStatus: root.lastStatus,
      home: root.home,
      diskLabel: root.diskLabel,
      diskUsedFrac: root.diskUsedFrac,
      diskTotal: root.diskTotal
    })
  }
  Process {
    id: textProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        readKill.stop()
        root.applyTextPreview(text)
      }
    }
    onExited: readKill.stop()
  }
  Process {
    id: pdfProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        pdfKill.stop()
        var t = String(text || "")
        if (t.indexOf("POPPLER_MISSING") === 0) {
          root.lastPreview = { kind: "pdf", path: root.previewPath, need_poppler: true, label: "PDF" }
          root.previewRevision += 1
        } else root.applyTextPreview(t)
      }
    }
    onExited: pdfKill.stop()
  }
  Timer {
    id: readKill
    interval: 4000
    repeat: false
    onTriggered: { if (textProc.running) textProc.running = false }
  }
  Timer {
    id: pdfKill
    interval: 5000
    repeat: false
    onTriggered: { if (pdfProc.running) pdfProc.running = false }
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
  Process {
    id: dfProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDf(text)
    }
  }
  Timer {
    interval: 20000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      dfProc.command = ["df", "-B1", "--output=size,avail", root.home]
      dfProc.running = true
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
