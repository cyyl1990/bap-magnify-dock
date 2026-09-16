with open("DockSettings.qml", "r") as f:
    text = f.read()

import re

# Fix ChoiceRow internals
text = text.replace("onChosen: choiceRow.chosen(id)", "onChosen: (id) => choiceRow.chosen(id)")

# Fix all usages
text = re.sub(r'onChosen: function\(id\) \{ ([^\}]+) \}', r'onChosen: (id) => { \1 }', text)
text = text.replace("onChosen: root.autoHideModeChosen(id)", "onChosen: (id) => root.autoHideModeChosen(id)")

with open("DockSettings.qml", "w") as f:
    f.write(text)
