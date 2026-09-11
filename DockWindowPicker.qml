import QtQuick
import QtQuick.Controls
import qs.Commons

// Window list for an app, per the design: 280px glass card, uppercase
// "APP — N WINDOWS" title, rows with an activity dot, title, location, and a
// close control that appears on hover.
DockGlass {
  id: root

  property string title: ""
  property var rows: []
  property real maxHeight: 420
  property real textScale: 1
  property string fontFamily: Style.font.family
  property color accent: Color.accent
  readonly property bool containsPointer: hover.hovered

  signal windowActivated(var win)
  signal windowClosed(var win)
  signal dismissed()

  open: visible
  width: Math.round(280 * Math.max(1, Math.min(1.3, textScale)))
  height: Math.min(maxHeight, header.height + list.contentHeight + 12)

  HoverHandler { id: hover }

  Text {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    leftPadding: 14
    rightPadding: 14
    topPadding: 10
    bottomPadding: 6
    elide: Text.ElideRight
    text: (root.title + " — " + root.rows.length + (root.rows.length === 1 ? " window" : " windows")).toUpperCase()
    font.family: root.fontFamily
    font.pixelSize: Math.round(11 * root.textScale)
    font.weight: Font.DemiBold
    font.letterSpacing: 1.1
    color: Qt.rgba(1, 1, 1, 0.4)
  }

  ListView {
    id: list
    anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 7 }
    clip: true
    model: root.rows
    spacing: 0
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

    delegate: Item {
      id: windowRow
      required property var modelData
      width: list.width
      height: Math.round(48 * root.textScale)

      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 5
        anchors.rightMargin: 5
        radius: 9
        color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"

        Rectangle {
          id: dot
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          width: 6
          height: 6
          radius: 3
          color: windowRow.modelData.active ? root.accent : Qt.rgba(1, 1, 1, 0.25)
        }

        Column {
          anchors.left: dot.right
          anchors.leftMargin: 10
          anchors.right: closeButton.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1
          Text {
            width: parent.width
            text: windowRow.modelData.title
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Math.round(13.5 * root.textScale)
            font.weight: Font.Medium
            color: Qt.rgba(1, 1, 1, 0.94)
          }
          Text {
            width: parent.width
            text: windowRow.modelData.location
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Math.round(11.5 * root.textScale)
            color: Qt.rgba(1, 1, 1, 0.45)
          }
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.windowActivated(windowRow.modelData.window)
        }

        Rectangle {
          id: closeButton
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          width: 22
          height: 22
          radius: 6
          color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
          Text {
            anchors.centerIn: parent
            text: "×"
            font.family: root.fontFamily
            font.pixelSize: 15
            color: closeMouse.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.5)
          }
          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.windowClosed(windowRow.modelData.window)
          }
        }
      }
    }
  }
}
