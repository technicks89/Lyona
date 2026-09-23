.pragma library

// Pure keyboard-navigation math for the overview popup's flat, tag-grouped
// card list (Sync Sprint 8 S8-01, docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md).
// OverviewModel.qml is a QML component (it imports Quickshell), so it cannot
// be instantiated directly in plain qmltestrunner the way DwmStateWindows.js
// already is -- these two functions exist specifically so the actual
// selection math still gets real, mutation-checkable unit coverage rather
// than only a "the function exists" structural pin.

// Mirrors LauncherModel.qml's own selectRelative() exactly: wraps around
// both ends of the list. An empty list has nothing to select; the index
// resets to 0 rather than staying stale.
function selectRelative(selectedIndex, delta, cardCount) {
    if (cardCount === 0) {
        return 0;
    }

    return (selectedIndex + delta + cardCount) % cardCount;
}

// Mirrors LauncherModel.qml's own selectAbsolute(): clamps rather than
// wrapping, the shape Home/End need (jump to an end, not past it).
function selectAbsolute(index, cardCount) {
    if (cardCount === 0) {
        return 0;
    }

    return Math.max(0, Math.min(index, cardCount - 1));
}

// OverviewModel.qml's own activateSelected() guard (Sync Sprint 8 S8-02): a
// window can close while the popup is open, and DwmState.windowStates'
// shrinking is the only signal of that -- selectedIndex itself is not
// touched until a selection function runs, so it can be transiently
// out-of-range. Enter (or any future activation path) must refuse to act on
// that rather than focusing whatever windowId now happens to sit at a
// reused array index.
function isValidIndex(index, cardCount) {
    return cardCount > 0 && index >= 0 && index < cardCount;
}
