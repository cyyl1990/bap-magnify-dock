import sys

with open("DockSettings.qml", "r") as f:
    lines = f.read().split('\n')

for i, line in enumerate(lines):
    if "label: \"Background opacity\"" in line:
        # We need to find the end of this ChoiceRow.
        # It ends at `onChosen: ...`
        for j in range(i, len(lines)):
            if "onChosen:" in lines[j] and "root.preferenceChanged(\"opacity\"" in lines[j]:
                end_index = j + 2  # The closing bracket of ChoiceRow
                break
        
        insert_text = """          Item { width: 1; height: 8 }
          ChoiceRow {
            width: parent.width
            label: "Dock shape"
            options: [
              { id: "theme", label: "Auto (Theme)" },
              { id: "rounded", label: "Rounded" },
              { id: "round", label: "Round" },
              { id: "square", label: "Square" }
            ]
            value: root.settings.dockShape || "rounded"
            onChosen: (id) => { root.preferenceChanged("dockShape", id) }
          }"""
        
        lines.insert(end_index, insert_text)
        break

with open("DockSettings.qml", "w") as f:
    f.write('\n'.join(lines))
