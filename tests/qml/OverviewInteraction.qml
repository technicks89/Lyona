import QtQuick
import Quickshell
import qs.overview

// Runtime harness for the cross-tag window overview (Sync Sprint 10 S10-04,
// the interaction cases docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md required
// and that only ever existed as source greps). It loads the real
// OverviewModel, the real OverviewFilter/OverviewSelection/DwmStateWindows
// libraries and the real WindowOverview popup against a stub dwmState, so a
// member the popup reads but the model never defines (query, setQuery,
// closeCard once shipped that way) fails here instead of on a desktop.
// Event delivery (real key presses, mouse clicks) is not simulated; the model
// calls those handlers make are exercised directly.
ShellRoot {
    id: root

    property int assertions: 0
    property var focused: []
    property var closed: []

    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("Overview interaction FAILED: " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }

    function ids(cards) {
        return cards.map(function(card) { return card.windowId; }).join(",");
    }

    function run() {
        const all = [
            { "windowId": "0x1", "desktop": 0, "appClass": "kitty", "title": "build log" },
            { "windowId": "0x2", "desktop": 0, "appClass": "firefox", "title": "docs" },
            { "windowId": "0x3", "desktop": 1, "appClass": "kitty", "title": "ssh prod" }
        ];

        dwm.windowStates = all;
        model.open(null);

        root.check(model.visible, "open() shows the popup");
        root.check(model.groups.length === 2, "two occupied tags give two groups");
        root.check(root.ids(model.flatCards) === "0x1,0x2,0x3", "cards in tag order: " + root.ids(model.flatCards));

        // Type-to-filter (S8-03).
        model.setQuery("kitty");
        root.check(root.ids(model.flatCards) === "0x1,0x3", "filter by class: " + root.ids(model.flatCards));
        model.setQuery("PROD");
        root.check(root.ids(model.flatCards) === "0x3", "filter is case-insensitive and matches titles");
        root.check(model.groups.length === 1, "a tag with nothing left is absent, not empty");
        model.setQuery("zzz");
        root.check(model.groups.length === 0 && model.flatCards.length === 0, "no match gives no groups");
        model.activateSelected();
        root.check(root.focused.length === 0 && model.visible, "activating an empty overview does nothing");
        model.setQuery("");
        root.check(root.ids(model.flatCards) === "0x1,0x2,0x3", "clearing the query restores every card");

        // Keyboard selection still works over the filtered list (S8-01 + S8-03).
        model.setQuery("kitty");
        model.selectRelative(1);
        root.check(model.selectedIndex === 1, "selection moves within the filtered list");
        model.selectRelative(1);
        root.check(model.selectedIndex === 0, "selection wraps within the filtered list");
        model.setQuery("");

        // Close from a card (S8-04): hidden at once, close requested, popup stays open.
        model.selectAbsolute(2);
        model.closeCard("0x3");
        root.check(root.closed.length === 1 && root.closed[0] === "0x3", "closeCard asks dwm to close the window");
        root.check(root.ids(model.flatCards) === "0x1,0x2", "the closed card disappears immediately");
        root.check(model.selectedIndex === 1, "selection clamps back into range: " + model.selectedIndex);
        root.check(model.visible, "closing a card keeps the popup open");

        // A window vanishing while the popup is open (S8-02).
        dwm.windowStates = [all[1]];
        root.check(root.ids(model.flatCards) === "0x2", "a window that vanished drops its card");
        root.check(model.selectedIndex === 0, "selection clamps after the list shrinks");
        model.activateSelected();
        root.check(root.focused.length === 1 && root.focused[0] === "0x2", "Enter acts on the surviving window, not a stale id");
        root.check(!model.visible, "activating a card closes the popup");

        // Reopening starts clean: no stale filter, no stale pending closes.
        model.setQuery("firefox");
        model.closeCard("0x2");
        model.close();
        root.check(model.query === "", "close() clears the query");
        dwm.windowStates = all;
        model.open(null);
        root.check(root.ids(model.flatCards) === "0x1,0x2,0x3", "reopening shows every window again");

        // Every monitor-labelled card reports its monitor; single monitor: no labels needed.
        root.check(model.flatCards[0].monitorIndex === 0, "cards carry a resolved monitor index");

        console.info("Overview interaction tests: PASS (" + root.assertions + " assertions)");
        Qt.quit();
    }

    QtObject {
        id: dwm

        property var windowStates: []
        property var monitorWorkspaceRows: []
        property var workspaceNames: ["1", "2", "3"]

        function monitorCount() {
            return 1;
        }

        function focusWindow(windowId) {
            root.focused = root.focused.concat([windowId]);
        }

        function closeWindow(windowId) {
            root.closed = root.closed.concat([windowId]);
        }
    }

    OverviewModel {
        id: model

        dwmState: dwm
    }

    PanelWindow {
        id: panel

        implicitWidth: 900
        implicitHeight: 32
        screen: Quickshell.screens[0]
        anchors.top: true
        anchors.left: true
        anchors.right: true
    }

    // The real popup, bound to the same model. Loading it is what surfaces a
    // member it reads that the model does not define.
    WindowOverview {
        overviewModel: model
        panelWindow: panel
    }

    Component.onCompleted: Qt.callLater(root.run)
}
