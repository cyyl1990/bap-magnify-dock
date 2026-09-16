with open("DockSettings.qml", "r") as f:
    text = f.read()

import re

# Insert the shape selector after the opacity ChoiceRow
pattern = r'(onChosen: function\(id\) { root\.preferenceChanged\("opacity", parseFloat\(id\)\) }\n          })'
replacement = r'''\1
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
          }'''

text = re.sub(pattern, replacement, text)

with open("DockSettings.qml", "w") as f:
    f.write(text)

