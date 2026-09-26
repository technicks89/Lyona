# Design: cross-tag window overview (Sprint 6 S6-04)

Index: [`docs/SYNC-SPRINT-6-THEME-CONSISTENCY-AND-WINDOW-OVERVIEW.md`](../SYNC-SPRINT-6-THEME-CONSISTENCY-AND-WINDOW-OVERVIEW.md#s6-04-cross-tag-window-overview).
Upstream issue `#350`, no upstream code. This is a design pass only, per the
sprint doc's own recommendation — no implementation in this document, and
none of it has been built yet.

## What upstream asked for

A "Mission Control"-style overlay: compact previews/cards of every open
window across every dwm tag, including ones on tags not currently visible.
Clicking a card switches to that window's tag, focuses and raises it, and
dismisses the overlay. Escape or a click-away leaves the current tag and
focus unchanged. Keyboard navigation and activation. Multi-monitor and
multi-tag-membership windows handled predictably. The overview stays current
while windows open, close, or change tags. Existing tag/layout/hotkey/rule
behaviour is unaffected, desktop UI policy stays out of the C event loop
where practical, and it must not cost idle CPU while closed.

## What already exists, and what doesn't

The single biggest finding of this design pass: **no `dwm.c` change is
needed.** Lyona already has, and the panel already uses, the exact machinery
this feature needs:

- `_NET_CLIENT_LIST` (standard EWMH) is dwm's own list of every managed
  window, kept current on every map/unmap (`dwm.c`, `updateclientlist()`).
- `_NET_WM_DESKTOP` per window is dwm's own per-client tag/monitor encoding
  (already read today, see below).
- `_DWM_MONITOR_DESKTOPS` (Lyona's own EWMH extension) gives each monitor's
  geometry and which of those per-window desktop numbers is *its* current
  one — this is exactly the "which tag, on which monitor" mapping a
  cross-tag overview needs, and it already exists for `DwmState.qml`'s
  workspace-row UI.
- `scripts/dwm-quickshell-state` already polls `_NET_CLIENT_LIST` via
  `xprop -id WINDOW _NET_WM_DESKTOP _NET_WM_PID WM_CLASS` per window
  (`client_snapshot()`), already filters out root-owned windows the same
  way, and already exposes a live `watch` subcommand plus one-shot
  `switch`/`focus` actions.
- `config/quickshell/state/DwmState.qml` already parses that watch stream,
  already has `switchWorkspace(index)` and `focusWindow(windowId)` wired to
  real `dwm-quickshell-state` calls, and already computes monitor/screen
  mapping from `_DWM_MONITOR_DESKTOPS` (`screenForMonitorIndex()`,
  `screenIndex()`) for exactly the multi-monitor case this feature needs.

What's missing is narrower than it first looks:

1. **Per-window data, not per-class.** `client_snapshot()`'s `apps=` output
   is deduplicated by `WM_CLASS` (`seen["|" class "|"]`, one entry per
   running application) — it backs the panel's running-apps row, where that
   is correct, but an overview needs one card *per window*, including two
   windows of the same app. It also never fetches a window title
   (`_NET_WM_NAME`/`WM__NAME`) — nothing today needs it, so nothing reads it.
2. **Tag, not just EWMH "desktop" number, per window.** `_NET_WM_DESKTOP` is
   already read per window; what's missing is *keeping* it per window in the
   output (today it only feeds the aggregate `occupied=` list) and resolving
   it to a human tag label + owning monitor via `_DWM_MONITOR_DESKTOPS`,
   which `DwmState.qml` already knows how to do for its own purposes.
3. **A surface to show it in and a way to open it.** No existing popup shows
   arbitrary window content as a grid of cards; the closest precedent is
   `RunningAppsArea.qml`, which shows one icon per running app in the panel,
   not a preview grid.

## Proposed shape

### New helper output, not a new dwm.c property

Add a new `windows` subcommand (and a `windows` line to the existing `watch`
stream, the same way `apps=` already appears there) to
`scripts/dwm-quickshell-state`, reusing `client_snapshot()`'s existing
per-window loop rather than writing a second one:

- Do **not** touch `apps=`'s existing dedup-by-class behaviour — the panel
  depends on it unchanged.
- Add a second, undeduplicated field, e.g. `windows=<id>:<desktop>:<class>:<title>|...`,
  built in the same awk pass over the same `xprop` output `client_snapshot()`
  already gathers, adding one more `xprop` atom
  (`_NET_WM_NAME`, falling back to `WM_NAME` the way `root_status()` already
  does for the bar) to the per-window query it already makes. No new X
  round-trips beyond that one extra atom per window, and no new call sites:
  the *existing* `watch` loop already re-polls on client-list/desktop
  changes for `apps=`/`occupied=`, so `windows=` rides along for free.
- Title text needs the same quoting/escaping care `class` already gets
  (strip embedded `|`, the field separator, the way `dwm-quickshell-launcher`
  already sanitises `.desktop` fields elsewhere in this codebase) before it
  reaches QML.

### `DwmState.qml` gains the per-window list

- `property var windows: []`, parsed from the new `windows=` field the same
  way `apps` is parsed today, each entry `{windowId, desktop, appClass,
  title}`.
- A `windowsByTag()`-style helper reusing the *existing*
  `monitorWorkspaceRows`/`screenForMonitorIndex()` machinery to resolve each
  window's `desktop` to `{tagIndex, monitorIndex}` — this is new glue code,
  not new data collection, since the raw desktop-to-monitor mapping already
  exists for the panel's own workspace rows.
- Add a separate `activateOverviewWindow(windowId)` action for card clicks
  and keyboard activation, backed by a new helper action. Resolve the
  window's current tag and owning monitor, switch to that tag and monitor,
  then focus and raise the window before dismissing the overview. Sequence
  these steps so focus waits for the workspace switch to complete, and
  handle a window disappearing during activation without acting on stale
  data. Navigate to the window without moving it or changing its tags.
- Keep `focusWindow(windowId)` and the existing helper `focus` action
  unchanged for panel clicks and other callers. They use `xdotool
  windowactivate` or `wmctrl -ia`, which request `_NET_ACTIVE_WINDOW`;
  dwm's `clientmessage()` handler only marks the target urgent. The new
  overview action must explicitly focus and raise the window after
  navigation; reusing that activation request is insufficient.

### A new popup: `config/quickshell/overview/WindowOverview.qml`

- Same `PopupWindow` + `ClickAwayPopup`-style dismiss-on-click-outside as the
  launcher and command menu already use (`core/ClickAwayPopup.qml`), so
  Escape and click-away are inherited behaviour, not new code to get right.
- A `GridView` (or a `Flow` inside the existing `Flickable`/`viewport`
  pattern `ClickAwayPopup` already provides) of window cards, grouped by tag
  — a `SectionLabel` per occupied tag (the same component the launcher
  already uses for "Categories"), cards under it. Each card: a small
  preview or, for a first cut, just the app icon (`Icons.qml`, already used
  elsewhere) plus title and tag/monitor label — a live thumbnail is a later
  enhancement, not a blocker (see Non-goals).
- Keyboard nav: the exact `Keys.onPressed` shape `LauncherWindow.qml`
  already has (arrow keys / `selectRelative`, Home/End / `selectAbsolute`,
  Enter to activate, Escape to close) against a new small model object
  (`OverviewModel.qml`) that just orders `DwmState.windows` into the grouped
  list and tracks a selection index — the pattern is copy-adapt, not new
  design.
- Multiple monitors: each card already carries a resolved `monitorIndex`
  (via the same `_DWM_MONITOR_DESKTOPS` mapping `DwmState.qml` uses); the
  grouping/sort order should probably be tag-first (matching "including
  windows on tags that are not currently visible", the issue's own framing)
  with the monitor shown as a small label per card, rather than a
  monitor-first split — worth confirming with the maintainer before
  building, not a technical fork in the plumbing either way.
- Multiple windows per app: since the new `windows=` field is per-window
  (not deduped like `apps=`), this falls out for free — no special case.

### Opening it

- A new `IpcHandler { target: "overview" }` in `shell.qml`, matching the
  `launcher`/`menu` handlers already there (`open()`/`close()`/`toggle()`),
  and a new `hotkeys.toml` binding in the "Launchers" section (a `SUPER+Tab`
  or similar — precedent: `func="spawn", cmd="quickshell ipc --path ... call
  overview toggle"`, the exact shape `SUPER+r`'s launcher binding already
  uses).
- On open, following `selectPanelPopup`'s existing convention (seen in the
  panel popup code Lyona already has for mutual exclusion between launcher /
  notification history / control-center utility), close any other open
  panel popup first.

## Non-goals (for a first version)

- **Live thumbnails.** A real per-window pixel preview needs a compositing
  capture path Quickshell/Lyona does not have today (Picom captures for its
  own compositing, not for handing frames to another client). First
  version: icon + title + tag/monitor label, matching what the panel's own
  running-apps row already shows today, not a visual regression from
  nothing. A real preview is a separate, later design.
- **Drag-and-drop to retag a window from the overview.** The issue asks for
  "navigate to the existing window rather than moving it," so this is
  explicitly out of scope, not just deferred.
- **A dwm.c-side push protocol.** `dwm-quickshell-state watch`'s existing
  polling-on-X-event model (it already re-runs `client_snapshot()` when the
  client list or a window's properties change) is reused as-is; there is no
  proposed change to how or when it wakes up.

## Idle-CPU and event-driven-ness

The issue explicitly asks this be event-driven with no significant idle
cost. Since this reuses the *existing* `dwm-quickshell-state watch` stream
(already running today for the panel's workspace/app indicators) rather than
starting a second watcher, the overview adds no new idle-time process or
poll loop: the popup just reads `DwmState.windows`, which is already kept
current by a mechanism that already runs whether or not the overview exists.
The only genuinely new idle cost is the small amount of additional `xprop`
work per client-list-changing event (one more atom fetched per window, in a
loop that already runs); that should be validated empirically once built
(the same `check-desktop-smoke-xvfb`-adjacent close-vs-open idle CPU
comparison `docs/UPSTREAM-SYNC.md`'s own manual-qualification checklist
already does for every sprint that adds a watcher).

## Verification plan (once implemented)

- `scripts/dwm-quickshell-state windows` unit-style coverage the same shape
  as `tests/test-quickshell-state.sh`'s existing `client_snapshot()` coverage
  (it already stubs `xprop` per window id, e.g. `0xaa`/`0xbb` with their own
  `_NET_WM_DESKTOP`/`WM_CLASS` — extend that pattern with a title atom, not a
  new stub shape), covering: multiple windows of the same class (must not
  dedup), a window with no title, an embedded `|` in a title (must not break
  the field separator), a root-owned window (must still be filtered).
- An xvfb harness opening several `xclient`-style windows across more than
  one tag (the pattern `tests/test-xvfb-runtime.sh` already uses for
  multi-window scenarios) and asserting the overview's model lists all of
  them, grouped correctly, and that `activateOverviewWindow` from a card or
  keyboard activation selects the target tag and monitor, focuses and raises
  the window, and preserves its tags and monitor assignment. Cover a hidden
  tag and a window on another monitor, and verify existing `focusWindow`
  callers retain their behavior, reusing
  `wait_for_active_window`/`wait_for_current_desktop`, both of which already
  exist in that file's helper library.
- A closed-popup idle-CPU baseline (per `docs/UPSTREAM-SYNC.md`'s existing
  manual qualification checklist item 4) before and after this lands, to
  confirm the "no significant idle resource use" requirement.
- Escape/click-away leaves tag and focus unchanged: an xvfb case opening the
  overview, pressing Escape, and asserting `_NET_CURRENT_DESKTOP`/
  `_NET_ACTIVE_WINDOW` are unchanged from before it opened.
- A window closing while the overview is open: open it, kill a window whose
  card is showing, assert the popup does not error and the card disappears
  (or the overview closes gracefully) rather than acting on a stale window id.

## Suggested phasing

Sized to land as more than one PR, each independently useful and testable,
matching this project's "one branch per sprint item" convention — this
design doc covers the whole feature, but implementation should not be one
enormous PR:

1. `scripts/dwm-quickshell-state windows` + the `windows=` watch field, with
   its own test coverage, no QML changes yet.
2. `DwmState.qml`'s `windows` property, tag/monitor resolution, and separate
   overview activation action, with a small headless (non-visual) test of the
   resolution logic and an X11 activation test, still no UI.
3. `WindowOverview.qml` + `OverviewModel.qml` + the IPC handler + hotkey,
   mouse-only first (click a card, click away, Escape).
4. Keyboard navigation.
5. Multi-monitor label polish and the closing-window-while-open edge case,
   once 1-4 are real and testable against them rather than imagined.
