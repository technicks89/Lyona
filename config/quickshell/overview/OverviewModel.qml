import Quickshell
import "../state/DwmStateWindows.js" as WindowsLib

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

    // Occupied tags only, in ascending tag order, each holding the windows
    // resolved to it. Always live (not gated on visible) so an IPC caller
    // can ask "how many windows" without opening the popup first, and the
    // work itself is cheap -- grouping an already-resolved list, not a
    // Process spawn the way LauncherModel's application index is.
    readonly property var groups: WindowsLib.groupByTag(
        root.dwmState.windows, root.dwmState.monitorWorkspaceRows, root.dwmState.workspaceNames)

    function open(screen) {
        root.targetScreen = screen || null;
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
}
