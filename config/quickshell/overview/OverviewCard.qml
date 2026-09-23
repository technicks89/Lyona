import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

// One window's card in the overview popup (Sync Sprint 7 S7-03): icon,
// title, and a monitor label -- no thumbnail yet (Sprint 9 S9-01 is the
// spike for that). Mirrors RunningAppItem.qml's own icon/click shape, just
// laid out as a row instead of a panel pill. `selected` (Sync Sprint 8
// S8-01) is the keyboard-navigated card, styled the same way
// LauncherResultDelegate.qml's own `selected` state already is -- a
// distinct fill/border from mouse hover, since the two can disagree (arrow
// keys move `selected` without the mouse moving at all).
Rectangle {
    id: root

    required property var window
    required property bool selected
    signal focusRequested(string windowId)
    signal closeRequested(string windowId)

    Layout.fillWidth: true
    Layout.preferredHeight: Theme.dp(48)
    radius: Theme.controlRadius
    color: root.selected ? Theme.menuSelectedBackground
        : cardMouse.containsMouse ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: root.selected ? Theme.controlSelectedBorder
        : cardMouse.containsMouse ? Theme.controlHoverBorder : Theme.controlNormalBorder
    border.width: Theme.controlBorderWidth

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
            text: root.window.title.length > 0 ? root.window.title : root.window.appClass
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.panelFontSize
            elide: Text.ElideRight
        }

        Text {
            visible: root.monitorCount > 1
            text: "Mon " + (root.window.monitorIndex + 1)
            color: Theme.menuMutedText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontCaptionSize
            font.bold: true
        }

        Rectangle {
            id: closeButton

            visible: cardMouse.containsMouse || closeMouse.containsMouse
            Layout.preferredWidth: Theme.dp(24)
            Layout.preferredHeight: Theme.dp(24)
            radius: Theme.controlRadius
            color: closeMouse.containsMouse ? Theme.danger : Theme.transparent
            border.color: closeButton.activeFocus ? Theme.controlFocusBorder : Theme.transparent
            border.width: Theme.controlBorderWidth
            activeFocusOnTab: root.selected
            Accessible.role: Accessible.Button
            Accessible.name: "Close " + (root.window.title.length > 0 ? root.window.title : root.window.appClass)
            Accessible.onPressAction: root.closeRequested(root.window.windowId)

            Text {
                anchors.centerIn: parent
                text: "×"
                color: closeMouse.containsMouse ? Theme.textStrong : Theme.menuMutedText
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

            Keys.onPressed: function(event) {
                if (!event.isAutoRepeat
                        && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
                    root.closeRequested(root.window.windowId);
                    event.accepted = true;
                }
            }
        }
    }

}
