.pragma library

// Pure type-to-filter matching for the overview popup (Sync Sprint 8 S8-03,
// docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md), the launcher's own matching
// convention (case-insensitive substring, LauncherModel.qml's own
// refreshFilteredApps()) applied to a window's title/class instead of an
// app's name. Filters the raw windows list *before* groupByTag() runs, so
// filtering needs no changes there: a tag with nothing left in it after
// filtering is simply absent from the result, the same "no empty groups"
// behaviour groupByTag() already has for an actually-empty tag.
function filterWindows(windows, query) {
    const needle = query.trim().toLowerCase();

    if (needle.length === 0) {
        return windows;
    }

    return windows.filter(function(win) {
        return win.title.toLowerCase().indexOf(needle) !== -1
            || win.appClass.toLowerCase().indexOf(needle) !== -1;
    });
}

// Closing a card from the overview (Sync Sprint 8 S8-04,
// docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md) removes it immediately rather
// than waiting for the next watch update to notice: DwmState.windowStates
// only refreshes when dwm-quickshell-state's watch stream reports the
// _NET_CLIENT_LIST change, which lags the close request itself. Filtering
// these ids out client-side, the same "filter the raw list before
// groupByTag() runs" shape filterWindows() already uses, gives the
// immediate removal without inventing a second grouping path.
function excludeIds(windows, ids) {
    if (ids.length === 0) {
        return windows;
    }

    return windows.filter(function(win) {
        return ids.indexOf(win.windowId) === -1;
    });
}
