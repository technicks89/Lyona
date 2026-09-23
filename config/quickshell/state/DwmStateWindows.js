.pragma library

// Pure parsing/resolution helpers for the windows= field DwmState.qml's watch
// stream carries as of Sync Sprint 7 S7-01
// (docs/SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md). Split out of DwmState.qml the
// same way Sprint 6 S6-01 split PanelTooltipPosition.js out of
// PanelTooltip.qml: plain functions with no QML/Process dependency, so they
// are directly testable via qmltestrunner without instantiating a live
// "dwm-quickshell-state watch" Process, matching tst_display_layout.qml's and
// tst_system_information_protocol.qml's own precedent for testing a
// pure-logic library this way.

// A WM_CLASS is percent-encoded by dwm-quickshell-state's own
// sanitize_class() before it reaches windows=/apps=/class= ("%" -> %25,
// ":" -> %3A, "|" -> %7C, so a class value can never collide with this wire
// format's own field/record separators) and must be decoded back here, the
// same way Icons.qml's own decodeIconPart() already unwraps a percent-encoded
// icon name. A class with no encoded sequences (the common case) round-trips
// through decodeURIComponent() unchanged.
function decodeClass(value) {
    try {
        return decodeURIComponent(value);
    } catch (error) {
        return value;
    }
}

// windows=<id>:<desktop>:<class>:<title>|... (dwm-quickshell-state's own
// shape, S7-01). A title may itself contain ":" (a clock, a path), so
// everything after the third colon is rejoined rather than taken as a single
// field; "|" and control characters were already stripped from the title by
// dwm-quickshell-state's own sanitize_title() before it reached this line.
// class is decoded (never stripped) since it is percent-encoded, not
// space-replaced, so it always has exactly one colon-delimited field.
function parseWindows(value) {
    if (!value || value.length === 0) {
        return [];
    }

    return value.split("|").map(function(entry) {
        const fields = entry.split(":");

        return {
            "windowId": fields[0],
            "desktop": parseInt(fields[1], 10),
            "appClass": decodeClass(fields[2]),
            "title": fields.slice(3).join(":")
        };
    });
}

// Mirrors DwmState.qml's own workspaceIndexes(screen) range math -- the same
// number of workspaces split evenly across monitors, with the last monitor
// taking the remainder -- but keyed by a plain monitor index and an explicit
// screen/workspace count instead of a live Quickshell screen object, so it
// runs the same way with no display attached.
function workspaceIndexesForMonitor(monitorIndex, screenCount, workspaceCount) {
    const indexes = [];

    if (workspaceCount <= 0 || screenCount <= 0) {
        return indexes;
    }

    const logicalIndex = Math.min(Math.max(0, monitorIndex), screenCount - 1);
    const workspacesPerScreen = Math.max(1, Math.floor(workspaceCount / screenCount));
    let start = logicalIndex * workspacesPerScreen;
    let end = logicalIndex === screenCount - 1 ? workspaceCount : start + workspacesPerScreen;

    if (start >= workspaceCount) {
        start = workspaceCount - 1;
    }
    end = Math.min(end, workspaceCount);

    for (let index = start; index < end; index++) {
        indexes.push(index);
    }

    return indexes;
}

// A window's raw desktop number is already a global tag index -- the same
// number DwmPanel.qml's own workspaceIndexes(screen) model iterates and hands
// straight to DwmState.switchWorkspace() -- so resolving it only needs to
// find which monitor's range contains it. When rows are empty, use the
// caller's Quickshell screen count instead. A desktop that matches no range
// (a stale window mid monitor-layout change) falls back to tag 0 / monitor 0,
// the same defensive pattern DwmState.qml's screenForMonitorIndex() uses.
function resolveWindowLocation(desktop, monitorWorkspaceRows, workspaceCount, fallbackScreenCount) {
    const screenCount = Math.max(1, monitorWorkspaceRows.length > 0
        ? monitorWorkspaceRows.length : (fallbackScreenCount || 0));

    for (let monitorIndex = 0; monitorIndex < screenCount; monitorIndex++) {
        if (workspaceIndexesForMonitor(monitorIndex, screenCount, workspaceCount).indexOf(desktop) !== -1) {
            return { "tagIndex": desktop, "monitorIndex": monitorIndex };
        }
    }

    return { "tagIndex": 0, "monitorIndex": 0 };
}

// Decorates each parsed window entry with its resolved {tagIndex,
// monitorIndex}, ready for the overview popup (Sprint 7 S7-03) to group by
// tag without repeating this math.
function windowsByTag(windows, monitorWorkspaceRows, workspaceCount, fallbackScreenCount) {
    return windows.map(function(win) {
        const location = resolveWindowLocation(win.desktop, monitorWorkspaceRows, workspaceCount, fallbackScreenCount);

        return {
            "windowId": win.windowId,
            "desktop": win.desktop,
            "appClass": win.appClass,
            "title": win.title,
            "tagIndex": location.tagIndex,
            "monitorIndex": location.monitorIndex
        };
    });
}

// Groups a parsed windows list by resolved tag, in ascending tag order, for
// the overview popup (Sprint 7 S7-03, OverviewModel.qml) to render one
// SectionLabel per occupied tag -- an empty tag is simply absent, never an
// empty group, since there is nothing to show a heading for. OverviewModel.qml
// calls this directly; without it defined, its own `groups` property throws
// every time it evaluates, which is constantly (a real bug found and fixed
// alongside this file's other issues -- see CHANGELOG). Each window is also
// decorated with a `flatIndex`, a sequential 0-based index across the whole
// groups list in the exact order WindowOverview.qml's nested Repeaters render
// it (group by group, ascending tag, windows within a group in their
// existing order) -- Sprint 8 S8-01's keyboard navigation selects by this
// index rather than duplicating the traversal order in two places.
function groupByTag(windows, monitorWorkspaceRows, workspaceNames, fallbackScreenCount) {
    const resolved = windowsByTag(windows, monitorWorkspaceRows, workspaceNames.length, fallbackScreenCount);
    const byTag = {};
    const order = [];

    for (const win of resolved) {
        if (!(win.tagIndex in byTag)) {
            byTag[win.tagIndex] = [];
            order.push(win.tagIndex);
        }
        byTag[win.tagIndex].push(win);
    }

    order.sort(function(a, b) { return a - b; });

    let flatIndex = 0;

    return order.map(function(tagIndex) {
        const windowsInTag = byTag[tagIndex].map(function(win) {
            return Object.assign({}, win, { "flatIndex": flatIndex++ });
        });

        return {
            "tagIndex": tagIndex,
            "tagLabel": tagIndex < workspaceNames.length ? workspaceNames[tagIndex] : String(tagIndex + 1),
            "windows": windowsInTag
        };
    });
}
