import QtQuick
import qs.core

Rectangle {
    id: root

    property bool active: false
    property bool hovered: false
    property bool outlined: false
    // A pill that does something on a click is on the panel's keyboard path
    // (#534): Tab and the arrow keys reach it, Enter or Space trigger it.
    property bool keyboardActivatable: false

    // Enter or Space while the pill has the keyboard: what a click does.
    signal triggered

    implicitHeight: Theme.pillHeight
    opacity: 1.0
    activeFocusOnTab: keyboardActivatable && visible
    color: active ? Theme.controlSelectedFill
        : activeFocus ? Theme.controlFocusFill
        : hovered ? Theme.controlHoverFill
        : outlined ? Theme.controlNormalFill : Theme.transparent
    // The focus ring wins over the selected look: it is the one thing that
    // shows where the keyboard is.
    border.color: activeFocus ? Theme.controlFocusBorder
        : active ? Theme.controlSelectedBorder
        : hovered ? Theme.controlHoverBorder
        : outlined ? Theme.controlNormalBorder : Theme.transparent
    border.width: activeFocus ? Math.max(Theme.pillBorderWidth, Theme.controlFocusBorderWidth)
        : Theme.pillBorderWidth
    radius: Theme.pillRadius

    Keys.onPressed: function(event) {
        if (!root.keyboardActivatable)
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.triggered();
            event.accepted = true;
        }
    }

    Behavior on color {
        ColorAnimation { duration: Theme.animationNormal }
    }

    Behavior on border.color {
        ColorAnimation { duration: Theme.animationNormal }
    }

    PillShadow { cornerRadius: root.radius }
}
