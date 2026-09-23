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
for library in OverviewSelection OverviewFilter; do
	test -f "$overview/$library.js"
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
# per-window resolution math duplicated here. And it must read the property
# DwmState.qml actually exposes -- a property rename (windows -> windowStates)
# that OverviewModel.qml's own call site missed once made `groups` throw
# "undefined" on every evaluation, which no other check here would catch:
# nothing instantiates OverviewModel.qml live (it needs the real Quickshell
# plugin, unavailable to plain qmltestrunner), so a stale reference like this
# only surfaced at runtime, on the real desktop.
grep -Fq 'import "../state/DwmStateWindows.js" as WindowsLib' "$overview/OverviewModel.qml"
grep -Fq 'readonly property var groups: WindowsLib.groupByTag(' "$overview/OverviewModel.qml"
if grep -Eq 'function (resolveWindowLocation|workspaceIndexesForMonitor)\(' "$overview/OverviewModel.qml"; then
	printf 'OverviewModel.qml must not duplicate DwmStateWindows.js resolution logic.\n' >&2
	exit 1
fi
if grep -Fq 'root.dwmState.windows,' "$overview/OverviewModel.qml" ||
	grep -Fq 'root.dwmState.windows)' "$overview/OverviewModel.qml"; then
	printf 'OverviewModel.qml references dwmState.windows -- the property is windowStates.\n' >&2
	exit 1
fi

# DwmState.qml itself must agree with its own property name everywhere: its
# storage, its own parser, and windowsByTag() (the other real caller of the
# same rename this file above guards on OverviewModel.qml's side).
grep -Fq 'property var windowStates: []' "$state/DwmState.qml"
grep -Fq 'root.windowStates = WindowsLib.parseWindows(value)' "$state/DwmState.qml"
grep -Fq 'WindowsLib.windowsByTag(root.windowStates,' "$state/DwmState.qml"

# A WM_CLASS is percent-encoded onto the wire (":" -> %3A, "|" -> %7C, "%" ->
# %25, so it can never collide with this format's own separators, unlike a
# title's own lossy space-replacement) and must be decoded back everywhere it
# is read, the same safe try/catch pattern Icons.qml's decodeIconPart() uses.
grep -Fq 'function decodeClass(value)' "$state/DwmStateWindows.js"
grep -Fq '"appClass": decodeClass(fields[2])' "$state/DwmStateWindows.js"
grep -Fq 'WindowsLib.decodeClass(app.slice(separator + 1))' "$state/DwmState.qml"
grep -Fq 'WindowsLib.decodeClass(value) : "application-x-executable"' "$state/DwmState.qml"

# dwm-quickshell-state's own sanitize_class() must be defined in the exact
# awk invocation that calls it: an awk function defined in one `awk '...'`
# script is not visible in another, unlike a shell function, so a call site
# added to client_snapshot() without also adding the function there is a
# fatal awk parse error the moment any client window exists -- checked
# against client_snapshot()'s own block, not the whole file, since
# window_class() also defines and calls its own copy correctly.
helper=$repo/scripts/dwm-quickshell-state
client_snapshot_awk=$(awk '/^client_snapshot\(\)/,/^}/' "$helper")
printf '%s\n' "$client_snapshot_awk" | grep -Fq 'function sanitize_class(value)' ||
	fail_reason='client_snapshot() calls sanitize_class() without defining it'
printf '%s\n' "$client_snapshot_awk" | grep -Fq 'class = sanitize_class(tolower(classes[2]))' ||
	fail_reason="${fail_reason:+$fail_reason; }client_snapshot() does not call sanitize_class() at its WM_CLASS site"
if [ -n "${fail_reason:-}" ]; then
	printf '%s\n' "$fail_reason" >&2
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
# actually exists where OverviewModel.qml expects it, with the signature that
# call site actually uses (grown a fallbackScreenCount 4th argument, matching
# windowsByTag()'s own).
grep -Fq 'function groupByTag(windows, monitorWorkspaceRows, workspaceNames, fallbackScreenCount)' "$state/DwmStateWindows.js"

# Keyboard navigation (Sync Sprint 8 S8-01, docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md):
# the exact Keys.onPressed shape LauncherWindow.qml already has (arrows,
# Home/End, Enter), driving OverviewModel's own selection state rather than
# inventing separate keyboard-handling logic in the view.
grep -Fq 'root.overviewModel.selectRelative(1)' "$overview/WindowOverview.qml"
grep -Fq 'root.overviewModel.selectRelative(-1)' "$overview/WindowOverview.qml"
grep -Fq 'root.overviewModel.selectAbsolute(0)' "$overview/WindowOverview.qml"
grep -Fq 'root.overviewModel.selectAbsolute(root.overviewModel.flatCards.length - 1)' "$overview/WindowOverview.qml"
grep -Fq 'root.overviewModel.activateSelected()' "$overview/WindowOverview.qml"
grep -Fq 'function selectRelative(delta)' "$overview/OverviewModel.qml"
grep -Fq 'function selectAbsolute(index)' "$overview/OverviewModel.qml"
grep -Fq 'function activateSelected()' "$overview/OverviewModel.qml"
grep -Fq 'readonly property var flatCards:' "$overview/OverviewModel.qml"
grep -Fq 'property int selectedIndex: 0' "$overview/OverviewModel.qml"

# The wrap-around/clamp math itself lives in a pure library, directly
# unit-tested (tests/qml/tst_overview_selection.qml) since OverviewModel.qml
# cannot be instantiated live in plain qmltestrunner -- not duplicated inline.
grep -Fq 'import "OverviewSelection.js" as Selection' "$overview/OverviewModel.qml"
grep -Fq 'Selection.selectRelative(root.selectedIndex, delta, root.flatCards.length)' "$overview/OverviewModel.qml"
grep -Fq 'Selection.selectAbsolute(index, root.flatCards.length)' "$overview/OverviewModel.qml"
grep -Fq 'function selectRelative(selectedIndex, delta, cardCount)' "$overview/OverviewSelection.js"
grep -Fq 'function selectAbsolute(index, cardCount)' "$overview/OverviewSelection.js"

# The selected card gets a visible focus ring, the same styling
# LauncherResultDelegate.qml's own `selected` state already uses -- not
# reinvented per component.
grep -Fq 'required property bool selected' "$overview/OverviewCard.qml"
grep -Fq 'Theme.menuSelectedBackground' "$overview/OverviewCard.qml"
grep -Fq 'Theme.controlSelectedBorder' "$overview/OverviewCard.qml"
grep -Fq 'selected: cardDelegate.modelData.flatIndex === root.overviewModel.selectedIndex' "$overview/WindowOverview.qml"

# flatIndex is groupByTag()'s own render-order index, not re-derived in the
# view or the model -- confirm the one real place it is assigned still
# exists.
grep -Fq '"flatIndex": flatIndex++' "$state/DwmStateWindows.js"

# Sync Sprint 8 S8-02: the monitor label is shown only when there is more
# than one monitor -- a single-monitor system should not see a redundant
# "Monitor 1" on every card.
grep -Fq 'required property int monitorCount' "$overview/OverviewCard.qml"
grep -Fq 'visible: root.monitorCount > 1' "$overview/OverviewCard.qml"
grep -Fq 'monitorCount: root.overviewModel.dwmState.monitorCount()' "$overview/WindowOverview.qml"

# S8-02: a window closing while the popup is open must not error or act on
# a stale id. activateSelected()'s own guard is isValidIndex() -- the same
# pure, unit-tested function selectRelative()/selectAbsolute() below it live
# next to -- not a re-derived bounds check; and selectedIndex re-clamps
# itself the moment flatCards changes, not only the next time a selection
# function happens to run.
grep -Fq 'Selection.isValidIndex(root.selectedIndex, cards.length)' "$overview/OverviewModel.qml"
grep -Fq 'onFlatCardsChanged:' "$overview/OverviewModel.qml"
grep -Fq 'function isValidIndex(index, cardCount)' "$overview/OverviewSelection.js"

# Type-to-filter (Sync Sprint 8 S8-03, docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md):
# the exact search-box shape LauncherWindow.qml already has (a TextInput
# always focused while the popup is open, no separate hotkey needed since
# ClickAwayPopup already grabs keyboard focus), filtering by title/class
# case-insensitive substring via a pure library, the same split
# OverviewSelection.js already established.
grep -Fq 'function filterWindows(windows, query)' "$overview/OverviewFilter.js"
grep -Fq 'import "OverviewFilter.js" as Filter' "$overview/OverviewModel.qml"
grep -Fq 'property string query: ""' "$overview/OverviewModel.qml"
grep -Fq 'function setQuery(text)' "$overview/OverviewModel.qml"
grep -Fq 'onTextChanged: root.overviewModel.setQuery(text)' "$overview/WindowOverview.qml"
grep -Fq 'text: root.overviewModel.query' "$overview/WindowOverview.qml"

# Sync Sprint 8 S8-04: closing a card that is not the focused window --
# dwm.c's own killclient() only ever closes selmon->sel, so this needs the
# new dwm-quickshell-state "close" action, not a dwm.c change (a plain
# ICCCM client message the X server routes directly to the target id).
# groups' own call site is the single place both S8-03's filter and S8-04's
# close-hiding must compose correctly, so it is pinned as one literal shape
# rather than two independent substrings that could each be present while
# nested in the wrong order.
grep -Fq 'Filter.filterWindows(Filter.excludeIds(root.dwmState.windowStates, root.closingWindowIds), root.query)' \
	"$overview/OverviewModel.qml"
grep -Fq 'property var closingWindowIds: []' "$overview/OverviewModel.qml"
grep -Fq 'function closeCard(windowId)' "$overview/OverviewModel.qml"
grep -Fq 'root.dwmState.closeWindow(windowId)' "$overview/OverviewModel.qml"
grep -Fq 'function excludeIds(windows, ids)' "$overview/OverviewFilter.js"
grep -Fq 'signal closeRequested(string windowId)' "$overview/OverviewCard.qml"
grep -Fq 'Accessible.name: "Close " + ' "$overview/OverviewCard.qml"
grep -Fq 'visible: cardMouse.containsMouse || closeMouse.containsMouse' "$overview/OverviewCard.qml"
card_mouse_line=$(grep -n 'id: cardMouse' "$overview/OverviewCard.qml" | cut -d: -f1)
row_layout_line=$(grep -n 'RowLayout {' "$overview/OverviewCard.qml" | head -n 1 | cut -d: -f1)
if [ "$card_mouse_line" -ge "$row_layout_line" ]; then
	printf 'OverviewCard cardMouse must be declared before the RowLayout so closeButton receives clicks.\n' >&2
	exit 1
fi
grep -Fq 'onCloseRequested: windowId => root.overviewModel.closeCard(windowId)' "$overview/WindowOverview.qml"
grep -Fq 'function closeWindow(windowId)' "$state/DwmState.qml"
grep -Fq 'closeWindowProcess.command = ["dwm-quickshell-state", "close", windowId]' "$state/DwmState.qml"

# close_window() is defined and dispatched the same way switch_workspace()/
# focus_window() already are, and does not touch dwm.c.
helper=$repo/scripts/dwm-quickshell-state
grep -Fq 'close_window() {' "$helper"
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq 'xdotool windowclose "$target"' "$helper"
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq 'wmctrl -ic "$target"' "$helper"
grep -Fq 'close)' "$helper"
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq 'close_window "${2:-}"' "$helper"

printf 'Quickshell window overview: PASS\n'
