import QtQuick
import qs.Commons

// Inline colour picker: saturation/value square, hue strip, and a hex field
// kept in sync. Emits `picked(hex)` with a #rrggbb string as the user drags.
Column {
  id: root

  property color value: "#12141a"
  property string fontFamily: Style.font.family
  property real textScale: 1
  property bool allowEmpty: false        // "" means: follow the theme
  property string emptyHint: "#RRGGBB"

  signal picked(string hex)

  width: parent ? parent.width : 300
  spacing: 8

  // HSV working copy, so dragging does not fight with the incoming binding.
  property real hue: 0
  property real sat: 0
  property real val: 0
  property bool dragging: false

  function hexOf(h, s, v) {
    var c = Qt.hsva(h, s, v, 1)
    function two(x) { var n = Math.round(x * 255).toString(16); return n.length < 2 ? "0" + n : n }
    return "#" + two(c.r) + two(c.g) + two(c.b)
  }
  function syncFromValue() {
    if (root.dragging) return
    var c = root.value
    root.hue = c.hsvHue < 0 ? 0 : c.hsvHue
    root.sat = c.hsvSaturation
    root.val = c.hsvValue
  }
  onValueChanged: syncFromValue()
  Component.onCompleted: syncFromValue()
  function emit() { root.picked(hexOf(root.hue, root.sat, root.val)) }

  function w(a) { return Qt.rgba(1, 1, 1, a) }

  // Saturation / value square
  Rectangle {
    id: square
    width: parent.width
    height: Math.round(120 * Math.max(1, root.textScale))
    radius: 8
    clip: true
    color: Qt.hsva(root.hue, 1, 1, 1)

    Rectangle {  // white -> transparent, left to right
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "#ffffff" }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }
    Rectangle {  // transparent -> black, top to bottom
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 1.0; color: "#000000" }
      }
    }
    Rectangle { anchors.fill: parent; radius: 8; color: "transparent"; border.width: 1; border.color: root.w(0.15) }

    Rectangle {  // cursor
      x: root.sat * (square.width - 1) - width / 2
      y: (1 - root.val) * (square.height - 1) - height / 2
      width: 14; height: 14; radius: 7
      color: "transparent"
      border.width: 2
      border.color: "#ffffff"
      Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 5; color: "transparent"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.5) }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.CrossCursor
      function apply(mx, my) {
        root.sat = Math.max(0, Math.min(1, mx / (square.width - 1)))
        root.val = 1 - Math.max(0, Math.min(1, my / (square.height - 1)))
        root.emit()
      }
      onPressed: function(m) { root.dragging = true; apply(m.x, m.y) }
      onPositionChanged: function(m) { if (pressed) apply(m.x, m.y) }
      onReleased: root.dragging = false
      onCanceled: root.dragging = false
    }
  }

  // Hue strip
  Rectangle {
    id: strip
    width: parent.width
    height: 16
    radius: 8
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.000; color: "#ff0000" }
      GradientStop { position: 0.167; color: "#ffff00" }
      GradientStop { position: 0.333; color: "#00ff00" }
      GradientStop { position: 0.500; color: "#00ffff" }
      GradientStop { position: 0.667; color: "#0000ff" }
      GradientStop { position: 0.833; color: "#ff00ff" }
      GradientStop { position: 1.000; color: "#ff0000" }
    }
    Rectangle {  // cursor
      x: root.hue * (strip.width - 1) - width / 2
      y: -2
      width: 8; height: 20; radius: 4
      color: "#ffffff"
      border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.45)
    }
    MouseArea {
      anchors.fill: parent
      anchors.margins: -4
      function apply(mx) { root.hue = Math.max(0, Math.min(1, (mx - 4) / (strip.width - 1))); root.emit() }
      onPressed: function(m) { root.dragging = true; apply(m.x) }
      onPositionChanged: function(m) { if (pressed) apply(m.x) }
      onReleased: root.dragging = false
      onCanceled: root.dragging = false
    }
  }

  // Preview + hex field
  Row {
    width: parent.width
    spacing: 8
    Rectangle {
      width: Math.round(30 * root.textScale); height: width
      radius: 8
      color: root.value
      border.width: 1; border.color: root.w(0.25)
    }
    Rectangle {
      width: parent.width - Math.round(30 * root.textScale) - 8
      height: Math.round(30 * root.textScale)
      radius: 8
      color: root.w(0.08)
      border.width: 1
      border.color: hexInput.activeFocus ? root.w(0.35) : root.w(0.12)
      TextInput {
        id: hexInput
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        font.family: root.fontFamily
        font.pixelSize: Math.round(12.5 * root.textScale)
        color: "#ffffff"
        selectionColor: root.w(0.25)
        maximumLength: 7
        text: root.hexOf(root.hue, root.sat, root.val)
        onActiveFocusChanged: if (!activeFocus) text = root.hexOf(root.hue, root.sat, root.val)
        onAccepted: {
          var v = text.trim()
          if (/^#[0-9a-fA-F]{6}$/.test(v)) root.picked(v.toLowerCase())
          else if (root.allowEmpty && v === "") root.picked("")
          else text = root.hexOf(root.hue, root.sat, root.val)
        }
        Text {
          visible: hexInput.text.length === 0 && !hexInput.activeFocus
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          text: root.emptyHint
          font: hexInput.font
          color: root.w(0.35)
        }
      }
    }
  }
}
