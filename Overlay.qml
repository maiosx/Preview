import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "js/Format.js" as Format

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property bool opened: false
  property string pluginId: "io.github.maiosx.preview"
  property string queryText: ""
  property int selectedIndex: 0
  property var results: []
  property int resultsTick: 0
  property var previewResult: ({})
  property bool previewLoading: false
  property int lastQueryRev: -1
  property int lastPreviewRev: -1
  property string backend: ""
  property var ipcQueue: []
  property var ipcCurrent: null
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color accent: Color.accent
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  function serviceRef() {
    try {
      if (root.pluginRegistry && typeof root.pluginRegistry.serviceFor === "function") {
        var s = root.pluginRegistry.serviceFor(root.pluginId)
        if (s && s !== root)
          return s
      }
    } catch (e) {}
    return null
  }

  function open(payloadJson) {
    root.opened = true
    root.queryText = ""
    searchField.text = ""
    root.lastQueryRev = -1
    root.requestQuery("")
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }
  function close() { root.opened = false }
  function toggle() { if (root.opened) root.close(); else root.open("{}") }
  function query(arg) { return root.callIpc("query", arg) }
  function snapshot(arg) { return root.callIpc("snapshot", arg) }
  function preview(arg) { return root.callIpc("preview", arg) }

  function callIpc(method, arg) {
    var job = { method: String(method || ""), arg: arg === undefined || arg === null ? "" : String(arg) }
    var svc = root.serviceRef()
    if (svc && typeof svc[job.method] === "function") {
      var result = svc[job.method](job.arg)
      if (job.method === "snapshot")
        root.applySnapshot(result)
      else if (job.method === "query" && svc.lastResults)
        root.setResults(svc.lastResults)
      return result === undefined || result === null ? "ok" : String(result)
    }
    root.ipcQueue.push(job)
    root.runIpc()
  }

  function runIpc() {
    if (ipcProc.running || root.ipcCurrent || !root.ipcQueue.length)
      return
    root.ipcCurrent = root.ipcQueue.shift()
    ipcProc.command = ["omarchy-shell", root.pluginId, root.ipcCurrent.method, root.ipcCurrent.arg]
    ipcProc.running = true
  }

  function setResults(list) {
    var next = []
    if (list && list.length) {
      for (var i = 0; i < list.length; i++)
        next.push(list[i])
    }
    root.results = next
    root.resultsTick += 1
    if (next.length) {
      if (root.selectedIndex >= next.length)
        root.selectedIndex = 0
      var hit = next[root.selectedIndex]
      if (hit && hit.path)
        root.requestPreview(hit.path, 1)
    }
  }

  function applySnapshot(raw) {
    var snap = null
    try { snap = JSON.parse(String(raw || "")) } catch (e) { return }
    if (!snap) return
    if (snap.backend) root.backend = String(snap.backend)
    var rev = Number(snap.resultsRevision)
    if (isNaN(rev)) rev = 0
    if (rev !== root.lastQueryRev) {
      root.lastQueryRev = rev
      root.setResults(snap.results || [])
    }
    var prev = Number(snap.previewRevision)
    if (!isNaN(prev) && prev !== root.lastPreviewRev) {
      root.lastPreviewRev = prev
      root.previewResult = snap.preview || {}
      root.previewLoading = false
    }
  }

  function requestQuery(q) { root.callIpc("query", q) }
  function requestPreview(path, page) {
    root.previewLoading = true
    root.callIpc("preview", JSON.stringify({ path: path, page: page || 1 }))
  }
  function selectIndex(i) {
    if (!root.results.length) return
    if (i < 0) i = 0
    if (i >= root.results.length) i = root.results.length - 1
    root.selectedIndex = i
    root.requestPreview(root.results[i].path, 1)
  }
  function openCurrent() {
    var hit = root.results[root.selectedIndex]
    if (!hit) return
    var svc = root.serviceRef()
    if (svc && typeof svc.openPath === "function") svc.openPath(hit.path)
    else Quickshell.execDetached(["xdg-open", hit.path])
    root.close()
  }

  Process {
    id: ipcProc
    running: false
    stdout: StdioCollector {
      id: ipcOut
      waitForEnd: true
    }
    onExited: function() {
      var job = root.ipcCurrent
      var collected = String(ipcOut.text || "").trim()
      root.ipcCurrent = null
      if (job && job.method === "snapshot" && collected.length)
        root.applySnapshot(collected)
      root.runIpc()
    }
  }

  Timer {
    interval: 100
    running: root.opened
    repeat: true
    onTriggered: root.callIpc("snapshot", "")
  }
  Timer {
    id: debounce
    interval: 80
    repeat: false
    onTriggered: { root.selectedIndex = 0; root.lastQueryRev = -1; root.requestQuery(root.queryText) }
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: root.scrim; MouseArea { anchors.fill: parent; onClicked: root.close() } }
    BorderSurface {
      width: Math.min(Style.space(1120), parent.width - Style.gapsOut * 2)
      height: Math.min(Style.space(680), parent.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      MouseArea { anchors.fill: parent; onClicked: {} }
      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.md
        Row {
          spacing: 12
          Text { text: "Preview"; color: root.foreground; font.pixelSize: Style.font.heading; font.bold: true }
          Text {
            text: root.backend + (root.results.length ? (" · " + root.results.length) : "")
            color: root.accent
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        Rectangle {
          width: parent.width
          height: Style.space(40)
          radius: 8
          border.color: searchField.activeFocus ? root.accent : root.border
          border.width: 1
          color: "transparent"
          TextInput {
            id: searchField
            anchors.fill: parent
            anchors.margins: 10
            color: root.foreground
            font.pixelSize: Style.font.title
            clip: true
            focus: true
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
              else if (event.key === Qt.Key_Down) { root.selectIndex(root.selectedIndex + 1); event.accepted = true }
              else if (event.key === Qt.Key_Up) { root.selectIndex(root.selectedIndex - 1); event.accepted = true }
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.openCurrent(); event.accepted = true }
            }
            onTextChanged: { root.queryText = text; debounce.restart() }
          }
        }
        Row {
          width: parent.width
          height: parent.height - Style.space(100)
          spacing: 12
          ListView {
            id: resultsView
            width: parent.width * 0.36
            height: parent.height
            clip: true
            model: root.results
            currentIndex: root.selectedIndex
            delegate: Rectangle {
              required property int index
              required property var modelData
              width: ListView.view.width
              height: 44
              radius: 6
              color: index === root.selectedIndex ? root.accent : "transparent"
              Text {
                anchors.fill: parent
                anchors.margins: 8
                text: Format.glyphFor(modelData.kind) + "  " + modelData.name
                color: root.foreground
                elide: Text.ElideMiddle
                verticalAlignment: Text.AlignVCenter
              }
              MouseArea { anchors.fill: parent; onClicked: root.selectIndex(index); onDoubleClicked: root.openCurrent() }
            }
            Text {
              anchors.centerIn: parent
              visible: root.results.length === 0
              text: root.queryText.length ? "no matches" : "type to search"
              color: root.foreground
              opacity: 0.45
            }
          }
          PreviewPane {
            width: parent.width * 0.64 - 12
            height: parent.height
            preview: root.previewResult
            loading: root.previewLoading
            foreground: root.foreground
            accent: root.accent
          }
        }
      }
    }
  }
}
