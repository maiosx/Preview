import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.maiosx.preview"

  readonly property string pluginId: "io.github.maiosx.preview"
  property var shell: bar && bar.shell ? bar.shell : null
  property var manifest: null
  property var pluginRegistry: null
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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggleOverlay() {
    if (root.shell && typeof root.shell.toggle === "function") {
      root.shell.toggle(root.pluginId, "{}")
      return
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.pluginId, "{}"])
  }

  function enqueueWork(command, done) {
    workQueue.push({ command: command, done: done || null })
    runWork()
  }

  function runWork() {
    if (workProc.running || root.workCurrent) return
    if (!workQueue.length) return
    root.workCurrent = workQueue.shift()
    workProc.command = root.workCurrent.command
    workProc.running = true
  }

  function stripBinds() {
    enqueueWork(["python3", root.pluginDir + "/compat/install-binds.py", "--remove", root.pluginId])
    enqueueWork(["hyprctl", "keyword", "unbind", "SUPER ALT, F"])
    enqueueWork(["hyprctl", "keyword", "unbind", "SUPER ALT, PERIOD"])
    enqueueWork(["hyprctl", "keyword", "unbind", "SUPER CTRL, SPACE"])
    enqueueWork(["hyprctl", "keyword", "unbind", "SUPER CTRL, F"])
    enqueueWork(["hyprctl", "keyword", "unbind", "SUPER, PERIOD"])
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf002"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Preview — search files in your home folder"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton || buttonCode === Qt.RightButton)
        root.toggleOverlay()
    }
  }

  Process {
    id: workProc
    running: false
    stdout: StdioCollector { id: workOut; waitForEnd: true }
    onExited: function(exitCode) {
      var job = root.workCurrent
      root.workCurrent = null
      if (job && job.done) {
        try { job.done(workOut.text, exitCode) } catch (e) {}
      }
      root.runWork()
    }
  }

  Component.onCompleted: Qt.callLater(root.stripBinds)
}
