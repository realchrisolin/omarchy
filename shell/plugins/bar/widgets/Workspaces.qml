import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // Per-monitor strip. Laptop panels use numeric workspaces 1-10; other
  // monitors (Miracast Extend, HDMI, …) use named workspaces ext-1..ext-10.
  // Use QsWindow (Quickshell), not Window.window — the latter is often null
  // in bar PanelWindows and broke eDP active-slot detection.
  readonly property var hostWindow: QsWindow.window
  readonly property string monitorName: {
    if (!hostWindow || !hostWindow.screen)
      return ""
    try {
      var hm = Hyprland.monitorFor(hostWindow.screen)
      if (hm && hm.name)
        return String(hm.name)
    } catch (e) {}
    if (hostWindow.screen.name)
      return String(hostWindow.screen.name)
    return ""
  }
  readonly property bool laptopMonitor: {
    var n = root.monitorName
    // If we cannot resolve the screen yet, prefer laptop logic so the primary
    // bar keeps showing the filled indicator (ext-N path would never match).
    if (!n)
      return true
    return n.indexOf("eDP") === 0 || n.indexOf("LVDS") === 0 || n.indexOf("DSI") === 0
  }

  function isLaptopName(name) {
    name = String(name || "")
    return name.indexOf("eDP") === 0 || name.indexOf("LVDS") === 0 || name.indexOf("DSI") === 0
  }

  function workspaceMonitorName(workspace) {
    if (!workspace) return ""
    var mon = workspace.monitor
    if (!mon) return ""
    if (typeof mon === "string") return mon
    if (mon.name !== undefined) return String(mon.name || "")
    return String(mon)
  }

  function workspaceKeyForSlot(slot) {
    if (root.laptopMonitor)
      return String(slot)
    return "ext-" + slot
  }

  function workspaceMatchesSlot(workspace, slot) {
    if (!workspace) return false
    var key = root.workspaceKeyForSlot(slot)
    if (root.laptopMonitor)
      return workspace.id === slot || String(workspace.name) === key
    return String(workspace.name) === key || String(workspace.name) === ("name:" + key)
  }

  function workspaceBySlot(slot) {
    var values = Hyprland.workspaces.values
    var mon = root.monitorName
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      if (!root.workspaceMatchesSlot(ws, slot)) continue
      if (mon) {
        var wsMon = root.workspaceMonitorName(ws)
        if (wsMon && wsMon !== mon) continue
      }
      return ws
    }
    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    for (var slot = 6; slot <= 10; slot++) {
      if (root.workspaceBySlot(slot) !== null && ids.indexOf(slot) === -1)
        ids.push(slot)
    }
    return ids
  }

  function slotFromActiveWorkspace(aw) {
    if (!aw) return -1
    if (root.laptopMonitor) {
      var id = aw.id
      // Classic path: positive numeric ids on the laptop.
      if (id >= 1 && id <= 10) return id
      return -1
    }
    var name = String(aw.name || "")
    var matched = name.match(/^ext-(\d+)$/) || name.match(/^name:ext-(\d+)$/)
    if (matched) return parseInt(matched[1], 10)
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id !== aw.id) continue
      name = String(values[i].name || "")
      matched = name.match(/^ext-(\d+)$/) || name.match(/^name:ext-(\d+)$/)
      return matched ? parseInt(matched[1], 10) : -1
    }
    return -1
  }

  function monitorActiveSlot() {
    var monName = root.monitorName
    var monitors = Hyprland.monitors.values
    var aw = null
    var i

    if (monName) {
      for (i = 0; i < monitors.length; i++) {
        if (!monitors[i] || String(monitors[i].name || "") !== monName) continue
        aw = monitors[i].activeWorkspace
        break
      }
    } else if (root.laptopMonitor) {
      // Resolve eDP even when QsWindow.screen is not ready yet.
      for (i = 0; i < monitors.length; i++) {
        if (!monitors[i] || !root.isLaptopName(monitors[i].name)) continue
        aw = monitors[i].activeWorkspace
        break
      }
    }

    if (Hyprland.focusedMonitor && monName
        && String(Hyprland.focusedMonitor.name || "") === monName
        && Hyprland.focusedWorkspace) {
      aw = Hyprland.focusedWorkspace
    }

    // Laptop fallback: original Omarchy behavior (reliable filled indicator).
    if (!aw && root.laptopMonitor && Hyprland.focusedWorkspace
        && Hyprland.focusedWorkspace.id >= 1 && Hyprland.focusedWorkspace.id <= 10) {
      // Only when focus is on a laptop monitor (or unknown).
      if (!Hyprland.focusedMonitor || root.isLaptopName(Hyprland.focusedMonitor.name))
        aw = Hyprland.focusedWorkspace
    }

    return root.slotFromActiveWorkspace(aw)
  }

  function focusWorkspace(slot) {
    if (!root.bar) return
    root.bar.run("omarchy-hyprland-workspace-focus " + slot)
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceBySlot(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: root.monitorActiveSlot() === modelData

        bar: root.bar
        text: focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
