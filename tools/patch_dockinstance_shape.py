import sys

with open("DockInstance.qml", "r") as f:
    lines = f.read().split('\n')

# 1. Insert `readonly property string dockShape` and `readonly property int capsuleRadius`
for i, line in enumerate(lines):
    if "readonly property string tileShape:" in line:
        insert_text = """  readonly property string dockShape: root.preferences.dockShape || "rounded"
  readonly property int capsuleRadius: {
    var h = root.capsuleHeight
    if (root.dockShape === "round" || root.dockShape === "pill") return Math.round(h / 2)
    if (root.dockShape === "square") return 0
    if (root.dockShape === "theme" || root.dockShape === "auto") {
      var n = typeof Style !== "undefined" ? Style.cornerRadius : undefined
      return (typeof n === "number" && isFinite(n) && n >= 0) ? n : 14
    }
    return Math.max(14, Math.min(28, Math.round(h * 0.26)))
  }"""
        lines.insert(i, insert_text)
        break

# 2. Re-evaluate lines after insert
for i in range(len(lines)):
    if "radius: 19" in lines[i] and not ("radius: (root.dockShape" in lines[i]):
        lines[i] = lines[i].replace("radius: 19", "radius: root.capsuleRadius")

with open("DockInstance.qml", "w") as f:
    f.write('\n'.join(lines))
