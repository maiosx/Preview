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
  property bool pinned: false
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
  readonly property bool compact: root.queryText.length === 0
  property string diskLabel: ""
  property real diskUsedFrac: 0
  property string homePrefix: ""
  property string activePath: ""
  property string locFlash: ""
  readonly property string locationLabel: {
    var p = String(root.activePath || "")
    if (!p.length) return ""
    var slash = p.lastIndexOf("/")
    var dir = slash > 0 ? p.slice(0, slash) : p
    var home = String(root.homePrefix || Quickshell.env("HOME") || "")
    if (home.length && dir.indexOf(home) === 0) dir = "~" + dir.slice(home.length)
    return dir.length ? dir : "/"
  }

  function serviceRef() {
    try {
      if (root.pluginRegistry && typeof root.pluginRegistry.serviceFor === "function") {
        var s = root.pluginRegistry.serviceFor(root.pluginId)
        if (s && s !== root) return s
      }
    } catch (e) {}
    return null
  }

  function open(payloadJson) {
    root.opened = true
    root.pinned = false
    root.queryText = ""
    searchField.text = ""
    root.results = []
    root.lastQueryRev = -1
    root.previewResult = ({})
    root.activePath = ""
    root.enableLayerBlur()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }
  function close() { root.opened = false; root.pinned = false }
  function toggle() { if (root.opened) root.close(); else root.open("{}") }
  function query(arg) { return root.callIpc("query", arg) }
  function snapshot(arg) { return root.callIpc("snapshot", arg) }
  function preview(arg) { return root.callIpc("preview", arg) }

  function currentHit() {
    if (!root.results || root.selectedIndex < 0 || root.selectedIndex >= root.results.length) return null
    return root.results[root.selectedIndex]
  }
  function currentPath() {
    if (root.activePath.length) return root.activePath
    var hit = root.currentHit()
    return hit && hit.path ? String(hit.path) : ""
  }
  function locationPath() {
    var p = String(root.activePath || "")
    if (!p.length) return ""
    var slash = p.lastIndexOf("/")
    return slash > 0 ? p.slice(0, slash) : p
  }
  function copyText(s) {
    var t = String(s || "")
    if (!t.length) return
    try { Quickshell.clipboardText = t } catch (e) {}
    Quickshell.execDetached(["wl-copy", "--", t])
  }
  function copyLocation() {
    var p = root.locationPath()
    if (!p.length) return
    root.copyText(p)
    root.locFlash = "copied"
    locFlashTimer.restart()
  }
  function enableLayerBlur() {
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "blur,preview"])
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "ignorealpha 0,preview"])
    Quickshell.execDetached(["hyprctl", "keyword", "layerrule", "xray 0,preview"])
  }

  function callIpc(method, arg) {
    var job = { method: String(method || ""), arg: arg === undefined || arg === null ? "" : String(arg) }
    var svc = root.serviceRef()
    if (svc && typeof svc[job.method] === "function") {
      var result = svc[job.method](job.arg)
      if (job.method === "snapshot") root.applySnapshot(result)
      else if (job.method === "query" && svc.lastResults) root.setResults(svc.lastResults)
      return result === undefined || result === null ? "ok" : String(result)
    }
    root.ipcQueue.push(job)
    root.runIpc()
  }
  function runIpc() {
    if (ipcProc.running || root.ipcCurrent || !root.ipcQueue.length) return
    root.ipcCurrent = root.ipcQueue.shift()
    ipcProc.command = ["omarchy-shell", root.pluginId, root.ipcCurrent.method, root.ipcCurrent.arg]
    ipcProc.running = true
  }
  function setResults(list) {
    var next = []
    var prefix = String(root.homePrefix || "")
    if (list && list.length) {
      for (var i = 0; i < list.length; i++) {
        var hit = list[i]
        var p = hit && hit.path ? String(hit.path) : ""
        if (!p.length) continue
        if (prefix.length && p !== prefix && p.indexOf(prefix + "/") !== 0) continue
        if (p.indexOf("/home/") !== 0 && p.indexOf("/root/") !== 0) continue
        next.push(hit)
      }
    }
    root.results = next
    root.resultsTick += 1
    if (next.length) {
      if (root.selectedIndex >= next.length) root.selectedIndex = 0
      var hit = next[root.selectedIndex]
      if (hit && hit.path) root.requestPreview(hit.path, 1)
    } else {
      root.previewResult = ({})
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
    if (snap.home) root.homePrefix = String(snap.home)
    if (snap.diskLabel !== undefined) root.diskLabel = String(snap.diskLabel || "")
    if (snap.diskUsedFrac !== undefined) root.diskUsedFrac = Number(snap.diskUsedFrac) || 0
  }
  function requestQuery(q) {
    if (!String(q || "").length) { root.results = []; root.previewResult = ({}); return }
    root.callIpc("query", q)
  }
  function requestPreview(path, page) {
    root.activePath = String(path || "")
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
  function launchFile(path) {
    var p = String(path || "")
    if (!p.length) return
    var quoted = "'" + p.replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["hyprctl", "dispatch", "exec", "xdg-open " + quoted])
  }
  function launchDir(path) {
    var p = String(path || "")
    if (!p.length) return
    var slash = p.lastIndexOf("/")
    var dir = slash > 0 ? p.slice(0, slash) : p
    var quoted = "'" + dir.replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["hyprctl", "dispatch", "exec", "xdg-open " + quoted])
  }
  function openCurrent() {
    var p = root.currentPath()
    if (!p.length) return
    root.launchFile(p)
    Qt.callLater(root.close)
  }
  function revealCurrent() {
    var p = root.currentPath()
    if (!p.length) return
    root.launchDir(p)
    Qt.callLater(root.close)
  }
  function pinToggle() {
    if (!root.currentHit() && !root.activePath.length) return
    root.pinned = !root.pinned
    if (root.pinned) {
      root.enableLayerBlur()
      Qt.callLater(function() { pinnedPane.forceActiveFocus() })
    } else {
      Qt.callLater(function() { searchField.forceActiveFocus() })
    }
  }

  Process {
    id: ipcProc
    running: false
    stdout: StdioCollector { id: ipcOut; waitForEnd: true }
    onExited: function() {
      var job = root.ipcCurrent
      var collected = String(ipcOut.text || "").trim()
      root.ipcCurrent = null
      if (job && job.method === "snapshot" && collected.length) root.applySnapshot(collected)
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
    id: locFlashTimer
    interval: 1200
    repeat: false
    onTriggered: root.locFlash = ""
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

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      visible: !root.pinned
      MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    BorderSurface {
      visible: !root.pinned
      width: Math.min(Style.space(root.compact ? 720 : 1120), parent.width - Style.gapsOut * 2)
      height: root.compact
        ? Style.space(140)
        : Math.min(Style.space(680), parent.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      MouseArea { anchors.fill: parent; onClicked: {} }
      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.md
        Rectangle {
          width: parent.width
          height: Style.space(48)
          radius: 10
          border.color: searchField.activeFocus ? root.accent : root.border
          border.width: 1
          color: "transparent"
          Text {
            anchors.fill: parent
            anchors.margins: 14
            text: "Search"
            visible: searchField.text.length === 0
            color: root.foreground
            opacity: 0.35
            font.pixelSize: Style.font.title
            verticalAlignment: Text.AlignVCenter
          }
          TextInput {
            id: searchField
            anchors.fill: parent
            anchors.margins: 14
            color: root.foreground
            font.pixelSize: Style.font.title
            clip: true
            focus: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.pinned) root.pinned = false
                else root.close()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) { root.selectIndex(root.selectedIndex + 1); event.accepted = true }
              else if (event.key === Qt.Key_Up) { root.selectIndex(root.selectedIndex - 1); event.accepted = true }
              else if (event.key === Qt.Key_Space) { root.pinToggle(); event.accepted = true }
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.openCurrent(); event.accepted = true }
            }
            onTextChanged: { root.queryText = text; debounce.restart() }
          }
        }
        Row {
          width: parent.width
          height: parent.height - Style.space(108)
          spacing: 12
          visible: !root.compact
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
              text: "no matches"
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
        Column {
          width: parent.width
          spacing: 6
          Item {
            width: parent.width
            height: 6
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(parent.width * 0.42, 280)
              height: 6
              radius: 3
              color: root.border
              visible: root.diskLabel.length > 0
              Rectangle {
                width: parent.width * Math.min(1, Math.max(0, root.diskUsedFrac))
                height: parent.height
                radius: 3
                color: root.diskUsedFrac > 0.9 ? "#f7768e" : root.accent
              }
            }
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.diskLabel
            visible: root.diskLabel.length > 0
            color: root.foreground
            opacity: 0.55
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Rectangle {
      id: pinnedPane
      anchors.fill: parent
      visible: root.pinned
      color: "transparent"
      focus: root.pinned
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Space) { root.pinToggle(); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.revealCurrent(); event.accepted = true }
      }
      Rectangle {
        id: blurLayer
        anchors.fill: parent
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.55)
      }
      PreviewPane {
        anchors.fill: parent
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 28
        anchors.bottomMargin: 48
        preview: root.previewResult
        loading: root.previewLoading
        foreground: root.foreground
        accent: root.accent
        selectable: true
      }
      Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 16
        width: parent.width * 0.8
        text: root.locFlash.length ? root.locFlash : root.locationLabel
        color: root.locFlash.length ? root.accent : root.foreground
        opacity: root.locFlash.length ? 1 : 0.55
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignHCenter
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.copyLocation()
        }
      }
    }
  }
}
