import QtQuick
import qs.Commons

// Flat theme-aware progress track. `value` is 0..1. The fill animates so
// bumping a page count reads as motion rather than a jump.
Rectangle {
  id: root

  property real value: 0
  property color foreground: Color.foreground
  property color accent: Color.accent
  property real thickness: Style.space(6)
  property bool muted: false

  implicitHeight: thickness
  height: thickness
  radius: Math.min(height / 2, Style.cornerRadius > 0 ? Style.cornerRadius : height / 2)
  color: Util.alpha(foreground, 0.12)

  Rectangle {
    id: fill
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(root.value > 0 ? root.height : 0, root.width * Math.max(0, Math.min(1, root.value)))
    radius: root.radius
    color: root.muted ? Util.alpha(root.foreground, 0.35) : root.foreground
    opacity: root.muted ? 1.0 : 0.9

    Behavior on width {
      NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
  }
}
