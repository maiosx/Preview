import QtQuick
import Quickshell
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
  property var previewResult: ({})
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color scrim: Color.menu.scrim

  function serviceRef() {
    try {
      if (root.pluginRegistry && typeof root.pluginRegistry.serviceFor === "function")
        return root.pluginRegistry.serviceFor(root.pluginId)
    } catch (e) {}
    return null
  }
  function open(payloadJson) {
    root.opened = true
    root.queryText = ""
    searchField.text = ""
    root.requestQuery("")
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }
  function close() { root.opened = false }
  function toggle() { if (root.opened) root.close(); else root.open("{}") }
  function requestQuery(q) {
    var svc = root.serviceRef()
    if (svc && typeof svc.query === "function") {
      svc.query(q)
      root.results = svc.lastResults || []
      if (root.results.length) root.requestPreview(root.results[0].path)
    }
  }
  function requestPreview(path) {
    var svc = root.serviceRef()
    if (svc && typeof svc.requestPreview === "function") {
      svc.requestPreview(path)
      root.previewResult = svc.lastPreview || {}
    }
  }
  function selectIndex(i) {
    if (!root.results.length) return
    if (i < 0) i = 0
    if (i >= root.results.length) i = root.results.length - 1
    root.selectedIndex = i
    root.requestPreview(root.results[i].path)
  }
  function openCurrent() {
    var hit = root.results[root.selectedIndex]
    if (!hit) return
    var svc = root.serviceRef()
    if (svc && typeof svc.openPath === "function") svc.openPath(hit.path)
    else Quickshell.execDetached(["xdg-open", hit.path])
    root.close()
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
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.md

        Text {
          text: "Preview"
          color: root.foreground
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Rectangle {
          width: parent.width
          height: Style.space(40)
          radius: 8
          border.color: root.accent
          border.width: 1
          color: "transparent"
          TextInput {
            id: searchField
            anchors.fill: parent
            anchors.margins: 10
            color: root.foreground
            font.pixelSize: Style.font.title
            focus: true
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
              else if (event.key === Qt.Key_Down) { root.selectIndex(root.selectedIndex + 1); event.accepted = true }
              else if (event.key === Qt.Key_Up) { root.selectIndex(root.selectedIndex - 1); event.accepted = true }
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.openCurrent(); event.accepted = true }
            }
            onTextChanged: { root.queryText = text; root.requestQuery(text) }
          }
        }

        Row {
          width: parent.width
          height: parent.height - Style.space(100)
          spacing: 12
          ListView {
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
              color: index === root.selectedIndex ? root.accent : "transparent"
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                text: Format.glyphFor(modelData.kind) + "  " + modelData.name
                color: root.foreground
              }
              MouseArea { anchors.fill: parent; onClicked: root.selectIndex(index); onDoubleClicked: root.openCurrent() }
            }
          }
          PreviewPane {
            width: parent.width * 0.64 - 12
            height: parent.height
            preview: root.previewResult
            foreground: root.foreground
            accent: root.accent
          }
        }
      }
    }
  }
}
