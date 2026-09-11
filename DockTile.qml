import QtQuick
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
  property string shape: "rounded"      // rounded | circle | square
  readonly property real radiusRatio: shape === "circle" ? 0.5 : (shape === "square" ? 0.12 : 0.24)
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

  // Sample only real files; image:// provider URLs cannot be read by the
  // quantizer and each failed attempt costs a warning and a load.
  readonly property bool sampleable: root.iconSource.indexOf("file://") === 0 || root.iconSource.indexOf("/") === 0
  ColorQuantizer {
    id: quantizer
    source: root.sampleable ? root.iconSource : ""
    depth: 2
    rescaleSize: 32
  }

  // Soft drop shadow (design: 0 4px 12px rgba(0,0,0,0.32)) built from a few
  // stacked translucent rectangles. MultiEffect would look closer but it
  // segfaults inside Qt when tiles are instantiated at shell startup.
  Repeater {
    model: 4
    delegate: Rectangle {
      required property int index
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 2 + index * 1.5
      width: root.size + index * 3
      height: root.size + index * 3
      radius: Math.round((root.size + index * 3) * root.radiusRatio)
      color: Qt.rgba(0, 0, 0, 0.09)
    }
  }

  Rectangle {
    id: tile
    anchors.fill: parent
    radius: Math.round(root.size * root.radiusRatio)
    gradient: Gradient {
      GradientStop { position: 0.0; color: root.hovered ? Qt.lighter(root.tileTop, 1.08) : root.tileTop }
      GradientStop { position: 1.0; color: root.hovered ? Qt.lighter(root.tileBottom, 1.08) : root.tileBottom }
    }

    // Inset edge light that follows the rounded shape.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.32) }
      GradientStop { position: 0.06; color: "transparent" }
      GradientStop { position: 0.94; color: "transparent" }
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.18) }
      }
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

    // Fallback initial. Driven by opacity rather than `visible`: the icon
    // loads asynchronously, and if the tile is torn down while a load is in
    // flight (closing the drawer), Qt crashes updating `visible` on an item
    // whose window is already gone. Opacity takes a different path.
    Text {
      opacity: icon.status === Image.Ready ? 0 : 1
      anchors.centerIn: parent
      text: root.appName.length > 0 ? root.appName.charAt(0).toUpperCase() : "★"
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.size * 0.42)
      font.weight: Font.DemiBold
      color: Qt.rgba(1, 1, 1, 0.95)
    }
  }
}
