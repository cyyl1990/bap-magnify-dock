import sys

with open("DockInstance.qml", "r") as f:
    text = f.read()

text = text.replace(
    'var n = typeof Style !== "undefined" ? Style.cornerRadius : undefined',
    'var n = Style.cornerRadius'
)

with open("DockInstance.qml", "w") as f:
    f.write(text)
