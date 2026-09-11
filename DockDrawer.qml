import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "DockModel.js" as DockModel

// Full-screen application drawer opened from the dock's launcher tile, per
// the design: dimmed backdrop, a wide search field with an ESC badge, an
// uppercase heading, and a grid of 62px icons with labels. Escape or a click
// on the backdrop closes it; Enter launches the first match.
PanelWindow {
  id: root

  property bool open: false
  property var dockScreen: null
  property var appLibrary: null
  property real textScale: 1
  property string fontFamily: Style.font.family
  // Follows the dock's "Background opacity" setting: a solid backdrop at
  // 100%, more see-through as it is lowered.
  property real backdropOpacity: 0.9
  property color backdropColor: "#0a0c11"
  // Height of the dock's own window; the drawer stops above it so the dock
  // stays visible and clickable while the drawer is open, as in the design.
  property real bottomInset: 0
  property string query: ""

  signal drawerClosed()

  readonly property var apps: DockModel.drawerApps(DesktopEntries, root.appLibrary, Quickshell, root.query)

  function launch(app) {
    root.close()
    DockModel.handleItemClick(app, Util, root.appLibrary, DesktopEntries)
  }
  function close() {
    if (!root.open) return
    root.open = false
    root.drawerClosed()
  }

  onOpenChanged: {
    if (open) {
      root.query = ""
      searchInput.text = ""
      Qt.callLater(function() { searchInput.forceActiveFocus() })
    }
  }

  visible: open
  screen: dockScreen
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  margins { bottom: root.bottomInset }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-dock-drawer"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  Rectangle {
    id: backdrop
    anchors.fill: parent
    color: Qt.rgba(root.backdropColor.r, root.backdropColor.g, root.backdropColor.b, root.backdropOpacity)
    opacity: root.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Keys.onEscapePressed: root.close()

    // Search
    Rectangle {
      id: searchBox
      anchors.top: parent.top
      anchors.topMargin: Math.round(parent.height * 0.07)
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(560, parent.width * 0.8)
      height: Math.round(54 * Math.max(1, root.textScale))
      radius: 14
      color: Qt.rgba(1, 1, 1, 0.09)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.14)

      // Inset edge light that follows the rounded shape.
      Rectangle {
        anchors.fill: parent
        radius: 14
        gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
        GradientStop { position: 0.06; color: "transparent" }
        }
      }

      MouseArea { anchors.fill: parent; onClicked: searchInput.forceActiveFocus() }

      Text {
        id: searchGlyph
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        text: "󰍉"
        font.family: root.fontFamily
        font.pixelSize: 19
        color: "#ffffff"
        opacity: 0.55
      }

      TextInput {
        id: searchInput
        anchors.left: searchGlyph.right
        anchors.leftMargin: 12
        anchors.right: escBadge.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        font.family: root.fontFamily
        font.pixelSize: Math.round(20 * root.textScale)
        color: "#ffffff"
        selectionColor: Qt.rgba(1, 1, 1, 0.25)
        clip: true
        onTextChanged: root.query = text
        Keys.onEscapePressed: root.close()
        Keys.onReturnPressed: if (root.apps.length > 0) root.launch(root.apps[0])
        Keys.onEnterPressed: if (root.apps.length > 0) root.launch(root.apps[0])
        Text {
          visible: searchInput.text.length === 0
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          text: "Search applications"
          font: searchInput.font
          color: Qt.rgba(1, 1, 1, 0.38)
        }
      }

      Rectangle {
        id: escBadge
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        width: escLabel.implicitWidth + 14
        height: 21
        radius: 6
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        Text {
          id: escLabel
          anchors.centerIn: parent
          text: "ESC"
          font.family: root.fontFamily
          font.pixelSize: 11
          font.weight: Font.Medium
          font.letterSpacing: 0.5
          color: Qt.rgba(1, 1, 1, 0.5)
        }
      }
    }

    // Grid
    Item {
      id: gridArea
      anchors.top: searchBox.bottom
      anchors.topMargin: Math.round(parent.height * 0.05)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 24
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(880, parent.width * 0.92)
      opacity: root.open ? 1 : 0
      scale: root.open ? 1 : 0.97
      Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

      MouseArea { anchors.fill: parent }  // clicks inside do not close

      Text {
        id: heading
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.leftMargin: 10
        text: root.query.trim().length > 0 ? "RESULTS" : "ALL APPLICATIONS"
        font.family: root.fontFamily
        font.pixelSize: Math.round(11 * root.textScale)
        font.weight: Font.DemiBold
        font.letterSpacing: 1.5
        color: Qt.rgba(1, 1, 1, 0.42)
      }

      GridView {
        id: grid
        anchors.top: heading.bottom
        anchors.topMargin: 18
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: root.apps
        readonly property int columns: Math.max(1, Math.floor(width / 100))
        cellWidth: Math.floor(width / columns)
        cellHeight: Math.round(62 + 9 + 22 + 16 * root.textScale)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: grid.contentHeight > grid.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        delegate: Item {
          id: cell
          required property var modelData
          width: grid.cellWidth
          height: grid.cellHeight

          Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 14
            color: cellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
          }

          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 12
            spacing: 9
            DockTile {
              anchors.horizontalCenter: parent.horizontalCenter
              size: 62
              iconSource: cell.modelData.icon
              appName: cell.modelData.name
              fontFamily: root.fontFamily
              hovered: cellMouse.containsMouse
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              width: 92
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: cell.modelData.name
              font.family: root.fontFamily
              font.pixelSize: Math.round(12.5 * root.textScale)
              font.weight: Font.Medium
              color: Qt.rgba(1, 1, 1, 0.88)
            }
          }

          MouseArea {
            id: cellMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.launch(cell.modelData)
          }
        }
      }

      Text {
        visible: root.apps.length === 0
        anchors.top: heading.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        text: "No applications match “" + root.query + "”"
        font.family: root.fontFamily
        font.pixelSize: Math.round(15 * root.textScale)
        color: Qt.rgba(1, 1, 1, 0.45)
      }
    }
  }
}
