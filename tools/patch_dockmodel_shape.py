import sys
import re

with open("DockModel.js", "r") as f:
    text = f.read()

# Add to defaultSettings
text = text.replace('tileShape: "rounded"', 'tileShape: "rounded", dockShape: "rounded"')

# Add to normalizeSettings
insert = """  result.tileShape = ["rounded", "circle", "square"].indexOf(input.tileShape) >= 0 ? input.tileShape : "rounded";
  result.dockShape = ["theme", "rounded", "round", "square"].indexOf(input.dockShape) >= 0 ? input.dockShape : "rounded";"""
text = text.replace('  result.tileShape = ["rounded", "circle", "square"].indexOf(input.tileShape) >= 0 ? input.tileShape : "rounded";', insert)

with open("DockModel.js", "w") as f:
    f.write(text)
