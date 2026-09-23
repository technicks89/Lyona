import Quickshell
import "../state/DwmStateWindows.js" as WindowsLib
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

    // Occupied tags only, in ascending tag order, each holding the windows
    // resolved to it. Always live (not gated on visible) so an IPC caller
    // can ask "how many windows" without opening the popup first, and the
    // work itself is cheap -- grouping an already-resolved list, not a
    // Process spawn the way LauncherModel's application index is.
    readonly property var groups: WindowsLib.groupByTag(root.dwmState.windowStates, root.dwmState.monitorWorkspaceRows,
        root.dwmState.workspaceNames, root.dwmState.monitorCount())

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

    function open(screen) {
        root.targetScreen = screen || null;
        root.selectedIndex = 0;
        root.visible = true;
    }

    function close() {
        root.visible = false;
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
