with open("DockInstance.qml", "r") as f:
    text = f.read()

sharp_corners = """      // Square corners for attached to bottom
      Rectangle {
        visible: root.showBackground && root.dockShape === "attached"
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: dockCapsule.radius
        color: Qt.rgba(root.dockColor.r, root.dockColor.g, root.dockColor.b, root.surfaceAlpha)
      }

      // Top Specular Highlight"""

text = text.replace("      // Top Specular Highlight", sharp_corners)
with open("DockInstance.qml", "w") as f:
    f.write(text)
