# Sync Sprint 7 — Cross-tag window overview: foundation

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Continues
[Sprint 6 S6-04](SYNC-SPRINT-6-THEME-CONSISTENCY-AND-WINDOW-OVERVIEW.md#s6-04-cross-tag-window-overview)
(upstream issue `#350`, no upstream code — Lyona's own design) now that
[`docs/design/CROSS-TAG-WINDOW-OVERVIEW.md`](design/CROSS-TAG-WINDOW-OVERVIEW.md)
exists. That design's own "Suggested phasing" is what Sprints 7-9 implement;
this sprint is its phases 1-3, the smallest slice that is a working (if
mouse-only, icon-only) feature end to end.

**Goal:** the data layer and a minimal real surface. Land as three PRs in
order — each depends on the one before it.

| Item | Design phase | Kind | Size |
| --- | --- | --- | --- |
| [S7-01](#s7-01-per-window-data-in-dwm-quickshell-state) | 1 | New feature | ~+40 script, ~+40 tests |
| [S7-02](#s7-02-dwmstateqml-gains-the-window-list) | 2 | New feature | ~+40 QML, ~+40 tests |
| [S7-03](#s7-03-the-overview-popup-mouse-only) | 3 | New feature | ~+150 QML, ~+80 tests |

---

## S7-01: per-window data in `dwm-quickshell-state`

A new `windows` subcommand and a `windows=` line in the existing `watch`
stream, built in `client_snapshot()`'s existing per-window `xprop` loop
(design doc "New helper output, not a new dwm.c property") — not a second
loop, and **not** a change to the existing `apps=` field's dedup-by-class
behaviour, which the panel's running-apps row depends on unchanged.

- One more `xprop` atom per window: `_NET_WM_NAME`, falling back to
  `WM_NAME` the way `root_status()` already does for the status bar text.
- Output shape: `windows=<id>:<desktop>:<class>:<title>|...`, one entry per
  window, no dedup.
- Title sanitisation: strip the field separator (`|`) and any embedded
  newline/tab from the title before it reaches this line, the same care
  `class` already gets and the same spirit as `dwm-quickshell-launcher`'s
  `.desktop`-field sanitising elsewhere in this codebase.
- Root-owned windows are filtered the same way `apps=`/`occupied=` already
  are (`owner_uid(pid) == 0` skip).

**Verification:** extend `tests/test-quickshell-state.sh`'s existing stub
shape (it already fakes `xprop` per window id, e.g. `0xaa`/`0xbb`, each with
its own `_NET_WM_DESKTOP`/`WM_CLASS`) with a title atom, covering: multiple
windows of the same class (must **not** dedup, unlike `apps=`), a window
with no title (must not crash or emit a malformed field), a title containing
`|` (must not corrupt the field separator), a root-owned window (must still
be filtered), and that `apps=`'s own output is byte-identical before and
after this change (the regression guard for "do not touch `apps=`"). `make
check-shell check-format` plus whatever target wraps
`test-quickshell-state.sh`.

## S7-02: `DwmState.qml` gains the window list

- `property var windows: []`, parsed from `windows=` the same way `apps` is
  parsed today: `{windowId, desktop, appClass, title}` per entry.
- A resolution helper (`windowsByTag()`-shaped, name TBD at implementation
  time) that maps each entry's raw `desktop` number to `{tagIndex,
  monitorIndex}` using the *existing* `monitorWorkspaceRows` /
  `screenForMonitorIndex()` machinery `DwmState.qml` already has for the
  panel's own workspace rows — new glue, not new data collection.
- No new `Process`/watcher: this only parses a field the existing `watch`
  stream already carries as of S7-01.

**Verification:** a small headless (non-visual) test of the resolution
logic — feed it a `monitorWorkspaceRows` fixture and a `windows` list,
assert the `{tagIndex, monitorIndex}` output, including a window whose
`desktop` does not match any row (must not crash; a sane fallback, e.g. tag
0 / monitor 0, the same defensive pattern `screenForMonitorIndex()` already
uses for an out-of-range index). No QML UI yet, so this can be a
`qmltestrunner`-based `tst_*.qml` unit test against the parsing/resolution
functions directly, the same convention `tst_display_layout.qml` already
established for a pure-logic library — matching, not inventing, precedent.

## S7-03: the overview popup, mouse-only

`config/quickshell/overview/WindowOverview.qml` + a small `OverviewModel.qml`
+ the IPC handler + hotkey (design doc "A new popup" and "Opening it").
Mouse-only for this item: click a card to focus, click away or the popup's
own dismiss to close. Keyboard navigation is Sprint 8, not here.

- `ClickAwayPopup`-based (inherits Escape/click-away dismiss for free, same
  as the launcher and command menu).
- Cards grouped by tag (`SectionLabel` per occupied tag, the launcher's own
  "Categories" component, reused not reinvented), icon + title +
  tag/monitor label per card — no thumbnail yet (Sprint 9).
- Card click calls `DwmState.focusWindow(windowId)`, the exact function
  `RunningAppsArea.qml`'s own click handler already calls — no new dwm-side
  behaviour, a second caller of an existing one.
- `IpcHandler { target: "overview" }` in `shell.qml` (`open()`/`close()`/
  `toggle()`, matching `launcher`'s), a new `hotkeys.toml` binding under
  "Launchers" (candidate: `SUPER+Tab`, confirm the exact key with the
  maintainer before landing — not a design decision worth blocking on).
- On open, closes any other panel popup first via the existing
  `selectPanelPopup` convention.

**Verification:** an xvfb harness (the `tests/test-xvfb-runtime.sh`/
`wait_for_active_window`/`wait_for_current_desktop` pattern) opening several
`xclient`-style windows across more than one tag, opening the overview,
asserting it lists all of them grouped correctly, and that clicking a card
lands on the right tag with the right window focused. A separate case:
Escape/click-away leaves `_NET_CURRENT_DESKTOP`/`_NET_ACTIVE_WINDOW`
unchanged from before the overview opened. A closed-popup idle-CPU baseline
(`docs/UPSTREAM-SYNC.md`'s existing manual-qualification checklist item 4,
run once here as the first real measurement — Sprint 9 formalizes it as a
standing test) to catch anything grossly wrong early, even though this
sprint's own idle cost should be ~0 by design (S7-01's one extra `xprop`
atom rides an already-running watch loop).

---

## Verification (whole sprint)

Same gates as every sprint: `scripts/run-tests make clean all`,
`check-shell`, `check-format`, `check-quickshell-qml`, then `make check`
before the sprint closes, plus the **Full suite (manual)** workflow on the
sprint branch and on `main`.

## Not in this sprint

Keyboard navigation, multi-monitor label polish, the window-closes-while-open
edge case (Sprint 8); live thumbnails, motion, accessibility pass, formal
idle-CPU/performance testing (Sprint 9). See
[`SYNC-SPRINT-8-OVERVIEW-INTERACTION.md`](SYNC-SPRINT-8-OVERVIEW-INTERACTION.md)
and
[`SYNC-SPRINT-9-OVERVIEW-POLISH.md`](SYNC-SPRINT-9-OVERVIEW-POLISH.md).
