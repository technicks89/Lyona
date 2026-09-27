import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

// One window's card in the overview popup (Sync Sprint 7 S7-03): icon,
// title, and a monitor label -- no thumbnail (the Sprint 9 S9-01 spike found one
// only works with Picom running; docs/evidence/s9-01-thumbnail-spike.md). Mirrors RunningAppItem.qml's own icon/click shape, just laid out as a
// row instead of a panel pill. `selected` (Sync Sprint 8 S8-01) is the
// keyboard-navigated card, styled the same way LauncherResultDelegate.qml's own
// `selected` state already is -- a distinct fill/border from mouse hover, since
// the two can disagree (arrow keys move `selected` without the mouse moving).
//
// Sprint 9: every colour is a Theme token (text roles included, so light
// palettes stay readable), state changes ease with Theme.animationFast (0 under
// reduced motion, an instant change rather than a skipped one), and the card is
// an accessible list item that a screen reader can tell apart from another
// window of the same app.
Rectangle {
    id: root

    required property var window
    required property bool selected
    // How many monitors there are (the label only matters above one), and the tag
    // this card is grouped under, for the accessible description.
    property int monitorCount: 1
    property string tagLabel: ""
    readonly property string windowLabel: root.window.title.length > 0 ? root.window.title : root.window.appClass
    readonly property bool hovered: cardMouse.containsMouse || closeMouse.containsMouse
    signal focusRequested(string windowId)
    signal closeRequested(string windowId)

    Layout.fillWidth: true
    Layout.preferredHeight: Theme.dp(48)
    radius: Theme.controlRadius
    color: root.selected ? Theme.menuSelectedBackground
        : root.hovered ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: root.selected ? Theme.controlSelectedBorder
        : root.hovered ? Theme.controlHoverBorder : Theme.controlNormalBorder
    border.width: Theme.controlBorderWidth

    Behavior on color { ColorAnimation { duration: Theme.animationFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animationFast } }

    Accessible.role: Accessible.ListItem
    Accessible.name: root.windowLabel
    Accessible.description: "Tag " + root.tagLabel + ", " + root.window.appClass
        + (root.monitorCount > 1 ? ", monitor " + (root.window.monitorIndex + 1) : "")
    Accessible.selectable: true
    Accessible.selected: root.selected
    Accessible.onPressAction: root.focusRequested(root.window.windowId)

    MouseArea {
        id: cardMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.focusRequested(root.window.windowId)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.rowSpacing
        anchors.rightMargin: Theme.rowSpacing
        spacing: Theme.rowSpacing

        IconImage {
            Layout.preferredWidth: Theme.trayIconSize
            Layout.preferredHeight: Theme.trayIconSize
            source: Icons.launcherIcon(root.window.appClass)
        }

        Text {
            Layout.fillWidth: true
            text: root.windowLabel
            color: root.selected ? Theme.menuSelectedText
                : root.hovered ? Theme.controlHoverText : Theme.controlNormalText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.panelFontSize
            elide: Text.ElideRight
        }

        Text {
            objectName: "overviewMonitorLabel"
            visible: root.monitorCount > 1
            text: "Mon " + (root.window.monitorIndex + 1)
            color: Theme.menuMutedText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontCaptionSize
            font.bold: true
        }

        // Shown on hover and on the keyboard-selected card, so the selected card's
        // Ctrl+W (WindowOverview.qml) has a visible counterpart. Ignored by
        // keyboard focus on purpose: the shortcut is the keyboard path.
        Rectangle {
            id: closeButton

            objectName: "overviewCloseButton"
            visible: root.hovered || root.selected
            Layout.preferredWidth: Theme.dp(24)
            Layout.preferredHeight: Theme.dp(24)
            radius: Theme.controlRadius
            color: closeMouse.containsMouse ? Theme.danger : Theme.transparent
            Behavior on color { ColorAnimation { duration: Theme.animationFast } }
            Accessible.role: Accessible.Button
            Accessible.name: "Close " + root.windowLabel
            Accessible.onPressAction: root.closeRequested(root.window.windowId)

            Text {
                anchors.centerIn: parent
                text: "×"
                color: closeMouse.containsMouse ? Theme.readableText(Theme.textStrong, Theme.danger) : Theme.menuMutedText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodySize
                font.bold: true
            }

            MouseArea {
                id: closeMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested(root.window.windowId)
            }
        }
    }
}
