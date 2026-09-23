import Quickshell
import "../state/DwmStateWindows.js" as WindowsLib
import "OverviewSelection.js" as Selection
import "OverviewFilter.js" as Filter

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
    // Cards closed from this popup, hidden immediately rather than waiting
    // for the next watch update (Sync Sprint 8 S8-04) -- reset each time the
    // popup opens, since a stale entry here is only ever waste, never wrong
    // (an id already gone from windowStates has nothing left to hide).
    property var closingWindowIds: []

    // Occupied tags only, in ascending tag order, each holding the windows
    // resolved to it. Always live (not gated on visible) so an IPC caller
    // can ask "how many windows" without opening the popup first, and the
    // work itself is cheap -- grouping an already-resolved list, not a
    // Process spawn the way LauncherModel's application index is. Filtered
    // by query first (Sync Sprint 8 S8-03) -- a tag with nothing left after
    // filtering is simply absent, groupByTag()'s existing "no empty groups"
    // behaviour, not a separate case to handle here -- and with any card
    // closed from this popup (Sprint 8 S8-04) excluded the same way, so a
    // close feels immediate rather than waiting for windowStates itself to
    // catch up.
    readonly property var groups: WindowsLib.groupByTag(
        Filter.filterWindows(Filter.excludeIds(root.dwmState.windowStates, root.closingWindowIds), root.query),
        root.dwmState.monitorWorkspaceRows, root.dwmState.workspaceNames, root.dwmState.monitorCount())

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

    // A window can close while the popup is open (Sync Sprint 8 S8-02,
    // docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md): DwmState.windowStates is
    // driven by the same live watch stream as everything else, so groups and
    // flatCards already re-derive themselves and the stale card simply stops
    // being rendered -- no new IPC, and activateSelected()'s own bounds
    // check already refuses to act on a since-vanished selectedIndex.
    // Re-clamping it here too keeps some card highlighted rather than none,
    // the moment the list that made it out of range changes, not only the
    // next time a selection function happens to run.
    onFlatCardsChanged: {
        if (root.selectedIndex >= root.flatCards.length) {
            root.selectedIndex = Math.max(0, root.flatCards.length - 1);
        }
    }

    function open(screen) {
        root.targetScreen = screen || null;
        root.selectedIndex = 0;
        root.query = "";
        root.closingWindowIds = [];
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

    // Type-to-filter (Sync Sprint 8 S8-03): groups/flatCards already depend
    // on root.query as a live binding, so setting it is the whole job --
    // matching LauncherModel.setQuery()'s own selectedIndex reset, so a
    // filter that changes the list does not leave the highlight on
    // whatever card now happens to occupy the old index.
    function setQuery(text) {
        root.query = text;
        root.selectedIndex = 0;
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

        if (!Selection.isValidIndex(root.selectedIndex, cards.length)) {
            return;
        }

        root.dwmState.focusWindow(cards[root.selectedIndex].windowId);
        root.close();
    }

    // Closing a card (Sync Sprint 8 S8-04) hides it here immediately (see
    // closingWindowIds/groups above) and sends the real close request; the
    // popup itself stays open, on whatever tag/window it already had
    // focused, matching the design doc's own "does not otherwise change
    // tag/focus" requirement -- unlike activateSelected(), this never closes
    // the popup itself.
    function closeCard(windowId) {
        root.closingWindowIds = root.closingWindowIds.concat([windowId]);
        root.dwmState.closeWindow(windowId);
    }
}
