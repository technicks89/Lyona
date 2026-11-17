import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

Rectangle {
    id: root

    required property var trayItem
    property var iconSources: Icons.trayIconSources(root.trayItem)
    property int iconSourceIndex: 0

    // TrayArea draws the menu: one popup for the whole tray.
    signal menuRequested(var item)

    function openContextMenu() {
        if (root.trayItem && root.trayItem.hasMenu) {
            root.menuRequested(root);
        }
    }

    function handleClick(button) {
        if (button === Qt.LeftButton) {
            if (!root.trayItem.onlyMenu) {
                root.trayItem.activate();
            } else if (root.trayItem.hasMenu) {
                root.openContextMenu();
            }
        } else if (button === Qt.MiddleButton) {
            root.trayItem.secondaryActivate();
        }
    }

    onIconSourcesChanged: {
        iconSourceIndex = 0;
    }

    Layout.preferredWidth: Theme.trayItemSize
    Layout.preferredHeight: Theme.trayItemSize
    radius: Theme.smallRadius
    // On the panel's keyboard path (#534): Enter or Space is a left click,
    // the Menu key or Shift+F10 a right click.
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.trayItem.tooltipTitle || root.trayItem.title || root.trayItem.id || "Tray item"
    Accessible.onPressAction: root.handleClick(Qt.LeftButton)
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.handleClick(Qt.LeftButton);
            event.accepted = true;
        } else if (event.key === Qt.Key_Menu
                || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            root.openContextMenu();
            event.accepted = true;
        }
    }
    color: activeFocus ? Theme.controlFocusFill
        : trayMouse.containsMouse ? Theme.controlHoverFill : Theme.transparent
    border.color: activeFocus ? Theme.controlFocusBorder
        : trayMouse.containsMouse ? Theme.controlHoverBorder : Theme.transparent
    border.width: activeFocus ? Math.max(Theme.pillBorderWidth, Theme.controlFocusBorderWidth)
        : trayMouse.containsMouse ? Theme.pillBorderWidth : 0

    IconImage {
        id: trayIcon

        anchors.centerIn: parent
        width: Theme.trayIconSize
        height: Theme.trayIconSize
        source: root.iconSources.length > root.iconSourceIndex ? root.iconSources[root.iconSourceIndex] : ""
        implicitSize: Theme.trayIconSize
        asynchronous: true
        mipmap: true
        visible: status === Image.Ready

        onStatusChanged: {
            if (status === Image.Error && root.iconSourceIndex < root.iconSources.length - 1) {
                root.iconSourceIndex += 1;
            }
        }
    }

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: !trayIcon.visible
        text: {
            const title = root.trayItem.tooltipTitle || root.trayItem.title || root.trayItem.id || "?";
            return title.length > 0 ? title.charAt(0).toUpperCase() : "?";
        }
        color: root.activeFocus ? Theme.controlFocusText
            : trayMouse.containsMouse ? Theme.controlHoverText : Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tinyFontSize
        font.bold: true
    }

    MouseArea {
        id: trayMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.openContextMenu();
                mouse.accepted = true;
            }
        }

        onClicked: mouse => {
            if (mouse.button !== Qt.RightButton) {
                root.handleClick(mouse.button);
            }
        }
    }
}
