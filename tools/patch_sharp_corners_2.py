with open("DockInstance.qml", "r") as f:
    text = f.read()

import re
old = """      // Square corners for attached to bottom
      Rectangle {
        visible: root.showBackground && root.dockShape === "attached"
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: dockCapsule.radius
        color: Qt.rgba(root.dockColor.r, root.dockColor.g, root.dockColor.b, root.surfaceAlpha)
      }"""

new = """      // Square corners for attached to bottom
      Rectangle {
        visible: root.showBackground && root.dockShape === "attached"
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: dockCapsule.radius
        color: Qt.rgba(root.dockColor.r, root.dockColor.g, root.dockColor.b, root.surfaceAlpha)
        Rectangle { width: 1; height: parent.height; anchors.left: parent.left; visible: root.showBackground; color: Qt.rgba(1, 1, 1, 0.13) }
        Rectangle { width: 1; height: parent.height; anchors.right: parent.right; visible: root.showBackground; color: Qt.rgba(1, 1, 1, 0.13) }
      }"""

text = text.replace(old, new)
with open("DockInstance.qml", "w") as f:
    f.write(text)
