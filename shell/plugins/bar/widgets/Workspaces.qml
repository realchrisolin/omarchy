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

  // Bumped on Hyprland IPC events so focused/occupied bindings re-run even
  // when nested monitor.activeWorkspace changes do not invalidate QML deps.
  property int hyprEpoch: 0

  readonly property string monitorName: root.resolveMonitorName()
  readonly property bool laptopMonitor: {
    var n = root.monitorName
    if (n)
      return root.isLaptopName(n)
    if (Hyprland.focusedMonitor && root.isLaptopName(Hyprland.focusedMonitor.name))
      return true
    var monitors = Hyprland.monitors.values
    var external = 0
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i] && !root.isLaptopName(monitors[i].name))
        external++
    }
    return external === 0
  }

  // Explicit slot properties so the Repeater binds to values that change with
  // hyprEpoch / focusedWorkspace rather than opaque function call results.
  readonly property int activeSlot: {
    void root.hyprEpoch
    void Hyprland.focusedWorkspace
    void Hyprland.focusedMonitor
    void Hyprland.workspaces.values
    void Hyprland.monitors.values
    return root.monitorActiveSlot()
  }

  function isLaptopName(name) {
    name = String(name || "")
    return name.indexOf("eDP") === 0 || name.indexOf("LVDS") === 0 || name.indexOf("DSI") === 0
  }

  function resolveMonitorName() {
    void root.hyprEpoch
    if (!hostWindow || !hostWindow.screen)
      return ""
    var screen = hostWindow.screen
    var i
    var m
    var monitors = Hyprland.monitors.values

    try {
      var hm = Hyprland.monitorFor(screen)
      if (hm && hm.name)
        return String(hm.name)
    } catch (e) {}

    var screenName = screen.name ? String(screen.name) : ""
    if (screenName) {
      for (i = 0; i < monitors.length; i++) {
        m = monitors[i]
        if (m && String(m.name || "") === screenName)
          return screenName
      }
    }

    // Geometry match (Hyprland layout coords ↔ Qt screen position).
    try {
      var sx = Number(screen.x)
      var sy = Number(screen.y)
      var matches = []
      for (i = 0; i < monitors.length; i++) {
        m = monitors[i]
        if (!m || !m.name) continue
        if (Number(m.x) === sx && Number(m.y) === sy)
          matches.push(m)
      }
      if (matches.length === 1)
        return String(matches[0].name)
      // Disambiguate duplicates by logical size when scale is known.
      if (matches.length > 1) {
        var sw = Number(screen.width)
        var sh = Number(screen.height)
        for (i = 0; i < matches.length; i++) {
          m = matches[i]
          var scale = Number(m.scale) || 1
          if (Math.round(Number(m.width) / scale) === sw && Math.round(Number(m.height) / scale) === sh)
            return String(m.name)
        }
        return String(matches[0].name)
      }
    } catch (e2) {}

    // Primary Quickshell screen ↔ laptop connector; any other screen with a
    // single external Hyprland output ↔ that output (Miracast Extend case).
    try {
      var screens = Quickshell.screens
      var primary = screens && screens.length ? screens[0] : null
      var externals = []
      var laptop = null
      for (i = 0; i < monitors.length; i++) {
        m = monitors[i]
        if (!m || !m.name) continue
        if (root.isLaptopName(m.name))
          laptop = m
        else
          externals.push(m)
      }
      if (primary && screen === primary && laptop)
        return String(laptop.name)
      if ((!primary || screen !== primary) && externals.length === 1)
        return String(externals[0].name)
    } catch (e3) {}

    return screenName
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
    void root.hyprEpoch
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
    void root.hyprEpoch
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
      for (i = 0; i < monitors.length; i++) {
        if (!monitors[i] || !root.isLaptopName(monitors[i].name)) continue
        aw = monitors[i].activeWorkspace
        break
      }
    } else {
      for (i = 0; i < monitors.length; i++) {
        if (!monitors[i] || root.isLaptopName(monitors[i].name)) continue
        aw = monitors[i].activeWorkspace
        break
      }
    }

    if (Hyprland.focusedMonitor && monName
        && String(Hyprland.focusedMonitor.name || "") === monName
        && Hyprland.focusedWorkspace) {
      aw = Hyprland.focusedWorkspace
    }

    if (!aw && root.laptopMonitor && Hyprland.focusedWorkspace
        && Hyprland.focusedWorkspace.id >= 1 && Hyprland.focusedWorkspace.id <= 10) {
      if (!Hyprland.focusedMonitor || root.isLaptopName(Hyprland.focusedMonitor.name))
        aw = Hyprland.focusedWorkspace
    }

    return root.slotFromActiveWorkspace(aw)
  }

  function focusWorkspace(slot) {
    if (!root.bar) return
    root.bar.run("omarchy-hyprland-workspace-focus " + slot)
  }

  function bumpHyprEpoch() {
    root.hyprEpoch++
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.bumpHyprEpoch() }
    function onFocusedMonitorChanged() { root.bumpHyprEpoch() }
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      // workspace / workspacev2 / createworkspace / destroyworkspace /
      // moveworkspace / focusedmon / activewindow* — anything that can move
      // the filled slot or occupied opacity.
      if (name.indexOf("workspace") !== -1
          || name.indexOf("focusedmon") !== -1
          || name.indexOf("activewindow") !== -1
          || name.indexOf("monitor") !== -1
          || name === "configreloaded") {
        root.bumpHyprEpoch()
      }
    }
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
        readonly property bool occupied: {
          void root.hyprEpoch
          return workspace !== null && workspace.toplevels.values.length > 0
        }
        readonly property bool focused: root.activeSlot === modelData

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
