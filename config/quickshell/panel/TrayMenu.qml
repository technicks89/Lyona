import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import "Tray.js" as Tray

pragma ComponentBehavior: Bound

// A tray item's context menu, drawn by the shell from the item's DBusMenu
// like the other panel popups. QsMenuAnchor's platform menu needs Quickshell
// in QApplication mode, which this shell does not run in, so right-click
// opened nothing. A submenu replaces the list, with Back to return.
ClickAwayPopup {
    id: root

    required property var panelWindow
    property var trayItem: null
    property int anchorX: 0
    // The submenus entered, innermost last; empty shows the item's own menu.
    property var submenus: []
    readonly property var currentMenu: submenus.length > 0
        ? submenus[submenus.length - 1]
        : (trayItem ? trayItem.menu : null)
    // The entry Up and Down have reached (#534), -1 for none; each menu and
    // submenu starts with none, so a pointer user sees no highlight.
    property int keyIndex: -1
    onCurrentMenuChanged: root.keyIndex = -1

    function moveKey(step) {
        root.keyIndex = Tray.nextEntryIndex(opener.children.values, root.keyIndex, step);
    }

    function keyEntry() {
        const entries = opener.children.values;
        return root.keyIndex >= 0 && root.keyIndex < entries.length ? entries[root.keyIndex] : null;
    }

    function openMenu(item, x) {
        root.submenus = [];
        root.trayItem = item;
        root.anchorX = x;
        root.open = true;
    }

    function closeMenu() {
        root.open = false;
        root.submenus = [];
        root.trayItem = null;
    }

    function activate(entry) {
        if (!entry.enabled)
            return;
        if (entry.hasChildren) {
            root.submenus = root.submenus.concat([entry]);
        } else {
            entry.triggered();
            root.closeMenu();
        }
    }

    open: false
    targetWindow: panelWindow
    popupWidth: Theme.controlCenterWidth
    popupHeight: menuCard.implicitHeight
    popupX: anchorX - popupWidth / 2
    popupY: Theme.panelHeight
    onDismissed: root.closeMenu()
    onVisibleChanged: if (visible) Qt.callLater(() => menuCard.forceActiveFocus())

    // Bound to the open menu only, so a closed popup holds no DBusMenu.
    QsMenuOpener {
        id: opener

        menu: root.visible ? root.currentMenu : null
    }

    ShellSurface {
        id: menuCard

        anchors.fill: parent
        implicitHeight: menuColumn.implicitHeight + margin * 2
        margin: 10
        focus: true

        // Up and Down move between the entries, Enter or Space activates
        // one, Right enters a submenu and Left goes back out (#534).
        Keys.onPressed: function(event) {
            const entry = root.keyEntry();
            if (event.key === Qt.Key_Escape) {
                if (root.submenus.length > 0)
                    root.submenus = root.submenus.slice(0, -1);
                else
                    root.closeMenu();
            } else if (event.key === Qt.Key_Down) {
                root.moveKey(1);
            } else if (event.key === Qt.Key_Up) {
                root.moveKey(-1);
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Space) {
                if (entry) root.activate(entry);
            } else if (event.key === Qt.Key_Right) {
                if (entry && entry.hasChildren) root.activate(entry);
            } else if (event.key === Qt.Key_Left) {
                if (root.submenus.length > 0)
                    root.submenus = root.submenus.slice(0, -1);
            } else {
                return;
            }
            event.accepted = true;
        }

        ColumnLayout {
            id: menuColumn

            anchors.fill: parent
            spacing: Theme.listSpacing

            MenuHeader {
                Layout.fillWidth: true
                title: root.submenus.length > 0
                    ? Tray.menuLabel(root.submenus[root.submenus.length - 1].text)
                    : (root.trayItem ? (root.trayItem.tooltipTitle || root.trayItem.title || root.trayItem.id || "") : "")
                showBack: root.submenus.length > 0
                onBackRequested: root.submenus = root.submenus.slice(0, -1)
                onCloseRequested: root.closeMenu()
            }

            PanelSeparator {}

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: opener.children

                    delegate: Item {
                        id: entryRow

                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        visible: !Tray.redundantSeparator(opener.children.values, index)
                        implicitHeight: modelData.isSeparator ? separator.implicitHeight + Theme.listSpacing * 2 : row.implicitHeight

                        PanelSeparator {
                            id: separator

                            visible: entryRow.modelData.isSeparator
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        MenuRow {
                            id: row

                            visible: !entryRow.modelData.isSeparator
                            anchors.left: parent.left
                            anchors.right: parent.right
                            label: Tray.menuLabel(entryRow.modelData.text)
                            detail: Tray.checkDetail(entryRow.modelData.buttonType, entryRow.modelData.checkState)
                            navigates: entryRow.modelData.hasChildren
                            active: root.keyIndex === entryRow.index
                            enabled: entryRow.modelData.enabled
                            opacity: enabled ? 1 : 0.45
                            onActivated: root.activate(entryRow.modelData)
                        }
                    }
                }
            }
        }
    }
}
