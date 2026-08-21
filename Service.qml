import QtQuick
import Quickshell
import "js/Fallback.js" as Fallback
import "js/Format.js" as Format
import "js/Config.js" as Config

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  readonly property string pluginId: "io.github.maiosx.preview"
  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    if (u.indexOf("file://") === 0) u = u.slice(7)
    if (u.length > 1 && u.charAt(u.length - 1) === "/") u = u.slice(0, u.length - 1)
    return u
  }
  property var lastResults: []
  property var lastPreview: ({})
  property int resultsRevision: 0
  property int previewRevision: 0

  function query(q) {
    root.lastResults = Fallback.search(Fallback.defaultSamples(root.pluginDir), q, 40)
    root.resultsRevision += 1
    return String(root.resultsRevision)
  }
  function requestPreview(path) {
    root.lastPreview = Format.localPreview(path)
    root.previewRevision += 1
    return String(root.previewRevision)
  }
  function preview(arg) {
    var path = String(arg || "")
    if (path.length && path.charAt(0) === "{") {
      try { path = String(JSON.parse(path).path || "") } catch (e) {}
    }
    return root.requestPreview(path)
  }
  function snapshotJson() {
    return JSON.stringify({
      resultsRevision: root.resultsRevision,
      previewRevision: root.previewRevision,
      results: root.lastResults,
      preview: root.lastPreview
    })
  }
  function openPath(path) {
    if (path) Quickshell.execDetached(["xdg-open", path])
    return "ok"
  }
  function reveal(path) {
    if (path) Quickshell.execDetached(["xdg-open", path])
    return "ok"
  }

  IpcHandler {
    target: "io.github.maiosx.preview"
    function ping(arg: string): string { return "ok" }
    function status(arg: string): string { return "{\"id\":\"io.github.maiosx.preview\"}" }
    function snapshot(arg: string): string { return root.snapshotJson() }
    function query(q: string): string { return String(root.query(q)) }
    function preview(path: string): string { return root.preview(path) }
    function open(path: string): string { return root.openPath(path) }
    function reveal(path: string): string { return root.reveal(path) }
    function toggle(arg: string): string {
      Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId, arg || "{}"])
      return "ok"
    }
  }

  Component.onCompleted: root.query("")
}
