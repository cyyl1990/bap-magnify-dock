import QtQuick
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

  // Tile hue: a stable hash of the app name, so each app gets its own colour
  // and keeps it. (Sampling the icon with ColorQuantizer looked closer to the
  // design but crashes Quickshell when a tile is torn down mid-sample.)
  readonly property real hue: {
    var key = String(root.appName || root.iconSource || "")
    if (!key) return -1
    var h = 2166136261
    for (var i = 0; i < key.length; i++) { h ^= key.charCodeAt(i); h = (h * 16777619) >>> 0 }
    return (h % 360) / 360
  }
  readonly property color tileTop: hue >= 0 ? Qt.hsla(hue, 0.72, 0.61, 1) : "#434c5c"
  readonly property color tileBottom: hue >= 0 ? Qt.hsla(hue, 0.74, 0.45, 1) : "#262b34"

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
      color: Qt.rgba(0, 0, 0, 0.045)
    }
  }

  Rectangle {
    id: tile
    anchors.fill: parent
    radius: Math.round(root.size * root.radiusRatio)
    color: "transparent"

    Image {
      id: icon
      anchors.centerIn: parent
      width: root.size
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
      textFormat: Text.PlainText
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.size * 0.42)
      font.weight: Font.DemiBold
      color: Qt.rgba(1, 1, 1, 0.95)
    }
  }
}
