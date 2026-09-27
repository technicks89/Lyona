import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
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
    property string savedSurfaceActive: ""
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

        // Ctrl+W's model call (Sprint 9 S9-03): closes the selected card's window
        // without closing the popup, and does nothing on an empty list.
        model.selectAbsolute(0);
        root.closed = [];
        model.closeSelected();
        root.check(root.closed.length === 1 && root.closed[0] === "0x1", "closeSelected closes the selected window");
        root.check(model.visible, "closeSelected keeps the popup open");
        model.setQuery("zzz");
        root.closed = [];
        model.closeSelected();
        root.check(root.closed.length === 0, "closeSelected on an empty overview does nothing");
        model.setQuery("");

        // The model reports the monitor count the cards need (Sprint 9 S9-03); before
        // it existed the card read an undefined property and never showed its label.
        root.check(model.monitorCount === 1, "one monitor reports 1");
        dwm.monitors = 2;
        root.check(model.monitorCount === 2, "a second monitor is reported: " + model.monitorCount);
        dwm.monitors = 1;

        // Let the card's window show first: a Behavior only runs in a shown window.
        cardStart.start();
    }

    Timer {
        id: cardStart

        interval: 500
        onTriggered: root.cardChecks()
    }

    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children) {
            const found = root.find(child, name);
            if (found) return found;
        }
        return null;
    }

    // One card on its own: accessibility, the monitor label, colour tokens and motion
    // (Sprint 9 S9-02, S9-03).
    function cardChecks() {
        // In the default palette the selected and normal fills are the same colour, so
        // there would be no transition to observe; make them differ for these checks.
        root.savedSurfaceActive = Theme.surfaceActive;
        Theme.surfaceActive = "#aa3333";
        const info = { "windowId": "0x9", "desktop": 2, "appClass": "firefox", "title": "docs", "tagIndex": 2, "monitorIndex": 1 };

        cardOne.window = info;
        cardOne.tagLabel = "web";
        cardOne.monitorCount = 1;
        root.check(cardOne.Accessible.role === Accessible.ListItem, "a card is an accessible list item");
        root.check(cardOne.Accessible.name === "docs", "the accessible name is the window title");
        root.check(cardOne.Accessible.description === "Tag web, firefox",
            "the description names the tag and app: " + cardOne.Accessible.description);
        root.check(!root.find(cardOne, "overviewMonitorLabel").visible, "no monitor label on a single monitor");

        cardOne.monitorCount = 2;
        root.check(cardOne.Accessible.description === "Tag web, firefox, monitor 2",
            "the description names the monitor when there are several: " + cardOne.Accessible.description);
        root.check(root.find(cardOne, "overviewMonitorLabel").visible, "the monitor label shows with two monitors");
        root.check(root.find(cardOne, "overviewMonitorLabel").text === "Mon 2", "the label names the right monitor");

        // A new object: assigning the same reference to a var property notifies nobody.
        cardOne.window = Object.assign({}, info, { "title": "" });
        root.check(cardOne.Accessible.name === "firefox", "a window with no title is named by its class");

        // Selected and hovered states use the Theme roles that were checked for contrast.
        cardOne.selected = false;
        root.check(!root.find(cardOne, "overviewCloseButton").visible, "no close button on an idle card");
        cardOne.selected = true;
        // Positive control: with motion on, the colour is still travelling straight
        // after the change. If this fails the harness is not animating at all.
        root.check(!Qt.colorEqual(cardOne.color, Theme.menuSelectedBackground),
            "with motion on, selecting eases the card colour instead of jumping");
        root.check(root.find(cardOne, "overviewCloseButton").visible, "the selected card shows its close button");
        root.check(root.find(cardOne, "overviewCloseButton").Accessible.role === Accessible.Button,
            "the close button is an accessible button");
        root.check(root.find(cardOne, "overviewCloseButton").Accessible.name === "Close firefox",
            "the close button says what it closes");

        // Reduced motion makes the transition an instant change, not a skipped one.
        root.check(Theme.animationFast === 120, "motion is on by default: " + Theme.animationFast);
        Theme.applyAccessibility(false, true);
        root.check(Theme.animationFast === 0 && Theme.animationNormal === 0, "reduced motion zeroes both durations");
        cardOne.selected = false;
        motionCheck.start();
    }

    Timer {
        id: motionCheck

        interval: 60
        onTriggered: {
            // With no animation the state change has already landed.
            root.check(Qt.colorEqual(cardOne.color, Theme.controlNormalFill),
                "reduced motion: deselecting changed the card colour instantly: " + cardOne.color);
            cardOne.selected = true;
            motionCheckSelected.start();
        }
    }

    Timer {
        id: motionCheckSelected

        interval: 60
        onTriggered: {
            root.check(Qt.colorEqual(cardOne.color, Theme.menuSelectedBackground),
                "reduced motion: selecting changed the card colour instantly: " + cardOne.color);
            Theme.applyAccessibility(false, false);
            root.check(Theme.animationFast === 120, "motion returns when reduced motion is off");
            Theme.surfaceActive = root.savedSurfaceActive;
            root.check(popup.visible, "the overview is open before the close transition");
            model.close();
            root.check(popup.visible, "closing keeps the popup visible for its fade-out");
            root.check(!popup.grabFocus, "closing releases the popup's focus grab");
            popupFading.start();
        }
    }

    Timer {
        id: popupFading

        interval: 60
        onTriggered: {
            const surface = root.find(popup.contentItem, "overviewContent");
            root.check(popup.visible && surface.opacity > 0 && surface.opacity < 1,
                "the popup fades through an intermediate opacity while closing");
            popupClosed.start();
        }
    }

    Timer {
        id: popupClosed

        interval: 400
        onTriggered: {
            root.check(!popup.visible, "the popup hides after its fade-out completes");
            model.open(null);
            popupReopen.start();
        }
    }

    Timer {
        id: popupReopen

        interval: 400
        onTriggered: {
            model.close();
            root.check(popup.visible, "a second close also animates");
            model.open(null);
            popupReopened.start();
        }
    }

    Timer {
        id: popupReopened

        interval: 400
        onTriggered: {
            root.check(model.visible && popup.visible && popup.grabFocus,
                "reopening during a close keeps the popup open and focused");
            Theme.applyAccessibility(false, true);
            model.close();
            root.check(!popup.visible, "reduced motion closes the popup immediately");
            model.open(null);
            root.check(popup.visible, "reduced motion still opens the popup");
            model.close();
            root.check(!popup.visible, "reduced motion closes immediately after reopening too");
            console.info("Overview interaction tests: PASS (" + root.assertions + " assertions)");
            Qt.quit();
        }
    }

    // The card lives in a real window: QML does not run a Behavior for an item that
    // has no window, which would make every motion assertion below vacuous.
    FloatingWindow {
        visible: true
        implicitWidth: 420
        implicitHeight: 120

        ColumnLayout {
            anchors.fill: parent

            OverviewCard {
                id: cardOne

                window: { "windowId": "0x0", "desktop": 0, "appClass": "kitty", "title": "x", "tagIndex": 0, "monitorIndex": 0 }
                selected: false
            }
        }
    }

    QtObject {
        id: dwm

        property var windowStates: []
        property var monitorWorkspaceRows: []
        property var workspaceNames: ["1", "2", "3"]
        property int monitors: 1

        function monitorCount() {
            return dwm.monitors;
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
        id: popup

        overviewModel: model
        panelWindow: panel
    }

    Component.onCompleted: Qt.callLater(root.run)
}
