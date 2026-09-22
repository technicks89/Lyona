#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
overview=$repo/config/quickshell/overview
state=$repo/config/quickshell/state

# Sync Sprint 7 S7-03 (docs/SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md, part of the
# cross-tag window overview, issue #350): structural pins for the popup's own
# files, matching test-quickshell-panel-menus.sh's convention of literal
# `grep -Fq` checks against the other ClickAwayPopup-based windows
# (ControlsWindow, NetworkWindow, PowerMenuWindow) rather than re-rendering
# the popup here. The grouping/resolution logic itself is covered directly by
# tests/qml/tst_dwm_state_windows.qml under qmltestrunner (Sprint 7 S7-02's
# convention, grown one function for groupByTag()).

for component in OverviewModel OverviewCard WindowOverview; do
	test -f "$overview/$component.qml"
done

# ClickAwayPopup-based, the same base ControlsWindow/NetworkWindow/
# PowerMenuWindow use -- inherits the click-away dismiss for free.
grep -Fq 'ClickAwayPopup {' "$overview/WindowOverview.qml"
grep -Fq 'onDismissed: overviewModel.close()' "$overview/WindowOverview.qml"
grep -Fq 'event.key === Qt.Key_Escape' "$overview/WindowOverview.qml"

# Cards grouped by tag via SectionLabel, the launcher's own "Categories"
# component reused, not reinvented.
grep -Fq 'SectionLabel {' "$overview/WindowOverview.qml"
grep -Fq 'model: root.overviewModel.groups' "$overview/WindowOverview.qml"

# Card click calls DwmState.focusWindow(windowId) directly -- the exact
# function RunningAppsArea.qml's own click handler already calls -- and then
# closes the popup; no new dwm-side behaviour.
grep -Fq 'root.overviewModel.dwmState.focusWindow(windowId)' "$overview/WindowOverview.qml"
grep -Fq 'root.overviewModel.close()' "$overview/WindowOverview.qml"
grep -Fq 'signal focusRequested(string windowId)' "$overview/OverviewCard.qml"
grep -Fq 'onFocusRequested: windowId =>' "$overview/WindowOverview.qml"
grep -Fq 'source: Icons.launcherIcon(root.window.appClass)' "$overview/OverviewCard.qml"

# The model is thin glue over DwmStateWindows.js's own groupByTag(): no
# per-window resolution math duplicated here.
grep -Fq 'import "../state/DwmStateWindows.js" as WindowsLib' "$overview/OverviewModel.qml"
grep -Fq 'WindowsLib.groupByTag(' "$overview/OverviewModel.qml"
if grep -Eq 'function (resolveWindowLocation|workspaceIndexesForMonitor)\(' "$overview/OverviewModel.qml"; then
	printf 'OverviewModel.qml must not duplicate DwmStateWindows.js resolution logic.\n' >&2
	exit 1
fi

# shell.qml wiring: model instantiated, popup instantiated bound to the
# active panel window (matching ControlsWindow's own binding), IpcHandler
# with open/close/toggle, and any other panel popup/the command menu/the
# launcher close when the overview becomes the selected popup or opens.
shell=$repo/config/quickshell/shell.qml
grep -Fq 'OverviewModel {' "$shell"
grep -Fq 'dwmState: dwmState' "$shell"
grep -Fq 'WindowOverview {' "$shell"
grep -Fq 'panelWindow: root.activePanelWindow' "$shell"
grep -Fq 'if (popupId !== "overview") overviewModel.close();' "$shell"
grep -Fq 'function openOverview(screen)' "$shell"
grep -Fq 'function toggleOverview(screen)' "$shell"
grep -Fq 'overviewModel.close();' "$shell"
grep -Fq 'target: "overview"' "$shell"

# hotkeys.toml: a real binding, calling the IPC target/action above.
grep -Fq 'call overview toggle' "$repo/config/hotkeys.toml"

if grep -REn 'Quickshell\.(Wayland|Hyprland)|WlrLayershell|hyprctl|uwsm-app|wl-copy|wl-paste' \
	"$overview"; then
	printf 'The overview popup must remain X11-safe.\n' >&2
	exit 1
fi

if grep -REn '(^|[[:space:]])Process[[:space:]]*\{' "$overview"; then
	printf 'The overview popup must not own its own helper process: it only reads DwmState, which already owns the single watch Process.\n' >&2
	exit 1
fi

# groupByTag() itself is a pure function, covered directly (with mutation
# coverage) by tst_dwm_state_windows.qml under qmltestrunner -- confirm it
# actually exists where OverviewModel.qml expects it.
grep -Fq 'function groupByTag(windows, monitorWorkspaceRows, workspaceNames)' "$state/DwmStateWindows.js"

printf 'Quickshell window overview: PASS\n'
