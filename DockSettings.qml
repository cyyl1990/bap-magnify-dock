import QtQuick
import QtQuick.Controls
import qs.Commons
import "DockModel.js" as DockModel

// Settings card, per the design: 340px glass, "Dock Settings" header with a
// close control, Appearance sliders, a segmented "Windows shown" control,
// Behavior switches, and a footer noting where settings are saved.
DockGlass {
  id: root

  property var settings: ({})
  property bool isAutoHide: false
  property bool isReserveSpace: true
  property real maxHeight: 620
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  readonly property real textScale: settings && settings.textScale ? settings.textScale : 1
  readonly property var colorPresets: DockModel.colorPresets
  readonly property var accentPresets: DockModel.accentPresets

  signal preferenceChanged(string key, var value)
  signal autoHideToggled()
  signal reserveSpaceToggled()
  signal dismissed()

  open: visible
  width: Math.round(340 * Math.max(1, Math.min(1.25, textScale)))
  height: Math.min(maxHeight, flick.contentHeight)

  function w(a) { return Qt.rgba(1, 1, 1, a) }

  Flickable {
    id: flick
    anchors.fill: parent
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

    Column {
      id: column
      width: flick.width
      spacing: 0

      // Header
      Item {
        width: parent.width
        height: 44
        Text {
          anchors.left: parent.left
          anchors.leftMargin: 18
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: 4
          text: "Dock Settings"
          font.family: root.fontFamily
          font.pixelSize: Math.round(15 * root.textScale)
          font.weight: Font.DemiBold
          color: "#ffffff"
        }
        Rectangle {
          anchors.right: parent.right
          anchors.rightMargin: 18
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: 4
          width: 24
          height: 24
          radius: 8
          color: closeMouse.containsMouse ? root.w(0.12) : "transparent"
          Text {
            anchors.centerIn: parent
            text: "×"
            font.family: root.fontFamily
            font.pixelSize: Math.round(16 * root.textScale)
            color: closeMouse.containsMouse ? "#ffffff" : root.w(0.55)
          }
          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dismissed()
          }
        }
      }

      // Appearance
      Column {
        width: parent.width
        leftPadding: 18
        rightPadding: 18
        topPadding: 8
        spacing: 0

        Text {
          text: "APPEARANCE"
          font.family: root.fontFamily
          font.pixelSize: Math.round(10 * root.textScale)
          font.weight: Font.DemiBold
          font.letterSpacing: 1.3
          color: root.w(0.38)
          topPadding: 8
          bottomPadding: 2
        }

        Repeater {
          model: [
            { key: "iconSize", label: "Icon size", min: 24, max: 64, step: 1, fmt: "px" },
            { key: "magnification", label: "Magnification", min: 1, max: 2, step: 0.05, fmt: "x" },
            { key: "spacing", label: "Spacing", min: 2, max: 16, step: 1, fmt: "px" },
            { key: "opacity", label: "Background opacity", min: 0.2, max: 1, step: 0.02, fmt: "%" },
            { key: "textScale", label: "Text size", min: 0.8, max: 1.6, step: 0.05, fmt: "%" }
          ]
          delegate: Column {
            id: settingRow
            required property var modelData
            width: column.width - 36
            topPadding: 9
            bottomPadding: 2
            spacing: 7

            function display(v) {
              var f = settingRow.modelData.fmt
              if (f === "%") return Math.round(v * 100) + "%"
              if (f === "x") return "×" + Number(v).toFixed(2)
              return Math.round(v) + " px"
            }

            Item {
              width: parent.width
              height: 14
              Text {
                anchors.left: parent.left
                anchors.baseline: parent.bottom
                text: settingRow.modelData.label
                font.family: root.fontFamily
                font.pixelSize: Math.round(13 * root.textScale)
                font.weight: Font.Medium
                color: root.w(0.85)
              }
              Text {
                anchors.right: parent.right
                anchors.baseline: parent.bottom
                text: settingRow.display(control.value)
                font.family: root.fontFamily
                font.pixelSize: Math.round(12 * root.textScale)
                font.weight: Font.Medium
                color: root.w(0.5)
              }
            }

            Slider {
              id: control
              objectName: settingRow.modelData.key
              width: parent.width
              height: 20
              from: settingRow.modelData.min
              to: settingRow.modelData.max
              stepSize: settingRow.modelData.step
              value: root.settings[settingRow.modelData.key]
              Accessible.name: settingRow.modelData.label
              onMoved: root.preferenceChanged(settingRow.modelData.key, value)

              background: Rectangle {
                x: control.leftPadding
                y: control.topPadding + control.availableHeight / 2 - height / 2
                width: control.availableWidth
                height: 4
                radius: 2
                color: root.w(0.16)
                Rectangle {
                  width: control.visualPosition * parent.width
                  height: parent.height
                  radius: 2
                  color: root.w(0.45)
                }
              }
              handle: Rectangle {
                x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
                y: control.topPadding + control.availableHeight / 2 - height / 2
                width: 15
                height: 15
                radius: 7.5
                color: "#ffffff"
                border.width: 0
              }
            }
          }
        }


        // Colors
        Text {
          text: "COLORS"
          font.family: root.fontFamily
          font.pixelSize: Math.round(10.5 * root.textScale)
          font.weight: Font.DemiBold
          font.letterSpacing: 1.3
          color: root.w(0.38)
          topPadding: 18
          bottomPadding: 6
        }
        Repeater {
          model: [
            { key: "dockColor", label: "Dock", presets: root.colorPresets, allowTheme: false },
            { key: "drawerColor", label: "Drawer", presets: root.colorPresets, allowTheme: false },
            { key: "accentColor", label: "Accent", presets: root.accentPresets, allowTheme: true }
          ]
          delegate: Column {
            id: colorRow
            required property var modelData
            readonly property string current: String(root.settings[modelData.key] || "")
            width: column.width - 36
            topPadding: 6
            bottomPadding: 4
            spacing: 7

            Text {
              text: colorRow.modelData.label
              font.family: root.fontFamily
              font.pixelSize: Math.round(13 * root.textScale)
              font.weight: Font.Medium
              color: root.w(0.85)
            }

            Row {
              spacing: 8
              // "Theme" swatch for the accent: follow the Omarchy theme.
              Rectangle {
                visible: colorRow.modelData.allowTheme
                width: 26; height: 26; radius: 13
                color: root.accent
                border.width: colorRow.current === "" ? 2 : 1
                border.color: colorRow.current === "" ? "#ffffff" : root.w(0.25)
                Text {
                  anchors.centerIn: parent
                  text: "T"
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(11 * root.textScale)
                  font.weight: Font.DemiBold
                  color: "#ffffff"
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.preferenceChanged(colorRow.modelData.key, "") }
              }
              Repeater {
                model: colorRow.modelData.presets
                delegate: Rectangle {
                  id: swatch
                  required property string modelData
                  readonly property bool selected: colorRow.current === modelData.toLowerCase()
                  width: 26; height: 26; radius: 13
                  color: modelData
                  border.width: selected ? 2 : 1
                  border.color: selected ? "#ffffff" : root.w(0.25)
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.preferenceChanged(colorRow.modelData.key, swatch.modelData) }
                }
              }
            }

            DockColorPicker {
              width: parent.width
              fontFamily: root.fontFamily
              textScale: root.textScale
              allowEmpty: colorRow.modelData.allowTheme
              emptyHint: colorRow.modelData.allowTheme ? "theme accent, or #RRGGBB" : "#RRGGBB"
              value: colorRow.current !== "" ? colorRow.current : (colorRow.modelData.allowTheme ? root.accent : "#000000")
              onPicked: function(hex) { root.preferenceChanged(colorRow.modelData.key, hex) }
            }
          }
        }

        // Windows shown
        Text {
          text: "WINDOWS SHOWN"
          font.family: root.fontFamily
          font.pixelSize: Math.round(10 * root.textScale)
          font.weight: Font.DemiBold
          font.letterSpacing: 1.3
          color: root.w(0.38)
          topPadding: 18
          bottomPadding: 10
        }
        Rectangle {
          width: column.width - 36
          height: 34
          radius: 9
          color: root.w(0.08)
          Row {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 0
            Repeater {
              model: [
                { id: "all", label: "All" },
                { id: "monitor", label: "This monitor" },
                { id: "workspace", label: "Workspace" }
              ]
              delegate: Rectangle {
                id: seg
                required property var modelData
                readonly property bool selected: root.settings.windowScope === modelData.id
                width: (parent.width) / 3
                height: parent.height
                radius: 7
                color: selected ? root.w(0.16) : (segMouse.containsMouse ? root.w(0.06) : "transparent")
                Text {
                  anchors.centerIn: parent
                  text: seg.modelData.label
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(12 * root.textScale)
                  font.weight: Font.Medium
                  color: seg.selected ? "#ffffff" : root.w(0.55)
                }
                MouseArea {
                  id: segMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.preferenceChanged("windowScope", seg.modelData.id)
                }
              }
            }
          }
        }

        // Behavior
        Text {
          text: "BEHAVIOR"
          font.family: root.fontFamily
          font.pixelSize: Math.round(10 * root.textScale)
          font.weight: Font.DemiBold
          font.letterSpacing: 1.3
          color: root.w(0.38)
          topPadding: 18
          bottomPadding: 4
        }
        Repeater {
          model: [
            { key: "autoHide", label: "Auto-hide", sub: "Slide off-screen; reveal at the bottom edge" },
            { key: "reserveSpace", label: "Reserve space", sub: "Tiled windows stop above the dock" },
            { key: "windowPreviews", label: "Window previews", sub: "Live thumbnails in the window list on hover" }
          ]
          delegate: Item {
            id: toggleRow
            required property var modelData
            readonly property bool on: modelData.key === "autoHide" ? root.isAutoHide
              : modelData.key === "reserveSpace" ? root.isReserveSpace
              : root.settings.windowPreviews !== false
            width: column.width - 36
            height: 50

            Column {
              anchors.left: parent.left
              anchors.right: track.left
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2
              Text {
                text: toggleRow.modelData.label
                font.family: root.fontFamily
                font.pixelSize: Math.round(13 * root.textScale)
                font.weight: Font.Medium
                color: root.w(0.85)
              }
              Text {
                width: parent.width
                text: toggleRow.modelData.sub
                wrapMode: Text.WordWrap
                font.family: root.fontFamily
                font.pixelSize: Math.round(12 * root.textScale)
                color: root.w(0.42)
              }
            }

            Rectangle {
              id: track
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: 40
              height: 24
              radius: 12
              color: toggleRow.on ? root.accent : root.w(0.16)
              Behavior on color { ColorAnimation { duration: 180 } }
              Rectangle {
                x: toggleRow.on ? 19 : 3
                y: 3
                width: 18
                height: 18
                radius: 9
                color: "#ffffff"
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (toggleRow.modelData.key === "autoHide") root.autoHideToggled()
                else if (toggleRow.modelData.key === "reserveSpace") root.reserveSpaceToggled()
                else root.preferenceChanged("windowPreviews", !toggleRow.on)
              }
            }
          }
        }
        Item { width: 1; height: 6 }
      }

      // Footer
      Rectangle {
        width: parent.width
        height: 1
        color: root.w(0.08)
      }
      Text {
        width: parent.width
        leftPadding: 18
        rightPadding: 18
        topPadding: 10
        bottomPadding: 14
        wrapMode: Text.WordWrap
        text: "Changes apply live and save to dock-pinned-macos.json"
        font.family: root.fontFamily
        font.pixelSize: Math.round(11 * root.textScale)
        color: root.w(0.35)
      }
    }
  }
}
