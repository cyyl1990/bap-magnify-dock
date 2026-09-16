with open("DockInstance.qml", "r") as f:
    text = f.read()

# Revert opacity cap cap for consistency
text = text.replace("backdropOpacity: Math.min(0.55, root.surfaceAlpha)", "backdropOpacity: root.surfaceAlpha")

with open("DockInstance.qml", "w") as f:
    f.write(text)

with open("DockDrawer.qml", "r") as f:
    text = f.read()

import re

# Match dialogBox border.color and edge light
text = re.sub(r'border\.color: Qt\.rgba\(1, 1, 1, 0\.12\)', 'border.color: Qt.rgba(1, 1, 1, 0.13)', text)
text = re.sub(r'GradientStop { position: 0\.0; color: Qt\.rgba\(1, 1, 1, 0\.08\) }', 'GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.14) }', text)
# And make the radius 19 to match perfectly? 
# Wait, dialog box is huge (940x800). radius 24 is better for a huge box than 19. 
# I will keep radius 24 but sync the colors.

with open("DockDrawer.qml", "w") as f:
    f.write(text)

print("Style synced.")
