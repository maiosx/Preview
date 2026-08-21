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

  readonly property string searchBody: "q=\"$1\"; home=\"$2\"; fd_bin=$(command -v fd || command -v fdfind || true); " +
    "if [ -z \"$q\" ]; then " +
    "  if [ -n \"$fd_bin\" ]; then \"$fd_bin\" -a -H -t f --changed-within 30d --max-results 40 --max-depth 8 -E .git -E node_modules -E .cache . \"$home\"; " +
    "  else find \"$home\" -maxdepth 3 -type f ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/.cache/*' 2>/dev/null | head -n 40; fi; " +
    "  exit 0; " +
    "fi; " +
    "if [ -n \"$fd_bin\" ]; then \"$fd_bin\" -a -H -i -F --max-results 50 --max-depth 16 -E .git -E node_modules -E .cache -- \"$q\" \"$home\"; exit 0; fi; " +
    "if command -v plocate >/dev/null 2>&1; then plocate -i -l 50 -N -- \"$q\"; exit 0; fi; " +
    "find \"$home\" -maxdepth 8 \\( -name .git -o -name node_modules -o -name .cache \\) -prune -o -iname \"*$q*\" -print 2>/dev/null | head -n 50"

  function applyPathList(text, usedBackend) {
    var lines = String(text || "").split(/\r?\n/)
    var hits = []
    var seen = ({})
    for (var i = 0; i < lines.length && hits.length < 40; i++) {
      var p = String(lines[i] || "").replace(/^\s+|\s+$/g, "").replace(/^'+|'+$/g, "")
      if (!p.length || p.charAt(0) !== "/")
        continue
      if (seen[p])
        continue
      seen[p] = true
      var slash = p.lastIndexOf("/")
      var name = slash >= 0 ? p.slice(slash + 1) : p
      if (!name.length)
        continue
      hits.push({
        path: p,
        name: name,
        kind: Format.kindOf(p, false),
        score: 100,
        mtime: 0,
        size: 0
      })
    }
    root.lastResults = hits
    root.backend = usedBackend || "search"
    root.resultsRevision += 1
    root.lastStatus = "hits:" + hits.length
  }

  function sanitize(q) {
    return String(q || "").replace(/[*?[\]\\'"]/g, "")
  }

  function query(q) {
    root.searchNeedle = root.sanitize(q)
    Qt.callLater(root.startSearch)
    return String(root.resultsRevision + 1)
  }

  function startSearch() {
    if (searchProc.running) {
      searchProc.running = false
      Qt.callLater(root.startSearch)
      return
    }
    searchProc.command = ["sh", "-c", root.searchBody, "preview-search", root.searchNeedle, root.home]
    searchProc.running = true
    root.searchRunning = true
    root.lastStatus = "searching"
  }

  function requestPreview(path, page) {
    var p = String(path || "")
    root.lastPreview = Format.localPreview(p)
    root.previewRevision += 1
    return String(root.previewRevision)
  }

  function preview(arg) {
    var path = String(arg || "")
    var page = 1
    if (path.length && path.charAt(0) === "{") {
      try {
        var o = JSON.parse(path)
        path = String(o.path || "")
        page = Number(o.page) || 1
      } catch (e) {}
    }
    return root.requestPreview(path, page)
  }

  function prefetch(path) {
    return root.requestPreview(path, 1)
  }

  function openPath(path) {
    if (path)
      Quickshell.execDetached(["xdg-open", path])
    return "ok"
  }

  function reveal(path) {
    if (!path)
      return "empty"
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

  Process {
    id: searchProc
    running: false
    stdout: StdioCollector {
      id: searchOut
      waitForEnd: true
      onStreamFinished: {
        root.applyPathList(text, "search")
        root.searchRunning = false
      }
    }
    onExited: function(code) {
      root.searchRunning = false
      var collected = String(searchOut.text || "")
      if (root.lastStatus === "searching")
        root.applyPathList(collected, "search")
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
    function warmup(arg: string): string { root.query(""); return "ok" }
    function toggle(arg: string): string {
      Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId, arg && arg.length ? arg : "{}"])
      return "ok"
    }
  }

  Component.onCompleted: root.query("")
}
