import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs.core
import "Tray.js" as Tray

pragma ComponentBehavior: Bound

RowLayout {
    id: root

    required property var panelWindow
    required property var runningApps

    signal menuOpened

    function closeMenu() {
        trayMenu.closeMenu();
    }

    readonly property var visibleItems: Tray.visibleTrayItems(SystemTray.items.values, root.runningApps)
    visible: visibleItems.length > 0
    spacing: Theme.compactSpacing

    Repeater {
        model: root.visibleItems

        delegate: TrayItem {
            required property var modelData

            trayItem: modelData
            onMenuRequested: item => {
                if (trayMenu.visible && trayMenu.trayItem === item.trayItem) {
                    trayMenu.closeMenu();
                    return;
                }
                trayMenu.openMenu(item.trayItem, item.mapToItem(null, item.width / 2, 0).x);
                root.menuOpened();
            }
        }
    }

    TrayMenu {
        id: trayMenu

        panelWindow: root.panelWindow
    }
}
