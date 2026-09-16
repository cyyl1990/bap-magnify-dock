with open("DockSettings.qml", "r") as f:
    text = f.read()

bg_op_block = """          ChoiceRow {
            width: parent.width
            label: "Background opacity"
            options: [
              { id: "-1", label: "Auto" },
              { id: "1", label: "100%" },
              { id: "0.8", label: "80%" },
              { id: "0.65", label: "65%" },
              { id: "0.35", label: "35%" },
              { id: "0", label: "0%" }
            ]
            value: root.settings.opacity !== undefined ? String(Number(root.settings.opacity).toString()) : "-1"
            onChosen: function(id) { root.preferenceChanged("opacity", Number(id)) }
          }"""

new_shape_block = bg_op_block + """
          Item { width: 1; height: 8 }
          ChoiceRow {
            width: parent.width
            label: "Dock shape"
            options: [
              { id: "floating", label: "Floating" },
              { id: "attached", label: "Attached" },
              { id: "square", label: "Square" },
              { id: "panel", label: "Panel" }
            ]
            value: root.settings.dockShape || "floating"
            onChosen: function(id) { root.preferenceChanged("dockShape", id) }
          }"""

text = text.replace(bg_op_block, new_shape_block)

with open("DockSettings.qml", "w") as f:
    f.write(text)

