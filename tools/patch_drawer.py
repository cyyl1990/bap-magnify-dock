import re

with open("DockDrawer.qml", "r") as f:
    text = f.read()

# Make the root `backdrop` completely transparent to just catch clicks.
# Wait, I already have `backdrop` rectangle. Let's just modify the layout inside `backdrop`!
orig_backdrop = """  Rectangle {
    id: backdrop
    anchors.fill: parent
    color: Qt.rgba(root.backdropColor.r, root.backdropColor.g, root.backdropColor.b, root.backdropOpacity)"""

new_backdrop = """  Item {
    id: backdrop
    anchors.fill: parent"""

text = text.replace(orig_backdrop, new_backdrop)

# Now, add a `Rectangle` inside `backdrop` after MouseArea Keys.onEscapePressed
search_box_start = """    // Search
    Rectangle {"""

new_search_box_start = """    Rectangle {
      id: dialogBox
      anchors.centerIn: parent
      width: Math.min(940, parent.width * 0.95)
      height: Math.min(800, parent.height * 0.85)
      radius: 24
      color: Qt.rgba(root.backdropColor.r, root.backdropColor.g, root.backdropColor.b, root.backdropOpacity)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.12)
      
      Rectangle {
        anchors.fill: parent
        radius: 24
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.08) }
          GradientStop { position: 0.06; color: "transparent" }
        }
      }

    // Search
    Rectangle {"""

text = text.replace(search_box_start, new_search_box_start)


# Change searchBox positioning
text = text.replace("""      anchors.top: parent.top
      anchors.topMargin: Math.round(parent.height * 0.07)
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(560, parent.width * 0.8)""", """      anchors.top: parent.top
      anchors.topMargin: 40
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(560, parent.width * 0.8)""")

# Change gridArea positioning
text = text.replace("""      anchors.top: searchBox.bottom
      anchors.topMargin: Math.round(parent.height * 0.05)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 24""", """      anchors.top: searchBox.bottom
      anchors.topMargin: 30
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 30""")

# Change grid items widths (they use original width)
# wait, `parent.width` for gridArea inside dialogBox is mostly fine because dialogBox is parent.width of its parent? 
# Yes, dialogBox width is 940 max.
# gridArea width calculation: 
text = re.sub(r'width: Math.round\(\(62 \+ 28\) \* \(Math.floor\(Math.min\(980, parent.width \* 0.9\) \/ \(62 \+ 28\)\)\)\)',
              r'width: Math.round((62 + 28) * Math.max(1, Math.floor(parent.width * 0.92 / (62 + 28))))', text)

# Close the new dialogBox before dragging tile logic
dragging_start = """    // Ghost of the tile being dragged"""
new_dragging_start = """    } // end dialogBox

    // Ghost of the tile being dragged"""
text = text.replace(dragging_start, new_dragging_start)

with open("DockDrawer.qml", "w") as f:
    f.write(text)

print("Patched.")
