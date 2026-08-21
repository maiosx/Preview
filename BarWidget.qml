import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "js/Binds.js" as Binds

BarWidget {
  id: root
  moduleName: "io.github.maiosx.preview"

  readonly property string pluginId: "io.github.maiosx.preview"
  property var shell: bar && bar.shell ? bar.shell : null
  property var manifest: null
  property var pluginRegistry: null

  property bool offerBinds: true
  property bool canSetHotkey: false
  property string offerNote: ""
  property string hotkeyLabel: ""
  property var workQueue: []
  property var workCurrent: null

  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    if (u.indexOf("file://") === 0)
      u = u.slice(7)
    if (u.length > 1 && u.charAt(u.length - 1) === "/")
      u = u.slice(0, u.length - 1)
    return u
  }

  readonly property string chipText: root.hotkeyLabel.length
                                     ? ("Preview  " + root.hotkeyLabel)
                                     : "Preview"
  readonly property string chipTooltip: {
    if (root.hotkeyLabel.length)
      return "Preview " + root.hotkeyLabel + " — click to open"
    if (root.offerNote.length)
      return "Preview — click to open. " + root.offerNote
    return "Preview — click to open"
  }

  function toggleOverlay() {
    if (root.shell && typeof root.shell.toggle === "function") {
      root.shell.toggle(root.pluginId, "{}")
      return
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId, "{}"])
  }

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    spacing: Style.space(4)

    WidgetButton {
      id: button
      bar: root.bar
      text: root.chipText
      tooltipText: root.chipTooltip
      onPressed: function(buttonCode) {
        if (buttonCode === Qt.LeftButton || buttonCode === Qt.RightButton)
          root.toggleOverlay()
      }
    }
  }

  Component.onCompleted: {}
}
