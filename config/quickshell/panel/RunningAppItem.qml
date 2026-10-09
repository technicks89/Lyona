import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

Rectangle {
    id: root

    required property var app
    required property bool active
    signal focusRequested(string windowId)

    Layout.preferredWidth: Theme.pillHeight
    Layout.preferredHeight: Theme.pillHeight
    radius: Theme.pillRadius
    color: active ? Theme.controlSelectedFill
        : appMouse.containsMouse ? Theme.controlHoverFill : Theme.transparent
    border.color: active ? Theme.controlSelectedBorder
        : appMouse.containsMouse ? Theme.controlHoverBorder : Theme.transparent
    border.width: active || appMouse.containsMouse ? Theme.pillBorderWidth : 0

    IconImage {
        id: appIcon
        anchors.centerIn: parent
        width: Theme.trayIconSize
        height: Theme.trayIconSize
        source: Icons.launcherIcon(root.app.appClass)
        visible: source.toString().length > 0
    }

    // No themed icon for this class: its initial, not an empty button (#280 VM).
    UiText {
        anchors.centerIn: parent
        visible: !appIcon.visible
        text: Icons.initialFor(root.app.appClass)
        color: Theme.text
        font.bold: true
    }

    MouseArea {
        id: appMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.focusRequested(root.app.windowId)
    }
}
