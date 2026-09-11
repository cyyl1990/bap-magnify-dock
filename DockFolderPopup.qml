import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons

// Folder "stack": the most recent entries of a docked folder, newest first.
// Clicking an entry opens it; the header opens the folder itself.
DockGlass {
  id: root

  property string folderPath: ""
  property string title: ""
  property real textScale: 1
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real maxHeight: 420
  property int limit: 14
  readonly property bool containsPointer: hover.hovered

  signal entryActivated(string path)
  signal folderActivated(string path)
  signal dismissed()

  property var entries: []   // [{name, isDir, path}]
  property bool loading: false

  open: visible
  width: Math.round(300 * Math.max(1, Math.min(1.3, textScale)))
  height: Math.min(maxHeight, header.height + Math.max(list.contentHeight, emptyLabel.height) + 12)

  HoverHandler { id: hover }

  function refresh() {
    if (!root.folderPath) return
    root.loading = true
    if (lister.running) { lister.rerun = true; return }
    lister.buffer = []
    // Set the command here rather than binding it: a binding may not have
    // re-evaluated yet when this runs from onFolderPathChanged.
    lister.command = ["find", root.folderPath, "-mindepth", "1", "-maxdepth", "1", "-not", "-name", ".*", "-printf", "%T@\t%y\t%f\n"]
    lister.running = true
  }
  onFolderPathChanged: if (visible) refresh()
  onVisibleChanged: if (visible) refresh()

  Process {
    id: lister
    property var buffer: []
    property bool rerun: false
    // %T@ mtime, %y type, %f name; newest first, hidden entries skipped.
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).split("\t")
        if (parts.length < 3) return
        lister.buffer.push({ t: parseFloat(parts[0]) || 0, isDir: parts[1] === "d", name: parts.slice(2).join("\t") })
      }
    }
    onExited: {
      var rows = lister.buffer.slice().sort(function(a, b) { return b.t - a.t }).slice(0, root.limit)
      root.entries = rows.map(function(r) { return { name: r.name, isDir: r.isDir, path: root.folderPath + "/" + r.name } })
      root.loading = false
      if (lister.rerun) { lister.rerun = false; root.refresh() }
    }
  }

  Item {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Math.round(34 * root.textScale)
    Text {
      anchors.left: parent.left
      anchors.right: openLabel.left
      anchors.leftMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: root.title.toUpperCase()
      font.family: root.fontFamily
      font.pixelSize: Math.round(11 * root.textScale)
      font.weight: Font.DemiBold
      font.letterSpacing: 1.1
      color: Qt.rgba(1, 1, 1, 0.4)
    }
    Text {
      id: openLabel
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      text: "Open folder"
      font.family: root.fontFamily
      font.pixelSize: Math.round(11.5 * root.textScale)
      font.weight: Font.Medium
      color: openMouse.containsMouse ? "#ffffff" : root.accent
      MouseArea {
        id: openMouse
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.folderActivated(root.folderPath)
      }
    }
  }

  Text {
    id: emptyLabel
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    leftPadding: 14
    rightPadding: 14
    bottomPadding: 10
    visible: !root.loading && root.entries.length === 0
    height: visible ? implicitHeight : 0
    text: "Empty folder"
    font.family: root.fontFamily
    font.pixelSize: Math.round(12.5 * root.textScale)
    color: Qt.rgba(1, 1, 1, 0.45)
  }

  ListView {
    id: list
    anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 7 }
    clip: true
    model: root.entries
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
    delegate: Item {
      id: row
      required property var modelData
      width: list.width
      height: Math.round(32 * root.textScale)
      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 5
        anchors.rightMargin: 5
        radius: 8
        color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
        Text {
          id: glyph
          anchors.left: parent.left
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.isDir ? "󰉋" : "󰈔"
          font.family: Style.font.family
          font.pixelSize: Math.round(14 * root.textScale)
          color: row.modelData.isDir ? root.accent : Qt.rgba(1, 1, 1, 0.55)
        }
        Text {
          anchors.left: glyph.right
          anchors.leftMargin: 9
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.name
          elide: Text.ElideMiddle
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Math.round(13 * root.textScale)
          color: Qt.rgba(1, 1, 1, 0.92)
        }
        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.entryActivated(row.modelData.path)
        }
      }
    }
  }
}
