import QtQml
import Quickshell
import Quickshell.Io
import "../state/DwmStateWindows.js" as WindowsLib
import "OverviewFilter.js" as Filter
import "OverviewSelection.js" as Selection

// Presentation-level state for the cross-tag window overview popup (Sync
// Sprint 7 S7-03, docs/SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md, part of the
// cross-tag window overview, issue #350). Deliberately thin: the actual
// per-window tag/monitor resolution and grouping already lives in
// DwmStateWindows.js's own groupByTag() (Sprint 7 S7-02's pure library, grown
// one function for this) -- this model just feeds it live state and tracks
// visibility/which screen it was opened on, the same shape
// LauncherModel/CommandMenuModel already use for a screen-targeted popup.
Scope {
    id: root

    required property var dwmState

    property bool visible: false
    property var targetScreen: null
    property int selectedIndex: 0
    property string query: ""
    // Window ids a card close was requested for. Filtered out immediately
    // (OverviewFilter.excludeIds) rather than waiting for the next watch
    // update; reset whenever the popup opens or closes so a window that
    // refuses to close reappears next time instead of staying hidden.
    property var closingIds: []

    // Occupied tags only, in ascending tag order, each holding the windows
    // resolved to it. Always live (not gated on visible) so an IPC caller
    // can ask "how many windows" without opening the popup first, and the
    // work itself is cheap -- grouping an already-resolved list, not a
    // Process spawn the way LauncherModel's application index is.
    readonly property var visibleWindows: Filter.excludeIds(
        Filter.filterWindows(root.dwmState.windowStates, root.query), root.closingIds)

    // How many monitors there are. Cards label their monitor only when it is more
    // than one, and the accessible description names it then (Sprint 9 S9-03).
    readonly property int monitorCount: root.dwmState.monitorCount()

    readonly property var groups: WindowsLib.groupByTag(root.visibleWindows, root.dwmState.monitorWorkspaceRows,
        root.dwmState.workspaceNames, root.dwmState.monitorCount())

    // Filtering or closing a card can shrink the list under the selection.
    onFlatCardsChanged: root.selectedIndex = Selection.selectAbsolute(root.selectedIndex, root.flatCards.length)

    // A flat, tag-grouped-order card list for keyboard navigation (Sync
    // Sprint 8 S8-01, docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md) -- moving
    // past the last card of one tag's group lands on the first of the next,
    // for free, since this is exactly WindowOverview.qml's own nested-Repeater
    // render order (groupByTag()'s own flatIndex already matches it).
    readonly property var flatCards: {
        const cards = [];

        for (const group of root.groups) {
            for (const win of group.windows) {
                cards.push(win);
            }
        }

        return cards;
    }

    // Window previews (Sync Sprint 9 S9-01, docs/evidence/s9-01-thumbnail-spike.md).
    // dwm-window-thumb captures one window at a time, and only works while a
    // compositor runs, so previews are an extra: `thumbnailsAvailable` is false (and
    // the cards keep their icon and title) whenever it exits non-zero or is not
    // installed. Nothing is captured while the popup is closed, only cards that are on
    // screen are requested (WindowOverview.qml), and the files the helper wrote are
    // deleted when the popup closes because they show windows the user put out of sight.
    property string thumbnailHelper: "dwm-window-thumb"
    property bool thumbnailsAvailable: false
    // Window id -> URL of its preview image. Replaced, not edited, so bindings update.
    property var thumbnails: ({})
    property var thumbnailQueue: []
    property var thumbnailRequested: ({})
    property string thumbnailWindow: ""
    property int thumbnailSerial: 0
    // Bumped whenever the popup opens or closes, so a capture that finishes for an
    // earlier showing is dropped instead of appearing in the next one.
    property int thumbnailGeneration: 0
    property int thumbnailStartedGeneration: 0
    property bool thumbnailsStored: false

    function resetThumbnails() {
        root.thumbnailGeneration++;
        root.thumbnailsAvailable = false;
        root.thumbnails = ({});
        root.thumbnailQueue = [];
        root.thumbnailRequested = ({});
    }

    // Ask for a window's preview. Idempotent: each window is captured at most once
    // per showing, and captures run one after another, never side by side.
    function requestThumbnail(windowId) {
        if (!root.visible || !root.thumbnailsAvailable || root.thumbnailRequested[windowId] === true) {
            return;
        }

        root.thumbnailRequested = Object.assign({}, root.thumbnailRequested, { [windowId]: true });
        root.thumbnailQueue = root.thumbnailQueue.concat([windowId]);
        root.pumpThumbnails();
    }

    function pumpThumbnails() {
        if (!root.visible || !root.thumbnailsAvailable || root.thumbnailQueue.length === 0
                || captureProcess.running || purgeProcess.running) {
            return;
        }

        root.thumbnailWindow = root.thumbnailQueue[0];
        root.thumbnailQueue = root.thumbnailQueue.slice(1);
        root.thumbnailStartedGeneration = root.thumbnailGeneration;
        root.thumbnailsStored = true;
        captureProcess.command = [root.thumbnailHelper, "capture", root.thumbnailWindow];
        captureProcess.running = true;
    }

    function finishCapture(exitCode, output) {
        const path = output.trim();

        if (root.thumbnailStartedGeneration === root.thumbnailGeneration && root.visible) {
            if (exitCode === 0 && path.length > 0) {
                root.thumbnailSerial++;
                root.thumbnails = Object.assign({}, root.thumbnails,
                    { [root.thumbnailWindow]: "file://" + path + "?" + root.thumbnailSerial });
            } else if (exitCode === 3 || exitCode === 4) {
                // The compositor stopped, or previews were switched off, while open.
                root.thumbnailsAvailable = false;
                root.thumbnailQueue = [];
            }
        }

        root.purgeThumbnails();
        root.pumpThumbnails();
    }

    function purgeThumbnails() {
        if (root.visible || !root.thumbnailsStored || captureProcess.running || purgeProcess.running) {
            return;
        }

        root.thumbnailsStored = false;
        purgeProcess.running = true;
    }

    function open(screen) {
        root.targetScreen = screen || null;
        root.selectedIndex = 0;
        root.query = "";
        root.closingIds = [];
        root.resetThumbnails();
        root.visible = true;
        availableProcess.running = true;
    }

    function close() {
        root.visible = false;
        root.query = "";
        root.closingIds = [];
        root.resetThumbnails();
        root.purgeThumbnails();
    }

    Component.onCompleted: {
        // A shell that crashed while the popup was open left its previews behind.
        root.thumbnailsStored = true;
        root.purgeThumbnails();
    }

    Process {
        id: availableProcess

        command: [root.thumbnailHelper, "available"]
        onExited: (exitCode, exitStatus) => {
            root.thumbnailsAvailable = exitCode === 0 && root.visible;
            root.pumpThumbnails();
        }
    }

    Process {
        id: captureProcess

        stdout: StdioCollector {
            id: captureOutput
        }
        onExited: (exitCode, exitStatus) => root.finishCapture(exitCode, captureOutput.text)
    }

    Process {
        id: purgeProcess

        command: [root.thumbnailHelper, "purge"]
        onExited: (exitCode, exitStatus) => root.pumpThumbnails()
    }

    function setQuery(value) {
        root.query = value;
        root.selectedIndex = 0;
    }

    // Close a card's window without closing the popup: hide the card now,
    // then ask DwmState to launch an independent close command for this id.
    function closeCard(windowId) {
        root.closingIds = root.closingIds.concat([windowId]);
        root.dwmState.closeWindow(windowId);
    }

    // Ctrl+W in the popup: the keyboard form of the close button, which only
    // appears on hover (Sprint 9 S9-03). Same guard as activateSelected(): an empty
    // list or a stale index does nothing.
    function closeSelected() {
        const cards = root.flatCards;

        if (cards.length === 0 || root.selectedIndex < 0 || root.selectedIndex >= cards.length) {
            return;
        }

        root.closeCard(cards[root.selectedIndex].windowId);
    }

    function toggle(screen) {
        if (root.visible) {
            root.close();
        } else {
            root.open(screen);
        }
    }

    // selectRelative()/selectAbsolute() mirror LauncherModel's own shape
    // exactly (wrap-around on relative, clamp on absolute), operating on
    // flatCards the same way LauncherModel's own selection operates on its
    // filteredApps -- narrowed by a search filter (Sprint 8 S8-03), not the
    // full list, once that item lands. The actual math is
    // OverviewSelection.js's own pure functions, directly unit-tested, since
    // this model (it imports Quickshell) cannot be instantiated live in
    // plain qmltestrunner the way that pure library can.
    function selectRelative(delta) {
        root.selectedIndex = Selection.selectRelative(root.selectedIndex, delta, root.flatCards.length);
    }

    function selectAbsolute(index) {
        root.selectedIndex = Selection.selectAbsolute(index, root.flatCards.length);
    }

    // Enter activates the selected card the same way a click on it does
    // (WindowOverview.qml's own onFocusRequested handler): focus the window,
    // then close. A stale/out-of-range selectedIndex (an empty overview, or a
    // window that closed out from under the popup -- Sprint 8 S8-02) is a
    // no-op rather than a crash or an action on the wrong window.
    function activateSelected() {
        const cards = root.flatCards;

        if (cards.length === 0 || root.selectedIndex < 0 || root.selectedIndex >= cards.length) {
            return;
        }

        root.dwmState.focusWindow(cards[root.selectedIndex].windowId);
        root.close();
    }
}
