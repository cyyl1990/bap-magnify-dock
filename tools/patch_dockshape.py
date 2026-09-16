with open("DockInstance.qml", "r") as f:
    text = f.read()

# Add dockShape property
text = text.replace("property real layoutExpansionRatio: 0.82", "readonly property string dockShape: root.preferences.dockShape || \"floating\"\n  property real layoutExpansionRatio: 0.82")

# Update dockEdgeMargin
text = text.replace("property real dockEdgeMargin: 14", "property real dockEdgeMargin: root.dockShape === \"floating\" ? 14 : (root.dockShape === \"square\" ? 6 : 0)")

# Update capsule radius
text = text.replace("radius: 19\n      transform: Translate {", 'radius: (root.dockShape === "square" || root.dockShape === "panel") ? 0 : 19\n      transform: Translate {')

# Update capsule width
# original: width: contentRow.width + root.dockPadding * 2 + root.animatedExtraCapsuleWidth
import re
text = re.sub(
    r'width: contentRow\.width \+ root\.dockPadding \* 2 \+ root\.animatedExtraCapsuleWidth',
    r'width: root.dockShape === "panel" ? parent.width : (contentRow.width + root.dockPadding * 2 + root.animatedExtraCapsuleWidth)',
    text
)

# Fix shadow so it doesn't draw if panel
text = re.sub(
    r'visible: root\.showBackground',
    r'visible: root.showBackground && root.dockShape !== "panel"',
    text
)
# Wait, `shadowUnderlay` repeater visibility:
# Wait, the repeater delegates have:
# visible: root.showBackground
# let's just leave shadow if square. for panel, maybe no shadow because it spans the screen? Actually, panel can have shadow.

with open("DockInstance.qml", "w") as f:
    f.write(text)

