import QtQuick
import Quickshell
import qs.Commons

// Right-click menu, per the Magnify Dock design: 226px glass card, uppercase
// app title, 13.5px rows with a right-aligned hint, dividers, and hover fill.
DockGlass {
  id: root

  property var targetItem: null
  property bool isOpen: false
  property bool isAudioMuted: false
  property real textScale: 1
  property string fontFamily: Style.font.family
  readonly property bool containsPointer: menuHover.hovered

  signal pinToggled(var item)
  signal quitClicked(var item)
  signal launchClicked(var item)
  signal muteAudioToggled(var item)
  signal menuClosed()
  signal settingsRequested()

  readonly property bool running: targetItem ? targetItem.isRunning === true : false
  readonly property bool pinned: targetItem ? targetItem.isPinned === true : false
  readonly property var entries: {
    var rows = []
    if (root.targetItem) {
      rows.push({ kind: "item", label: root.running ? "Bring to Front" : "Open", hint: "", action: "launch" })
      rows.push({ kind: "item", label: root.pinned ? "Remove from Dock" : "Keep in Dock", hint: root.pinned ? "✓" : "", action: "pin" })
      rows.push({ kind: "item", label: root.isAudioMuted ? "Unmute Audio" : "Mute Audio", hint: root.isAudioMuted ? "✓" : "", action: "mute" })
      rows.push({ kind: "divider" })
      if (root.running) {
        rows.push({ kind: "item", label: "Close Window", hint: "", action: "quit" })
        rows.push({ kind: "divider" })
      }
    }
    rows.push({ kind: "item", label: "Dock Settings…", hint: "", action: "settings" })
    return rows
  }

  function activate(action) {
    var item = root.targetItem
    root.menuClosed()
    if (action === "launch") root.launchClicked(item)
    else if (action === "pin") root.pinToggled(item)
    else if (action === "mute") root.muteAudioToggled(item)
    else if (action === "quit") root.quitClicked(item)
    else if (action === "settings") root.settingsRequested()
  }

  open: isOpen
  visible: isOpen
  width: Math.round(226 * Math.max(1, Math.min(1.3, textScale)))
  height: column.implicitHeight + 10

  HoverHandler { id: menuHover }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: 4
    spacing: 0

    Text {
      visible: root.targetItem !== null
      width: parent.width
      leftPadding: 14
      rightPadding: 14
      topPadding: 9
      bottomPadding: 7
      elide: Text.ElideRight
      text: root.targetItem ? String(root.targetItem.name || "").toUpperCase() : ""
      font.family: root.fontFamily
      font.pixelSize: Math.round(11 * root.textScale)
      font.weight: Font.DemiBold
      font.letterSpacing: 1.1
      color: Qt.rgba(1, 1, 1, 0.4)
    }

    Repeater {
      model: root.entries
      delegate: Item {
        id: row
        required property var modelData
        width: column.width
        height: modelData.kind === "divider" ? 11 : Math.round(30 * root.textScale)

        Rectangle {
          visible: row.modelData.kind === "divider"
          anchors.centerIn: parent
          width: parent.width - 20
          height: 1
          color: Qt.rgba(1, 1, 1, 0.1)
        }

        Rectangle {
          visible: row.modelData.kind === "item"
          anchors.fill: parent
          anchors.leftMargin: 5
          anchors.rightMargin: 5
          radius: 8
          color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.label || ""
            font.family: root.fontFamily
            font.pixelSize: Math.round(13.5 * root.textScale)
            color: Qt.rgba(1, 1, 1, 0.92)
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.hint || ""
            font.family: root.fontFamily
            font.pixelSize: Math.round(12 * root.textScale)
            color: Qt.rgba(1, 1, 1, 0.92)
            opacity: 0.55
          }
          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activate(row.modelData.action)
          }
        }
      }
    }
  }
}
