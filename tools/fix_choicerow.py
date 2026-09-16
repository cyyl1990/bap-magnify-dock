with open("DockSettings.qml", "r") as f:
    text = f.read()

text = text.replace("onChosen: choiceRow.chosen(id)", "onChosen: function(choiceId) { choiceRow.chosen(choiceId) }")
text = text.replace("onChosen: root.autoHideModeChosen(id)", "onChosen: function(choiceId) { root.autoHideModeChosen(choiceId) }")

with open("DockSettings.qml", "w") as f:
    f.write(text)
