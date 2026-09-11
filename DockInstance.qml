import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import QtQml.Models
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

Item {
  id: root

  // Injected by Omarchy Shell
  property var shell: null
  property var manifest: null
  property var dockScreen: null
  property var appLibrary: shell ? shell.appLibrary : null

  // Geometry from the Magnify Dock design: 12px rail inset, rail height of
  // icon + 26, 17px dividers, magnification radius of 3.4 icon widths.
  property var preferences: DockModel.normalizeSettings(null)
  property real baseIconSize: root.iconPixelSize + 8
  property real iconPixelSize: root.preferences.iconSize
  property real maxMagnification: root.preferences.magnification
  property real magnifyRadius: root.iconPixelSize * 3.4
  property real dockPadding: DockModel.railPadding
  property real separatorWidth: DockModel.separatorWidth
  property real itemSpacing: root.preferences.spacing
  property real capsuleHeight: root.iconPixelSize + 26
  property real dockEdgeMargin: 14
  property real layoutExpansionRatio: 0.82
  property int magnificationDuration: 90
  readonly property real textScale: root.preferences.textScale || 1
  readonly property color accent: Color.accent
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  // Instrument Sans (OFL) ships with the plugin; fall back to the shell font.
  FontLoader { id: dockFont; source: Qt.resolvedUrl("fonts/InstrumentSans.ttf") }
  readonly property string fontFamily: dockFont.status === FontLoader.Ready ? dockFont.name : Style.font.family

  readonly property bool environmentReduceMotion: {
    var value = String(Quickshell.env("OMARCHY_REDUCE_MOTION") || "").toLowerCase()
    return value === "1" || value === "true" || value === "yes"
  }
  property bool systemReduceMotion: false
  readonly property bool reduceMotion: root.environmentReduceMotion || root.systemReduceMotion

  // Always visible macOS Mode
  property bool autoHide: false
  property bool reserveSpace: true
  property bool isDockHovered: false
  property bool edgeHovered: false
  property bool dockPresented: true
  property real hoverCursorX: -1
  property bool settingsOpen: false
  property bool pickerOpen: false
  property string pickerKey: ""
  property string pendingPickerKey: ""
  property string pickerTitle: ""
  property var windowMetadata: []
  property var windowRows: []
  property real pickerAnchorX: 0
  property real pickerAnchorY: 0
  readonly property var hyprMonitor: root.dockScreen ? Hyprland.monitorFor(root.dockScreen) : null
  readonly property var activeWorkspace: root.hyprMonitor ? root.hyprMonitor.activeWorkspace : null
  readonly property bool popupOpen: root.contextMenuOpen || root.pickerOpen || root.settingsOpen || appDrawer.open

  onActiveWorkspaceChanged: Qt.callLater(root.rebuildDock)
  onHyprMonitorChanged: Qt.callLater(root.rebuildDock)

  function changePreference(key, value) {
    var next = Object.assign({}, root.preferences)
    next[key] = value
    root.preferences = DockModel.normalizeSettings(next)
    root.rebuildDock()
    settingsSaveTimer.restart()
  }

  function openSettings() {
    root.closeContextMenu()
    root.clearTooltip()
    root.closePicker()
    root.settingsOpen = true
    root.revealDock()
  }

  function closeSettings() {
    root.settingsOpen = false
    root.scheduleDockHide()
  }

  function requestAppTooltip(item, target) {
    if (root.settingsOpen || root.contextMenuOpen || root.draggingPinnedIndex >= 0) return
    if (!item || !item.windows || item.windows.length === 0) {
      root.closePicker()
      root.requestTooltip(target, item ? item.name : "")
      return
    }
    root.clearTooltip()
    pickerHideTimer.stop()
    var point = dockPanel.contentItem.mapFromItem(target,
      target.width / 2 + Number(target.animatedOffsetX || 0), -8)
    root.pickerAnchorX = point.x
    root.pickerAnchorY = point.y
    root.pendingPickerKey = item.key
    if (root.pickerOpen) root.showPicker()
    else pickerShowTimer.restart()
  }

  function releaseAppTooltip(target) {
    root.releaseTooltip(target)
    pickerShowTimer.stop()
    root.pendingPickerKey = ""
    if (root.pickerOpen) pickerHideTimer.restart()
  }

  function showPicker() {
    root.pickerKey = root.pendingPickerKey
    root.pendingPickerKey = ""
    root.refreshPicker()
    root.pickerOpen = root.windowRows.length > 0
    if (root.pickerOpen) root.revealDock()
  }

  function refreshPicker() {
    var items = root.dockData.pinned.concat(root.dockData.unpinned)
    var item = items.find(function(value) { return value.key === root.pickerKey })
    root.pickerTitle = item ? item.name : ""
    root.windowRows = DockModel.pickerRows(item, root.windowMetadata)
    if (root.windowRows.length === 0) root.closePicker()
  }

  function closePicker() {
    pickerShowTimer.stop()
    pickerHideTimer.stop()
    root.pendingPickerKey = ""
    root.pickerKey = ""
    root.pickerOpen = false
    root.scheduleDockHide()
  }

  Timer { id: pickerShowTimer; interval: 380; onTriggered: root.showPicker() }
  Timer {
    id: pickerHideTimer
    interval: 320
    onTriggered: if (!windowPicker.containsPointer) root.closePicker()
  }
  Timer { id: settingsSaveTimer; interval: 300; onTriggered: root.saveConfig() }


  // Fixed invariant baseline geometry to eliminate jitter/shaking
  property var baselineGeometry: null

  // Magnification scales state
  property real launcherScale: 1.0
  property real animatedLauncherScale: root.launcherScale
  property real launcherOffsetX: 0
  property real animatedLauncherOffsetX: root.launcherOffsetX
  property var pinnedScales: []
  property var unpinnedScales: []
  property var pinnedOffsets: []
  property var unpinnedOffsets: []
  property real extraCapsuleWidth: 0
  property real animatedExtraCapsuleWidth: root.extraCapsuleWidth

  // Track fast pointer updates without restarting a discrete animation for
  // every event. This keeps the velocity continuous while entering, moving
  // across, and leaving the dock.
  Behavior on animatedLauncherScale {
    SmoothedAnimation {
      velocity: -1
      duration: root.reduceMotion ? 0 : root.magnificationDuration
      maximumEasingTime: root.reduceMotion ? 0 : 28
    }
  }

  Behavior on animatedLauncherOffsetX {
    SmoothedAnimation {
      velocity: -1
      duration: root.reduceMotion ? 0 : root.magnificationDuration
      maximumEasingTime: root.reduceMotion ? 0 : 28
    }
  }

  Behavior on animatedExtraCapsuleWidth {
    SmoothedAnimation {
      velocity: -1
      duration: root.reduceMotion ? 0 : root.magnificationDuration
      maximumEasingTime: root.reduceMotion ? 0 : 28
    }
  }

  // Dock items and pinned apps state
  // null means no saved preference; [] means explicitly no pinned apps.
  property var customPinnedApps: null
  property var dockData: ({ pinned: [], unpinned: [], totalItems: 0 })

  // Drag & drop reorder state
  property int draggingPinnedIndex: -1
  property int dragTargetIndex: -1
  property real dragGrabOffsetX: 0
  property real dragGrabOffsetY: 0
  property real dragVisualX: 0
  property real dragVisualY: 0
  property bool isDropSettling: false
  property real dropSettleStartX: 0
  property real dropSettleStartY: 0
  property real dropSettleTargetX: 0
  property real dropSettleProgress: 0.0

  NumberAnimation {
    id: dropSettleAnimation
    target: root
    property: "dropSettleProgress"
    from: 0.0
    to: 1.0
    duration: root.reduceMotion ? 0 : 180
    easing.type: Easing.OutCubic

    onRunningChanged: {
      if (!running && root.isDropSettling) {
        root.finishDropReorder()
      }
    }
  }

  onDropSettleProgressChanged: {
    if (root.isDropSettling) {
      root.dragVisualX = root.dropSettleStartX + (root.dropSettleTargetX - root.dropSettleStartX) * root.dropSettleProgress
      root.dragVisualY = root.dropSettleStartY * (1.0 - root.dropSettleProgress)
    }
  }

  // Hover Tooltip State
  property string tooltipText: ""
  property bool tooltipVisible: false
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string pendingTooltipText: ""

  // Context menu state is held by the dock so auto-hide remains suspended
  // while the menu is open.
  property bool contextMenuOpen: false
  property var contextTarget: null
  property var contextAnchor: null
  property double contextMenuOpenedAt: 0

  function requestTooltip(target, text) {
    if (root.draggingPinnedIndex >= 0 || root.settingsOpen || root.contextMenuOpen) return
    root.closePicker()
    tooltipHideTimer.stop()
    root.pendingTooltipTarget = target
    root.pendingTooltipText = String(text || "")

    if (root.tooltipVisible) {
      root.tooltipTarget = target
      root.tooltipText = root.pendingTooltipText
      root.pendingTooltipTarget = null
      root.pendingTooltipText = ""
      Qt.callLater(function() { tooltipWindow.anchor.updateAnchor() })
      return
    }
    tooltipShowTimer.restart()
  }

  function releaseTooltip(target) {
    if (root.pendingTooltipTarget === target) {
      tooltipShowTimer.stop()
      root.pendingTooltipTarget = null
      root.pendingTooltipText = ""
    }
    if (root.tooltipTarget === target) tooltipHideTimer.restart()
  }

  function clearTooltip() {
    tooltipShowTimer.stop()
    tooltipHideTimer.stop()
    root.tooltipVisible = false
    root.tooltipTarget = null
    root.pendingTooltipTarget = null
    root.pendingTooltipText = ""
  }

  function revealDock() {
    edgeRevealTimer.stop()
    hideDockTimer.stop()
    root.dockPresented = true
  }

  function scheduleDockHide() {
    // The edge is only a reveal trigger. Keeping it in this condition can
    // leave the dock permanently open after the first reveal because a
    // compositor does not always emit an exit while the input mask changes.
    if (root.autoHide && !root.isDockHovered && !root.popupOpen) {
      hideDockTimer.restart()
    }
  }

  function openContextMenu(item, target) {
    root.closePicker()
    root.clearTooltip()
    // Recreate the popup lifecycle for every request. Layer-shell geometry can
    // change after toggling reserve space; reusing an already-true visible
    // state may otherwise leave the compositor with a stale input surface.
    root.contextMenuOpen = false
    root.contextTarget = item
    root.contextAnchor = target
    root.contextMenuOpenedAt = Date.now()
    root.revealDock()
    Qt.callLater(function() {
      if (root.contextAnchor !== target) return
      root.contextMenuOpen = true
      Qt.callLater(function() {
        if (contextWindow && contextWindow.anchor && typeof contextWindow.anchor.updateAnchor === "function") {
          contextWindow.anchor.updateAnchor()
        }
      })
    })
  }

  function closeContextMenu() {
    root.contextMenuOpen = false
    root.contextTarget = null
    root.contextAnchor = null
    root.scheduleDockHide()
  }

  onAutoHideChanged: {
    if (root.autoHide) root.scheduleDockHide()
    else root.revealDock()
  }

  Timer {
    id: tooltipShowTimer
    interval: 380
    onTriggered: {
      if (!root.pendingTooltipTarget || root.pendingTooltipText === "") return
      root.tooltipTarget = root.pendingTooltipTarget
      root.tooltipText = root.pendingTooltipText
      root.pendingTooltipTarget = null
      root.pendingTooltipText = ""
      root.tooltipVisible = true
    }
  }

  Timer {
    id: tooltipHideTimer
    interval: 70
    onTriggered: root.clearTooltip()
  }

  Timer {
    id: edgeRevealTimer
    interval: root.preferences.revealDelay
    onTriggered: root.revealDock()
  }

  Timer {
    id: hideDockTimer
    interval: root.preferences.hideDelay
    onTriggered: {
      if (root.autoHide && !root.isDockHovered && !root.edgeHovered && !root.popupOpen) {
        root.clearTooltip()
        root.hoverCursorX = -1
        root.updateMagnification()
        root.dockPresented = false
      }
    }
  }

  // A popup normally closes through one of its actions or when the pointer
  // leaves it. This watchdog also recovers from a lost popup/input event so a
  // stale contextMenuOpen value can never disable auto-hide indefinitely.
  Timer {
    id: contextMenuDismissTimer
    interval: 180
    repeat: true
    running: root.contextMenuOpen
    onTriggered: {
      var graceElapsed = Date.now() - root.contextMenuOpenedAt > 900
      if (graceElapsed && !root.isDockHovered && !dockContextMenu.containsPointer) {
        root.closeContextMenu()
      }
    }
  }

  Process {
    id: reducedMotionProbe
    running: true
    command: ["gsettings", "get", "org.gnome.desktop.interface", "enable-animations"]
    stdout: SplitParser {
      onRead: function(line) {
        root.systemReduceMotion = String(line || "").trim() === "false"
      }
    }
  }

  // Muted Apps State Persistence & Audio Control
  readonly property string mutedAppsPath: Quickshell.env("HOME") + "/.config/omarchy/dock-muted-apps.json"
  readonly property string dockAudioScript: root.pluginDir + "/dock-audio.py"
  property var mutedAppsMap: ({})

  FileView {
    id: mutedAppsFileView
    path: root.mutedAppsPath
    watchChanges: true
    onFileChanged: reload()
    printErrors: false
    onLoaded: root.loadMutedApps(text())
    onLoadFailed: root.loadMutedApps("")
  }

  function loadMutedApps(rawText) {
    try {
      if (rawText && rawText.trim().length > 0) {
        var parsed = JSON.parse(rawText)
        if (parsed && typeof parsed === "object") {
          root.mutedAppsMap = parsed
          return
        }
      }
    } catch (e) {}
    root.mutedAppsMap = ({})
  }

  function isAppAudioMuted(item) {
    if (!item) return false
    var map = root.mutedAppsMap || {}
    var id = String(item.id || "")
    var name = String(item.name || "")
    if (id && map[id] === true) return true
    if (name && map[name] === true) return true
    for (var k in map) {
      if (!map[k]) continue
      if (id && (k === id || DockModel.matchApp(k, id))) return true
      if (name && (k === name || DockModel.normalizeId(k) === DockModel.normalizeId(name))) return true
    }
    return false
  }

  function toggleAppAudio(item) {
    if (!item) return
    var appId = String(item.id || "")
    var appName = String(item.name || "")
    // Update the intent map before the script runs so the sync timer stops
    // immediately on unmute; otherwise it can re-mute the stream in the gap
    // before the persisted file is reloaded.
    var next = Object.assign({}, root.mutedAppsMap)
    if (root.isAppAudioMuted(item)) {
      if (appId) delete next[appId]
      if (appName) delete next[appName]
    } else {
      if (appId) next[appId] = true
      if (appName) next[appName] = true
    }
    root.mutedAppsMap = next
    var cmd = "python3 " + Util.shellQuote(root.dockAudioScript) + " toggle " + Util.shellQuote(appId) + " " + Util.shellQuote(appName)
    Util.execDetached(cmd)
  }

  // A saved mute must also cover streams that appear after the menu action,
  // otherwise muting a silent app (or one that restarts playback) has no effect.
  Timer {
    id: audioSyncTimer
    interval: 1500
    repeat: true
    running: Object.keys(root.mutedAppsMap).length > 0
    onTriggered: audioSyncProc.running = true
  }

  Process {
    id: audioSyncProc
    command: ["python3", root.dockAudioScript, "sync"]
  }

  // Settings File Persistence
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/dock-pinned-macos.json"

  FileView {
    id: configFileView
    path: root.configPath
    watchChanges: true
    onFileChanged: reload()
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("")
  }

  function loadConfig(rawText) {
    try {
      if (rawText && rawText.trim().length > 0) {
        var parsed = JSON.parse(rawText)
        if (parsed.settings && !settingsSaveTimer.running) {
          root.preferences = DockModel.normalizeSettings(parsed.settings)
        }
        if (Array.isArray(parsed.pinned)) {
          root.customPinnedApps = parsed.pinned
        }
        if (typeof parsed.autoHide === "boolean") {
          root.autoHide = parsed.autoHide
        }
        if (typeof parsed.reserveSpace === "boolean") {
          root.reserveSpace = parsed.reserveSpace
        }
      }
    } catch (e) {}
    root.rebuildDock()
  }

  function saveConfig() {
    var payload = {
      version: 1,
      settings: root.preferences,
      autoHide: root.autoHide,
      reserveSpace: root.reserveSpace,
      pinned: Array.isArray(root.customPinnedApps) ? root.customPinnedApps : DockModel.defaultPinnedApps
    }
    var jsonStr = JSON.stringify(payload, null, 2)
    if (Util && typeof Util.execDetached === "function") {
      var tmpPath = root.configPath + ".tmp." + Date.now()
      var cmd = "printf '%s\\n' " + Util.shellQuote(jsonStr) + " > " + Util.shellQuote(tmpPath) + " && mv " + Util.shellQuote(tmpPath) + " " + Util.shellQuote(root.configPath)
      Util.execDetached(cmd)
    }
  }

  function togglePinApp(appId) {
    if (!appId) return
    var currentList = Array.isArray(root.customPinnedApps)
      ? root.customPinnedApps
      : DockModel.defaultPinnedApps
    var list = currentList.slice()
    var idx = -1
    for (var i = 0; i < list.length; i++) {
      var p = typeof list[i] === "string" ? list[i] : (list[i].id || "")
      if (p === appId || DockModel.matchApp(p, appId)) {
        idx = i
        break
      }
    }

    if (idx >= 0) {
      list.splice(idx, 1)
    } else {
      list.push(appId)
    }
    root.customPinnedApps = list
    root.saveConfig()
    root.rebuildDock()
  }

  function rebuildDock() {
    var toplevels = []
    try {
      toplevels = ToplevelManager.toplevels.values
    } catch (e) {
      toplevels = []
    }

    root.windowMetadata = DockModel.toArray(Hyprland.toplevels.values).map(function(win) {
      return {
        window: win.wayland,
        monitorName: win.monitor ? win.monitor.name : "",
        workspaceId: win.workspace ? win.workspace.id : null,
        workspaceName: win.workspace ? win.workspace.name : ""
      }
    })
    var visibleWindows = DockModel.filterWindows(toplevels, root.windowMetadata,
      root.preferences.windowScope, root.dockScreen ? root.dockScreen.name : "",
      root.activeWorkspace ? root.activeWorkspace.id : null)
    var data = DockModel.buildDockItems(
      visibleWindows,
      DesktopEntries,
      root.appLibrary,
      Quickshell,
      root.customPinnedApps
    )
    root.dockData = data
    if (root.pickerOpen) root.refreshPicker()

    var pCount = data.pinned ? data.pinned.length : 0
    var uCount = data.unpinned ? data.unpinned.length : 0
    root.baselineGeometry = DockModel.computeBaselineCenters(
      root.baseIconSize,
      root.itemSpacing,
      root.dockPadding,
      pCount,
      uCount,
      root.separatorWidth
    )

    updateMagnification()
  }

  function handleItemDragStarted(index, itemData, sceneX, sceneY) {
    if (dropSettleAnimation.running) {
      dropSettleAnimation.stop()
      root.finishDropReorder()
    }
    root.clearTooltip()
    root.closePicker()
    root.isDropSettling = false
    root.draggingPinnedIndex = index
    root.dragTargetIndex = index

    var geo = root.baselineGeometry
    if (!geo || !geo.pinned || index >= geo.pinned.length) return

    var pt = dockCapsule.mapFromItem(null, sceneX, sceneY)
    var slotCenterX = geo.pinned[index]
    var slotCenterY = root.capsuleHeight - 5 - (root.iconPixelSize / 2)
    root.dragGrabOffsetX = pt.x - slotCenterX
    root.dragGrabOffsetY = pt.y - slotCenterY
    root.dragVisualX = 0
    root.dragVisualY = 0

    // Magnification is suspended for the complete drag. Clearing these once
    // avoids rebuilding arrays on every high-frequency pointer event.
    root.launcherScale = 1.0
    root.launcherOffsetX = 0
    root.pinnedScales = []
    root.unpinnedScales = []
    root.pinnedOffsets = []
    root.unpinnedOffsets = []
    root.extraCapsuleWidth = 0

    root.updateDragState(pt.x - root.dragGrabOffsetX)
  }

  function handleItemDragMoved(index, itemData, sceneX, sceneY) {
    if (root.isDropSettling) return
    var geo = root.baselineGeometry
    if (!geo || !geo.pinned || index >= geo.pinned.length) return

    var pt = dockCapsule.mapFromItem(null, sceneX, sceneY)
    var slotCenterX = geo.pinned[index]
    var slotCenterY = root.capsuleHeight - 5 - (root.iconPixelSize / 2)
    root.dragVisualX = pt.x - slotCenterX - root.dragGrabOffsetX
    root.dragVisualY = Math.max(-20, Math.min(8, pt.y - slotCenterY - root.dragGrabOffsetY))

    root.updateDragState(pt.x - root.dragGrabOffsetX)
  }

  function updateDragState(currentCenterX) {
    var geo = root.baselineGeometry
    if (!geo || !geo.pinned || geo.pinned.length === 0) return

    var fromIdx = root.draggingPinnedIndex
    var pCenters = geo.pinned
    var pCount = pCenters.length

    var currentTarget = root.dragTargetIndex >= 0 ? root.dragTargetIndex : fromIdx
    var slotWidth = root.baseIconSize + root.itemSpacing
    var hysteresisMargin = slotWidth * 0.22 // ~10.5px directional deadzone to eliminate boundary jitter

    var bestIdx = currentTarget
    var bestDist = Math.abs(currentCenterX - pCenters[currentTarget]) - hysteresisMargin

    for (var i = 0; i < pCount; i++) {
      if (i === currentTarget) continue
      var dist = Math.abs(currentCenterX - pCenters[i])
      if (dist < bestDist) {
        bestDist = dist
        bestIdx = i
      }
    }
    // The dragged icon follows the pointer every frame, but neighbor layout
    // only changes when a slot boundary is crossed. Avoiding identical array
    // assignments keeps the QML animation scheduler off the pointer hot path.
    if (bestIdx === currentTarget && root.pinnedOffsets.length === pCount) return
    root.dragTargetIndex = bestIdx

    // Shift neighbor slots to preview the new layout
    var pOffsets = []
    var toIdx = root.dragTargetIndex

    for (var j = 0; j < pCount; j++) {
      if (j === fromIdx) {
        pOffsets.push(0)
      } else if (toIdx > fromIdx && j > fromIdx && j <= toIdx) {
        pOffsets.push(-slotWidth)
      } else if (toIdx < fromIdx && j >= toIdx && j < fromIdx) {
        pOffsets.push(slotWidth)
      } else {
        pOffsets.push(0)
      }
    }
    root.pinnedOffsets = pOffsets
  }

  function handleItemDragEnded(index, itemData, sourceItem) {
    var fromIdx = root.draggingPinnedIndex
    var toIdx = root.dragTargetIndex
    var geo = root.baselineGeometry

    if (fromIdx < 0 || !geo || !geo.pinned || fromIdx >= geo.pinned.length) {
      root.draggingPinnedIndex = -1
      root.dragTargetIndex = -1
      root.dragVisualX = 0
      root.dragVisualY = 0
      root.dragGrabOffsetX = 0
      root.dragGrabOffsetY = 0
      root.pinnedOffsets = []
      root.updateMagnification()
      return
    }

    var targetIdx = (toIdx >= 0 && toIdx < geo.pinned.length) ? toIdx : fromIdx
    root.dropSettleStartX = root.dragVisualX
    root.dropSettleStartY = root.dragVisualY
    // Distance from the starting slot center to the target slot center
    root.dropSettleTargetX = geo.pinned[targetIdx] - geo.pinned[fromIdx]
    root.dropSettleProgress = 0.0
    root.isDropSettling = true
    dropSettleAnimation.restart()
  }

  function finishDropReorder() {
    root.isDropSettling = false
    var fromIdx = root.draggingPinnedIndex
    var toIdx = root.dragTargetIndex

    root.draggingPinnedIndex = -1
    root.dragTargetIndex = -1
    root.dragVisualX = 0
    root.dragVisualY = 0
    root.dragGrabOffsetX = 0
    root.dragGrabOffsetY = 0

    if (fromIdx >= 0 && toIdx >= 0 && fromIdx !== toIdx) {
      root.reorderPinnedApps(fromIdx, toIdx)
    } else {
      root.pinnedOffsets = []
      root.updateMagnification()
    }
  }

  function reorderPinnedApps(fromIndex, toIndex) {
    var currentList = Array.isArray(root.customPinnedApps)
      ? root.customPinnedApps.slice()
      : DockModel.defaultPinnedApps.slice()

    if (fromIndex < 0 || fromIndex >= currentList.length || toIndex < 0 || toIndex >= currentList.length) {
      root.pinnedOffsets = []
      root.updateMagnification()
      return
    }

    var moved = currentList.splice(fromIndex, 1)[0]
    currentList.splice(toIndex, 0, moved)

    root.customPinnedApps = currentList
    root.saveConfig()
    root.rebuildDock()
  }

  function updateMagnification() {
    if (root.draggingPinnedIndex >= 0) return
    if (!root.isDockHovered || root.hoverCursorX < 0) {
      root.launcherScale = 1.0
      root.launcherOffsetX = 0
      root.pinnedScales = []
      root.unpinnedScales = []
      root.pinnedOffsets = []
      root.unpinnedOffsets = []
      root.extraCapsuleWidth = 0
      return
    }

    var geo = root.baselineGeometry
    if (!geo) return

    // Capsule width and item slots stay fixed, so pointer coordinates already
    // map to the invariant resting geometry without feedback compensation.
    var baseCursorX = root.hoverCursorX

    // Applications launcher scale
    root.launcherScale = DockModel.scaleFromDistance(
      Math.abs(baseCursorX - geo.launcher),
      root.maxMagnification,
      root.magnifyRadius
    )

    // Pinned items scales
    var pScales = []
    for (var p = 0; p < geo.pinned.length; p++) {
      pScales.push(DockModel.scaleFromDistance(
        Math.abs(baseCursorX - geo.pinned[p]),
        root.maxMagnification,
        root.magnifyRadius
      ))
    }
    root.pinnedScales = pScales

    // Unpinned items scales
    var uScales = []
    for (var u = 0; u < geo.unpinned.length; u++) {
      uScales.push(DockModel.scaleFromDistance(
        Math.abs(baseCursorX - geo.unpinned[u]),
        root.maxMagnification,
        root.magnifyRadius
      ))
    }
    root.unpinnedScales = uScales

    var allScales = [root.launcherScale].concat(pScales).concat(uScales)
    var offsets = DockModel.computeMagnifiedOffsets(
      allScales,
      root.baseIconSize,
      root.layoutExpansionRatio
    )
    root.launcherOffsetX = offsets.length > 0 ? offsets[0] : 0
    root.pinnedOffsets = offsets.slice(1, 1 + pScales.length)
    root.unpinnedOffsets = offsets.slice(1 + pScales.length)
    root.extraCapsuleWidth = (typeof offsets.totalExtra === "number") ? offsets.totalExtra : 0
  }

  // Observe each window, including moves that do not change the global list.
  Instantiator {
    model: Hyprland.toplevels
    delegate: Connections {
      required property var modelData
      target: modelData
      function onWorkspaceChanged() { Qt.callLater(root.rebuildDock) }
      function onMonitorChanged() { Qt.callLater(root.rebuildDock) }
      function onTitleChanged() { Qt.callLater(root.rebuildDock) }
      function onWaylandHandleChanged() { Qt.callLater(root.rebuildDock) }
    }
  }
  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { Qt.callLater(root.rebuildDock) }
  }

  // Reactive listeners for window and app changes
  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.rebuildDock() }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.rebuildDock() }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuildDock() }
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.rebuildDock() }
  }

  function toggleDrawer() {
    if (appDrawer.open) { appDrawer.close(); return }
    root.closeContextMenu()
    root.closePicker()
    root.clearTooltip()
    root.settingsOpen = false
    root.revealDock()
    appDrawer.open = true
  }

  // `omarchy-shell magnify-dock drawer` toggles the app drawer (bind it to a
  // key); `settings` opens the settings card; `status` reports state.
  IpcHandler {
    target: "magnify-dock"
    function drawer(): string { root.toggleDrawer(); return appDrawer.open ? "open" : "closed" }
    function settings(): string { if (root.settingsOpen) root.closeSettings(); else root.openSettings(); return root.settingsOpen ? "open" : "closed" }
    function autoHide(): string { root.autoHide = !root.autoHide; root.saveConfig(); return root.autoHide ? "on" : "off" }
    function status(): string {
      return JSON.stringify({ screen: root.dockScreen ? root.dockScreen.name : "", pinned: root.dockData.pinned.length, running: root.dockData.unpinned.length, autoHide: root.autoHide, reserveSpace: root.reserveSpace, drawer: appDrawer.open, settings: root.settingsOpen })
    }
  }

  DockDrawer {
    id: appDrawer
    dockScreen: root.dockScreen
    appLibrary: root.appLibrary
    textScale: root.textScale
    fontFamily: root.fontFamily
    backdropOpacity: root.preferences.opacity
    bottomInset: dockPanel.implicitHeight
    onDrawerClosed: root.scheduleDockHide()
  }

  Component.onCompleted: {
    console.log("Magnify Dock instance ready", root.dockScreen ? root.dockScreen.name : "no-screen")
    if (root.appLibrary) root.appLibrary.refreshIcons()
    root.rebuildDock()
  }

  // macOS Dock Panel Window
  PanelWindow {
    id: dockPanel
    visible: true
    screen: root.dockScreen

    anchors {
      bottom: true
      left: true
      right: true
    }

    margins {
      bottom: 0
    }

    implicitWidth: 0
    implicitHeight: root.capsuleHeight
      + root.dockEdgeMargin
      + Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0))
      + 24
    color: "transparent"

    WlrLayershell.namespace: "omarchy-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    
    // Reserve bottom space so Hyprland windows stop cleanly above the dock
    exclusionMode: root.reserveSpace && !root.autoHide
      ? ExclusionMode.Normal
      : ExclusionMode.Ignore
    exclusiveZone: root.capsuleHeight + root.dockEdgeMargin + 6

    // Single dynamic hit area bound directly to mask so Quickshell updates
    // the Wayland input region on geometry changes without nested region issues.
    Item {
      id: dockHitArea
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: (!root.autoHide || root.dockPresented)
        ? (dockCapsule.width + Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0) * 2) + 8)
        : (root.autoHide ? (dockCapsule.width + 160) : 0)
      height: (!root.autoHide || root.dockPresented)
        ? (root.capsuleHeight + root.dockEdgeMargin + Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0)) + 14)
        : (root.autoHide ? 4 : 0)
    }

    mask: Region {
      item: dockHitArea
    }

    // A separate popup surface can rise above the layer window without being
    // clipped by its compact exclusive-zone height.
    PopupWindow {
      id: tooltipWindow
      visible: root.tooltipVisible
        && root.tooltipTarget !== null
        && root.tooltipText !== ""
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        window: dockPanel
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!target) return
          try {
            var targetOffset = Number(target.animatedOffsetX || 0)
            var localX = target.width / 2 - tooltipWindow.implicitWidth / 2 + targetOffset
            var localY = -tooltipWindow.implicitHeight - Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0)) - 12
            var point = dockPanel.contentItem.mapFromItem(target, localX, localY)
            tooltipWindow.anchor.rect.x = Math.round(point.x)
            tooltipWindow.anchor.rect.y = Math.round(point.y)
          } catch (e) {}
        }
      }

      Rectangle {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 22
        implicitHeight: tooltipLabel.implicitHeight + 10
        radius: 8
        color: Qt.rgba(24 / 255, 26 / 255, 33 / 255, Math.max(0.9, root.preferences.opacity))
        border.color: Qt.rgba(1, 1, 1, 0.13)
        border.width: 1

        Text {
          id: tooltipLabel
          anchors.centerIn: parent
          text: root.tooltipText
          font.family: root.fontFamily
          font.pixelSize: Math.round(12.5 * root.textScale)
          font.weight: Font.Medium
          color: Qt.rgba(1, 1, 1, 0.95)
        }
      }
    }

    PopupWindow {
      id: pickerWindow
      visible: root.pickerOpen
      color: "transparent"
      implicitWidth: windowPicker.width
      implicitHeight: windowPicker.height
      anchor {
        window: dockPanel
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.x: Math.round(root.pickerAnchorX - pickerWindow.implicitWidth / 2)
        rect.y: Math.round(root.pickerAnchorY - pickerWindow.implicitHeight)
        rect.width: 1
        rect.height: 1
      }
      DockWindowPicker {
        id: windowPicker
        title: root.pickerTitle
        rows: root.windowRows
        textScale: root.textScale
        accent: root.accent
        fontFamily: root.fontFamily
        glassOpacity: root.preferences.opacity
        maxHeight: Math.max(120, (root.dockScreen ? root.dockScreen.height : 720) - dockPanel.height - 32)
        onContainsPointerChanged: {
          if (containsPointer) pickerHideTimer.stop()
          else if (root.pickerOpen) pickerHideTimer.restart()
        }
        onWindowActivated: function(win) {
          root.closePicker()
          DockModel.activateWindow(win)
        }
        onWindowClosed: function(win) { DockModel.closeAppWindow({ windows: [win] }) }
        onDismissed: root.closePicker()
      }
    }

    PopupWindow {
      id: settingsWindow
      visible: root.settingsOpen
      color: "transparent"
      implicitWidth: settingsPanel.width
      implicitHeight: settingsPanel.height
      anchor {
        window: dockPanel
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.x: Math.round((dockPanel.width - settingsWindow.implicitWidth) / 2)
        rect.y: Math.round(dockPanel.height - root.capsuleHeight - settingsWindow.implicitHeight - 12)
        rect.width: 1
        rect.height: 1
      }
      DockSettings {
        id: settingsPanel
        settings: root.preferences
        isAutoHide: root.autoHide
        isReserveSpace: root.reserveSpace
        accent: root.accent
        fontFamily: root.fontFamily
        glassOpacity: root.preferences.opacity
        maxHeight: Math.max(180, (root.dockScreen ? root.dockScreen.height : 720) - dockPanel.height - 32)
        onPreferenceChanged: function(key, value) { root.changePreference(key, value) }
        onAutoHideToggled: { root.autoHide = !root.autoHide; root.saveConfig() }
        onReserveSpaceToggled: { root.reserveSpace = !root.reserveSpace; root.saveConfig() }
        onDismissed: root.closeSettings()
      }
    }

    PopupWindow {
      id: contextWindow
      visible: root.contextMenuOpen && root.contextAnchor !== null
      color: "transparent"
      implicitWidth: dockContextMenu.width
      implicitHeight: dockContextMenu.height

      anchor {
        window: dockPanel
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.contextAnchor
          if (!target) return
          try {
            var targetOffset = Number(target.animatedOffsetX || 0)
            var localX = target.width / 2 - contextWindow.implicitWidth / 2 + targetOffset
            var localY = -contextWindow.implicitHeight - 10
            var point = dockPanel.contentItem.mapFromItem(target, localX, localY)
            contextWindow.anchor.rect.x = Math.round(point.x)
            contextWindow.anchor.rect.y = Math.round(point.y)
          } catch (e) {}
        }
      }

      DockContextMenu {
        id: dockContextMenu
        targetItem: root.contextTarget
        isOpen: root.contextMenuOpen
        isAudioMuted: root.isAppAudioMuted(root.contextTarget)
        textScale: root.textScale
        fontFamily: root.fontFamily
        glassOpacity: root.preferences.opacity

        onLaunchClicked: function(item) {
          DockModel.handleItemClick(item, Util, root.appLibrary, DesktopEntries)
        }
        onPinToggled: function(item) {
          if (item && item.id) root.togglePinApp(item.id)
        }
        onQuitClicked: function(item) {
          DockModel.closeAppWindow(item)
        }
        onMuteAudioToggled: function(item) {
          root.toggleAppAudio(item)
        }
        onSettingsRequested: root.openSettings()
        onMenuClosed: root.closeContextMenu()
      }
    }

    Item {
      id: edgeRevealArea
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: dockCapsule.width + 160
      height: root.autoHide ? 4 : 0

      HoverHandler {
        onHoveredChanged: {
          root.edgeHovered = hovered
          if (hovered) {
            if (!root.dockPresented) edgeRevealTimer.restart()
          } else {
            edgeRevealTimer.stop()
            root.scheduleDockHide()
          }
        }
        onPointChanged: {
          if (hovered && root.autoHide && !root.dockPresented && !edgeRevealTimer.running) {
            edgeRevealTimer.start()
          }
        }
      }
    }

    Item {
      id: dockInteractionRegion
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: dockCapsule.width
        + Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0) * 2)
        + 8
      height: root.capsuleHeight
        + Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0))
        + 14

      Item {
        id: dockInputRegion
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: (!root.autoHide || root.dockPresented) ? parent.width : 0
        height: (!root.autoHide || root.dockPresented) ? parent.height : 0
        visible: !root.autoHide || root.dockPresented
      }

      // The capsule and its hit envelope share this parent. When reveal swaps
      // input from the thin edge to the dock, hover ownership transfers inside
      // one subtree instead of briefly exiting the panel.
      HoverHandler {
        id: dockHover
        enabled: !root.autoHide || root.dockPresented
        onHoveredChanged: {
          root.isDockHovered = hovered
          if (hovered) {
            root.revealDock()
          } else {
            root.hoverCursorX = -1
            root.clearTooltip()
            root.updateMagnification()
            root.scheduleDockHide()
          }
        }
        onPointChanged: {
          if (hovered) {
            var centerDelta = point.position.x - (dockInteractionRegion.width / 2)
            var baseWidth = root.baselineGeometry ? root.baselineGeometry.totalBaseWidth : dockCapsule.width
            root.isDockHovered = true
            root.hoverCursorX = (baseWidth / 2) + centerDelta
            root.updateMagnification()
          }
        }
      }

      // Soft drop shadow under the capsule (design: 0 14px 44px rgba(0,0,0,0.45)).
      Rectangle {
        id: capsuleShadowSource
        anchors.fill: dockCapsule
        radius: dockCapsule.radius
        color: Qt.rgba(0, 0, 0, 0.45)
        visible: false
      }
      MultiEffect {
        anchors.fill: capsuleShadowSource
        anchors.topMargin: 10
        source: capsuleShadowSource
        blurEnabled: true
        blur: 1.0
        blurMax: 40
        autoPaddingEnabled: true
        z: -1
        transform: Translate { y: capsuleSlide.y }
      }

      // Frosted glass capsule (design tokens: rgba(18,20,26,opacity), 19px
      // radius, 1px white/13% border, white/14% top highlight).
      Rectangle {
        id: dockCapsule
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.dockEdgeMargin

      height: root.capsuleHeight
      width: contentRow.width + root.dockPadding * 2 + root.animatedExtraCapsuleWidth
      radius: 19
      transform: Translate {
        id: capsuleSlide
        y: root.autoHide && !root.dockPresented ? root.capsuleHeight + 30 : 0
        Behavior on y {
          NumberAnimation {
            duration: root.reduceMotion ? 0 : 320
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.3, 0.8, 0.3, 1, 1, 1]
          }
        }
      }

      color: Qt.rgba(18 / 255, 20 / 255, 26 / 255, root.preferences.opacity)
      border.color: Qt.rgba(1, 1, 1, 0.13)
      border.width: 1

      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 1
        height: 1
        radius: 19
        color: Qt.rgba(1, 1, 1, 0.14)
      }

      // Main Items Content Row
      Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: root.itemSpacing

        // Application launcher (same action as SUPER + ALT + SPACE)
        Item {
          id: launcherItem
          width: root.baseIconSize
          height: root.baseIconSize
          z: root.animatedLauncherScale

          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5
            width: root.iconPixelSize
            height: root.iconPixelSize
            transformOrigin: Item.Bottom
            scale: root.animatedLauncherScale
            transform: Translate { x: root.animatedLauncherOffsetX }

            // Launcher tile: white glass gradient, 24% radius, 3×3 dot grid.
            Rectangle {
              anchors.fill: parent
              radius: Math.round(root.iconPixelSize * 0.24)
              gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, launcherMouse.containsMouse || appDrawer.open ? 0.28 : 0.2) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, launcherMouse.containsMouse || appDrawer.open ? 0.16 : 0.1) }
              }
              border.width: 0

              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: 1
                radius: parent.radius
                color: Qt.rgba(1, 1, 1, 0.28)
              }

              Grid {
                anchors.centerIn: parent
                columns: 3
                rows: 3
                spacing: Math.max(2, Math.round(root.iconPixelSize * 0.11))
                Repeater {
                  model: 9
                  delegate: Rectangle {
                    width: Math.max(3, Math.round(root.iconPixelSize * 0.1))
                    height: width
                    radius: width / 2
                    color: Qt.rgba(1, 1, 1, 0.92)
                  }
                }
              }
            }

            MouseArea {
              id: launcherMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton

              onEntered: root.requestTooltip(launcherItem, "Applications")
              onExited: root.releaseTooltip(launcherItem)
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) root.openSettings()
                else root.toggleDrawer()
              }
            }
          }
        }

        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: root.separatorWidth
          height: root.iconPixelSize - 6
          Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.16) }
        }

        // Pinned Apps
        Repeater {
          id: pinnedRepeater
          model: root.dockData.pinned

          delegate: DockItem {
            required property var modelData
            required property int index

            itemData: modelData
            itemIndex: index
            baseSize: root.baseIconSize
            iconSize: root.iconPixelSize
            isDockHovered: root.isDockHovered
            magnificationDuration: root.magnificationDuration
            reduceMotion: root.reduceMotion
            accent: root.accent
            fontFamily: root.fontFamily
            isBeingDragged: root.draggingPinnedIndex === index
            isReordering: root.draggingPinnedIndex >= 0
            dragVisualX: root.draggingPinnedIndex === index ? root.dragVisualX : 0
            dragVisualY: root.draggingPinnedIndex === index ? root.dragVisualY : 0
            targetScale: (Array.isArray(root.pinnedScales) && index < root.pinnedScales.length) ? root.pinnedScales[index] : 1.0
            targetOffsetX: (Array.isArray(root.pinnedOffsets) && index < root.pinnedOffsets.length) ? root.pinnedOffsets[index] : 0

            onClicked: function(item) {
              DockModel.handleItemClick(item, Util, root.appLibrary, DesktopEntries)
            }

            onPinToggleRequested: function(item) {
              if (item && item.id) {
                root.togglePinApp(item.id)
              }
            }

            onCloseRequested: function(item) {
              DockModel.closeAppWindow(item)
            }

            onContextMenuRequested: function(item, srcItem) {
              root.openContextMenu(item, srcItem)
            }

            onHovered: function(item, srcItem) {
              if (root.draggingPinnedIndex >= 0) return
              root.requestAppTooltip(item, srcItem)
            }

            onUnhovered: function(srcItem) {
              root.releaseAppTooltip(srcItem)
            }

            onDragStarted: function(idx, item, sceneX, sceneY) {
              root.handleItemDragStarted(idx, item, sceneX, sceneY)
            }

            onDragMoved: function(idx, item, sceneX, sceneY) {
              root.handleItemDragMoved(idx, item, sceneX, sceneY)
            }

            onDragEnded: function(idx, item, srcItem) {
              root.handleItemDragEnded(idx, item, srcItem)
            }
          }
        }

        // Separator between pinned and unpinned running apps
        Item {
          visible: (root.dockData.pinned && root.dockData.pinned.length > 0)
            && (root.dockData.unpinned && root.dockData.unpinned.length > 0)
          anchors.verticalCenter: parent.verticalCenter
          width: root.separatorWidth
          height: root.iconPixelSize - 6
          Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.16) }
        }

        // Unpinned Running Apps
        Repeater {
          id: unpinnedRepeater
          model: root.dockData.unpinned

          delegate: DockItem {
            required property var modelData
            required property int index

            itemData: modelData
            itemIndex: (root.dockData.pinned ? root.dockData.pinned.length : 0) + index
            baseSize: root.baseIconSize
            iconSize: root.iconPixelSize
            isDockHovered: root.isDockHovered
            magnificationDuration: root.magnificationDuration
            reduceMotion: root.reduceMotion
            accent: root.accent
            fontFamily: root.fontFamily
            targetScale: (Array.isArray(root.unpinnedScales) && index < root.unpinnedScales.length) ? root.unpinnedScales[index] : 1.0
            targetOffsetX: (Array.isArray(root.unpinnedOffsets) && index < root.unpinnedOffsets.length) ? root.unpinnedOffsets[index] : 0

            onClicked: function(item) {
              DockModel.handleItemClick(item, Util, root.appLibrary, DesktopEntries)
            }

            onPinToggleRequested: function(item) {
              if (item && item.id) {
                root.togglePinApp(item.id)
              }
            }

            onCloseRequested: function(item) {
              DockModel.closeAppWindow(item)
            }

            onContextMenuRequested: function(item, srcItem) {
              root.openContextMenu(item, srcItem)
            }

            onHovered: function(item, srcItem) {
              root.requestAppTooltip(item, srcItem)
            }

            onUnhovered: function(srcItem) {
              root.releaseAppTooltip(srcItem)
            }
          }
        }
      }

      }
    }
  }
}
