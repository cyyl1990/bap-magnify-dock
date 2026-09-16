with open("DockSettings.qml", "r") as f:
    text = f.read()

import re
old_options = """            options: [
              { id: "floating", label: "Floating" },
              { id: "attached", label: "Attached" },
              { id: "square", label: "Square" },
              { id: "panel", label: "Panel" }
            ]"""

new_options = """            options: [
              { id: "floating", label: "Auto" },
              { id: "attached", label: "Attached" },
              { id: "square", label: "Square" },
              { id: "panel", label: "Panel" }
            ]"""

# Actually, I'll just change the label for floating to "Floating (Theme)". But wait, let me just add an "Auto" option.

new_options = """            options: [
              { id: "floating", label: "Auto (Theme)" },
              { id: "attached", label: "Attached" },
              { id: "square", label: "Square" },
              { id: "panel", label: "Panel" }
            ]"""
text = text.replace(old_options, new_options)

with open("DockSettings.qml", "w") as f:
    f.write(text)

