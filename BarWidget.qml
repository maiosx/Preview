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
  property bool bindInstallTried: false
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

  readonly property string chipTooltip: {
    var keys = root.hotkeyLabel.length ? root.hotkeyLabel : "Super+Ctrl+Space"
    return "Preview  " + keys
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

  function applyBindPlan(plan) {
    var p = plan || Binds.offer
    root.offerBinds = !!p.needed
    root.canSetHotkey = !!p.canSet
    root.offerNote = String(p.note || "")
    root.hotkeyLabel = String(p.hotkeyLabel || "")
    Binds.setOffer(p)
    if (p.needed && p.canSet && !root.bindInstallTried) {
      root.bindInstallTried = true
      Qt.callLater(root.installBinds)
    }
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

  function scanBinds() {
    enqueueWork(["hyprctl", "-j", "binds"], function(text, code) {
      if (Number(code) !== 0) return
      root.applyBindPlan(Binds.applyScan(text))
    })
  }

  function liveBind(item) {
    enqueueWork(["hyprctl", "keyword", "bind", Binds.hyprKeywordArg(item)])
  }

  function installBinds() {
    enqueueWork(["hyprctl", "-j", "binds"], function(text, code) {
      if (Number(code) !== 0) {
        root.offerNote = "could not read keybinds"
        return
      }
      var plan = Binds.applyScan(text)
      if (!plan.toAdd || !plan.toAdd.length) {
        root.applyBindPlan(plan)
        return
      }
      var lua = Binds.luaBlock(plan.toAdd)
      enqueueWork(["python3", root.pluginDir + "/compat/install-binds.py", root.pluginId, lua], function(out, instCode) {
        if (Number(instCode) !== 0) {
          root.offerNote = "could not write ~/.config/hypr/bindings.lua"
          return
        }
        for (var i = 0; i < plan.toAdd.length; i++)
          root.liveBind(plan.toAdd[i])
        Qt.callLater(root.scanBinds)
      })
    })
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf002"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.chipTooltip
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
      var collected = workOut.text
      var job = root.workCurrent
      root.workCurrent = null
      if (job && job.done) {
        try { job.done(collected, exitCode) }
        catch (e) { console.warn("preview: bar bind callback failed", e) }
      }
      root.runWork()
    }
  }

  Timer {
    interval: 4000
    repeat: true
    running: true
    onTriggered: root.scanBinds()
  }

  Component.onCompleted: Qt.callLater(root.scanBinds)
}
