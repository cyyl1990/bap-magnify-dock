import QtQuick
import QtQuick.Controls
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons

// Window list for an app. With previews on, each window is a card: a large
// square live thumbnail with the title beneath, cards side by side. With
// previews off, a compact text list.
DockGlass {
  id: root

  property string title: ""
  property var rows: []
  property real maxHeight: 420
  property real maxWidth: 1200
  property real textScale: 1
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool previews: true
  readonly property bool containsPointer: hover.hovered

  signal windowActivated(var win)
  signal windowClosed(var win)
  signal dismissed()

  readonly property int cardSize: Math.round(196 * textScale)      // square thumbnail box
  readonly property int cardW: cardSize + 16
  readonly property int cardH: cardSize + Math.round(46 * textScale) + 16
  readonly property int cardGap: 8

  open: visible
  width: previews
    ? Math.min(maxWidth, Math.max(cardW + 10, rows.length * cardW + Math.max(0, rows.length - 1) * cardGap + 10))
    : Math.round(280 * Math.max(1, Math.min(1.3, textScale)))
  height: previews
    ? header.height + cardH + 12
    : Math.min(maxHeight, header.height + textList.contentHeight + 12)

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

  // ---------- cards with previews ----------
  ListView {
    id: cardList
    visible: root.previews
    anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 5; rightMargin: 5; bottomMargin: 7 }
    orientation: ListView.Horizontal
    clip: true
    model: root.previews ? root.rows : []
    spacing: root.cardGap
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.horizontal: ScrollBar { policy: cardList.contentWidth > cardList.width ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

    delegate: Item {
      id: card
      required property var modelData
      width: root.cardW
      height: root.cardH

      Rectangle {
        anchors.fill: parent
        radius: 10
        color: cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
        border.width: card.modelData.active ? 1 : 0
        border.color: root.accent
      }

      ClippingRectangle {
        id: thumbBox
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.cardSize
        height: root.cardSize
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.35)
        ScreencopyView {
          anchors.centerIn: parent
          captureSource: card.modelData.window
          live: root.visible
          paintCursor: false
          constraintSize: Qt.size(root.cardSize, root.cardSize)
        }
      }

      Column {
        anchors.top: thumbBox.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 1
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: card.modelData.title
          elide: Text.ElideRight
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Math.round(13 * root.textScale)
          font.weight: Font.Medium
          color: Qt.rgba(1, 1, 1, 0.94)
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: card.modelData.location
          elide: Text.ElideRight
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Math.round(11 * root.textScale)
          color: Qt.rgba(1, 1, 1, 0.45)
        }
      }

      MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.windowActivated(card.modelData.window)
      }

      Rectangle {
        anchors.top: thumbBox.top
        anchors.right: thumbBox.right
        anchors.margins: 6
        width: 24; height: 24; radius: 7
        visible: cardMouse.containsMouse || closeMouse.containsMouse
        color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.55)
        Text {
          anchors.centerIn: parent
          text: "×"
          font.family: root.fontFamily
          font.pixelSize: 16
          color: "#ffffff"
        }
        MouseArea {
          id: closeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.windowClosed(card.modelData.window)
        }
      }
    }
  }

  // ---------- compact text list ----------
  ListView {
    id: textList
    visible: !root.previews
    anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 7 }
    clip: true
    model: root.previews ? [] : root.rows
    spacing: 0
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: textList.contentHeight > textList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

    delegate: Item {
      id: windowRow
      required property var modelData
      width: textList.width
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
          width: 6; height: 6; radius: 3
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
          width: 22; height: 22; radius: 6
          color: closeRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
          Text {
            anchors.centerIn: parent
            text: "×"
            font.family: root.fontFamily
            font.pixelSize: 15
            color: closeRowMouse.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.5)
          }
          MouseArea {
            id: closeRowMouse
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
