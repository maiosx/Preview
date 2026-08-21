import QtQuick
import Quickshell
import Quickshell.Io
import "js/Protocol.js" as Protocol
import "js/Config.js" as Config
import "js/Fallback.js" as Fallback
import "js/Format.js" as Format

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginId: "io.github.maiosx.preview"
  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    if (u.indexOf("file://") === 0)
      u = u.slice(7)
    if (u.length > 1 && u.charAt(u.length - 1) === "/")
      u = u.slice(0, u.length - 1)
    return u
  }

  property var roots: []
  property int watchCap: 2000
  property int cacheMb: 500
  property int maxFiles: 500000
  property var extraExclude: []

  readonly property string home: Quickshell.env("HOME") || "/tmp"
  readonly property string helperBin: pluginDir + "/bin/quicklookd"
  readonly property string helperSh: pluginDir + "/compat/quicklookd.sh"

  property string helperCmd: helperSh
  property bool helperIsBinary: false
  property bool helperReady: false
  property var lastResults: []
  property var lastPreview: ({})
  property var lastCaps: ({})
  property int resultsRevision: 0
  property int previewRevision: 0
  property int statusRevision: 0
  property bool indexing: false
  property real indexProgress: 0
  property string backend: "compat"
  property string lastStatus: "starting"
  property var oneshotQueue: []
  property var oneshotCurrent: null

  function helperCommand() {
    return root.helperIsBinary ? root.helperBin : root.helperSh
  }

  function helperLaunch(oneshotJson) {
    var cmd = [root.helperCommand(), "--plugin-dir", root.pluginDir]
    if (oneshotJson !== undefined && oneshotJson !== null) {
      cmd.push("--oneshot")
      cmd.push(String(oneshotJson))
    }
    return cmd
  }

  function enqueueOneshot(obj) {
    if (!obj)
      return
    if (obj.cmd === "query") {
      var kept = []
      for (var i = 0; i < oneshotQueue.length; i++) {
        if (oneshotQueue[i].cmd !== "query")
          kept.push(oneshotQueue[i])
      }
      oneshotQueue = kept
    }
    oneshotQueue.push(obj)
    runOneshot()
  }

  function runOneshot() {
    if (oneshotProc.running || root.oneshotCurrent)
      return
    if (!oneshotQueue.length)
      return
    root.oneshotCurrent = oneshotQueue.shift()
    oneshotProc.command = root.helperLaunch(JSON.stringify(root.oneshotCurrent))
    oneshotProc.running = true
  }

  function onHelperLine(line) {
    var msg = Protocol.parseLine(line)
    if (!msg)
      return
    if (msg.kind === "results") {
      root.lastResults = msg.results || []
      root.backend = String(msg.backend || root.backend)
      if (msg.indexing !== undefined)
        root.indexing = !!msg.indexing
      if (msg.progress !== undefined)
        root.indexProgress = Number(msg.progress) || 0
      root.resultsRevision += 1
    } else if (msg.kind === "preview") {
      root.lastPreview = msg.preview || {}
      root.previewRevision += 1
    } else if (msg.kind === "status") {
      root.lastCaps = msg.status || {}
      root.statusRevision += 1
    }
  }

  function localQuery(q) {
    var hits = Fallback.search(Fallback.defaultSamples(root.pluginDir), q, 40)
    root.lastResults = hits
    root.backend = "local"
    root.resultsRevision += 1
    return hits
  }

  function query(q) {
    if (!root.helperReady)
      root.localQuery(q)
    var req = Protocol.queryRequest(q)
    root.enqueueOneshot(req)
    return req.id
  }

  function requestPreview(path, page) {
    var req = Protocol.previewRequest(path, page)
    root.enqueueOneshot(req)
    return req.id
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
    return String(root.requestPreview(path, page))
  }

  function prefetch(path) {
    return String(root.requestPreview(path, 1))
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
      statusRevision: root.statusRevision,
      results: root.lastResults,
      preview: root.lastPreview,
      indexing: root.indexing,
      indexProgress: root.indexProgress,
      backend: root.backend,
      lastCaps: root.lastCaps,
      lastStatus: root.lastStatus,
      helperCmd: root.helperCmd
    })
  }

  function statusJson() {
    return JSON.stringify({
      id: root.pluginId,
      helper: root.helperCmd,
      helperIsBinary: root.helperIsBinary,
      backend: root.backend,
      indexing: root.indexing,
      results: root.lastResults.length
    })
  }

  Process {
    id: oneshotProc
    running: false
    stdout: StdioCollector {
      id: oneshotOut
      waitForEnd: true
    }
    onExited: {
      var text = String(oneshotOut.text || "").trim()
      var job = root.oneshotCurrent
      root.oneshotCurrent = null
      if (text.length) {
        var lines = text.split("\n")
        root.onHelperLine(lines[lines.length - 1])
      } else if (job && job.cmd === "query") {
        root.localQuery(job.q || "")
      } else if (job && (job.cmd === "preview" || job.cmd === "page")) {
        root.lastPreview = Format.localPreview(job.path)
        root.previewRevision += 1
      }
      root.runOneshot()
    }
  }

  Process {
    id: whichProc
    command: ["sh", "-c", "test -x \"$1\" && echo binary || echo missing", "sh", root.helperBin]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        root.helperIsBinary = (out === "binary")
        root.helperCmd = root.helperIsBinary ? root.helperBin : root.helperSh
        root.helperReady = true
        root.lastStatus = "ready"
        root.query("")
      }
    }
  }

  IpcHandler {
    target: "io.github.maiosx.preview"
    function ping(arg: string): string { return "ok" }
    function status(arg: string): string { return root.statusJson() }
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

  Component.onCompleted: {
    Config.applyInline({
      roots: root.roots,
      watchCap: root.watchCap,
      cacheMb: root.cacheMb,
      maxFiles: root.maxFiles,
      extraExclude: root.extraExclude
    }, root.home)
    Protocol.reset()
    whichProc.running = true
  }
}
