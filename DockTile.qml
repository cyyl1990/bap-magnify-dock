import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons

// One app tile as drawn in the Magnify Dock design: a rounded square (24%
// radius) with a two-stop gradient in the app's dominant hue, an inset top
// highlight, a soft drop shadow, and the app icon centred inside. The hue is
// sampled from the icon itself; icons without a saturated colour get the
// design's neutral slate gradient.
Item {
  id: root

  property string iconSource: ""
  property string appName: ""
  property real size: 38
  property real iconRatio: 0.66
  property string fontFamily: Style.font.family
  property bool hovered: false

  width: size
  height: size

  readonly property real hue: {
    var best = -1, bestScore = 0
    var cols = quantizer.colors || []
    for (var i = 0; i < cols.length; i++) {
      var c = cols[i]
      if (!c) continue
      var s = c.hslSaturation, l = c.hslLightness
      var score = s * (1 - Math.abs(l - 0.5) * 1.6)
      if (score > bestScore) { bestScore = score; best = c.hslHue }
    }
    return bestScore > 0.18 ? best : -1
  }
  readonly property color tileTop: hue >= 0 ? Qt.hsla(hue, 0.72, 0.61, 1) : "#434c5c"
  readonly property color tileBottom: hue >= 0 ? Qt.hsla(hue, 0.74, 0.45, 1) : "#262b34"

  ColorQuantizer {
    id: quantizer
    source: root.iconSource
    depth: 2
    rescaleSize: 32
  }

  // Shadow (design: 0 4px 12px rgba(0,0,0,0.32)) drawn from a hidden copy.
  Rectangle {
    id: shadowSource
    anchors.fill: parent
    radius: Math.round(root.size * 0.24)
    color: "#000000"
    visible: false
  }
  MultiEffect {
    anchors.fill: shadowSource
    anchors.topMargin: 4
    source: shadowSource
    blurEnabled: true
    blur: 0.7
    blurMax: 24
    opacity: 0.32
    autoPaddingEnabled: true
  }

  Rectangle {
    id: tile
    anchors.fill: parent
    radius: Math.round(root.size * 0.24)
    gradient: Gradient {
      GradientStop { position: 0.0; color: root.hovered ? Qt.lighter(root.tileTop, 1.08) : root.tileTop }
      GradientStop { position: 1.0; color: root.hovered ? Qt.lighter(root.tileBottom, 1.08) : root.tileBottom }
    }

    // inset highlights: top light, bottom dark
    Rectangle {
      anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
      anchors.margins: 1
      height: 1
      radius: parent.radius
      color: Qt.rgba(1, 1, 1, 0.32)
    }
    Rectangle {
      anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
      anchors.margins: 1
      height: 1
      radius: parent.radius
      color: Qt.rgba(0, 0, 0, 0.18)
    }

    Image {
      id: icon
      anchors.centerIn: parent
      width: Math.round(root.size * root.iconRatio)
      height: width
      fillMode: Image.PreserveAspectFit
      source: root.iconSource
      sourceSize.width: Math.round(width * 2 * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * 2 * Screen.devicePixelRatio)
      asynchronous: true
      smooth: true
      mipmap: true
    }

    Text {
      visible: icon.status !== Image.Ready
      anchors.centerIn: parent
      text: root.appName.length > 0 ? root.appName.charAt(0).toUpperCase() : "★"
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.size * 0.42)
      font.weight: Font.DemiBold
      color: Qt.rgba(1, 1, 1, 0.95)
    }
  }
}
