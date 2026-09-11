import QtQuick
import qs.Commons

// Frosted popup surface shared by the context menu, window picker and
// settings. Tokens come from the Magnify Dock design: rgba(24,26,33,0.82)
// glass, 1px white/13% border, 14px radius, top specular highlight, and a
// 160ms pop-in (fade, 6px rise, 0.98 -> 1 scale).
Item {
  id: root

  property bool open: false
  property real radius: 14
  property real glassOpacity: 0.82
  property color glassColor: Qt.rgba(24 / 255, 26 / 255, 33 / 255, 1)
  default property alias content: contentHolder.data

  implicitWidth: contentHolder.implicitWidth
  implicitHeight: contentHolder.implicitHeight

  opacity: 0
  transform: [
    Scale { id: popScale; origin.x: root.width / 2; origin.y: root.height; xScale: 0.98; yScale: 0.98 },
    Translate { id: popRise; y: 6 }
  ]

  onOpenChanged: {
    if (open) popIn.restart()
    else { popIn.stop(); root.opacity = 0; popRise.y = 6; popScale.xScale = 0.98; popScale.yScale = 0.98 }
  }
  Component.onCompleted: if (open) popIn.restart()

  ParallelAnimation {
    id: popIn
    NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
    NumberAnimation { target: popRise; property: "y"; from: 6; to: 0; duration: 160; easing.type: Easing.OutQuad }
    NumberAnimation { target: popScale; property: "xScale"; from: 0.98; to: 1; duration: 160; easing.type: Easing.OutQuad }
    NumberAnimation { target: popScale; property: "yScale"; from: 0.98; to: 1; duration: 160; easing.type: Easing.OutQuad }
  }

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: Qt.rgba(root.glassColor.r, root.glassColor.g, root.glassColor.b, root.glassOpacity)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.13)

    // Inset edge light that follows the rounded shape.
    Rectangle {
      anchors.fill: parent
      radius: root.radius
      gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.09) }
      GradientStop { position: 0.06; color: "transparent" }
      }
    }
  }

  Item {
    id: contentHolder
    anchors.fill: parent
  }
}
