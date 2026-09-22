import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

// One window's card in the overview popup (Sync Sprint 7 S7-03): icon,
// title, and a monitor label -- no thumbnail yet (Sprint 9 S9-01 is the
// spike for that). Mirrors RunningAppItem.qml's own icon/click shape, just
// laid out as a row instead of a panel pill.
Rectangle {
    id: root

    required property var window
    signal focusRequested(string windowId)

    Layout.fillWidth: true
    Layout.preferredHeight: Theme.dp(48)
    radius: Theme.controlRadius
    color: cardMouse.containsMouse ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: cardMouse.containsMouse ? Theme.controlHoverBorder : Theme.controlNormalBorder
    border.width: Theme.controlBorderWidth

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
            text: "Mon " + (root.window.monitorIndex + 1)
            color: Theme.menuMutedText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontCaptionSize
            font.bold: true
        }
    }

    MouseArea {
        id: cardMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.focusRequested(root.window.windowId)
    }
}
