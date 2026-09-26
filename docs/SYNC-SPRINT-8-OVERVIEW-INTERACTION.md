# Sync Sprint 8 — Cross-tag window overview: interaction completeness

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Continues
[Sprint 7](SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md), which landed a working
mouse-only overview. This sprint finishes what upstream issue `#350` actually
asked for (keyboard navigation, correct behaviour when a window closes mid-use,
multi-monitor clarity) and adds two things the issue did not ask for but a
usable overview needs, sized in rather than treated as scope creep.

**Depends on Sprint 7 (S7-01 through S7-03) being merged.**

| Item | Kind | Size |
| --- | --- | --- |
| [S8-01](#s8-01-keyboard-navigation) | Design doc phase 4 | ~+40 QML, ~+40 tests |
| [S8-02](#s8-02-multi-monitor-labels-and-a-window-closing-mid-use) | Design doc phase 5 | ~+30 QML, ~+50 tests |
| [S8-03](#s8-03-type-to-filter) | New (not in the design doc's v1) | ~+40 QML, ~+30 tests |
| [S8-04](#s8-04-close-a-window-from-its-card) | New (not in the design doc's v1) | ~+30 QML, ~+40 tests |

---

## S8-01: keyboard navigation

The exact `Keys.onPressed` shape `LauncherWindow.qml` already has: arrow
keys (`selectRelative`), Home/End (`selectAbsolute`), Enter to activate the
selected card, Escape to close (inherited from `ClickAwayPopup` already, so
this item is really "give the model a selection index and honour arrows",
not "invent keyboard handling"). `OverviewModel.qml` gains:

- `selectedIndex`, `selectRelative(delta)`, `selectAbsolute(index)` against
  the tag-grouped card list Sprint 7 already builds — moving past the last
  card of one tag's group into the first of the next, matching how a
  reasonable person expects arrow keys to traverse a grouped grid (up/down
  within a row of cards, left/right or wrap between tag sections — the exact
  traversal order is a small UX call to make during implementation, not a
  blocking design question).
- A visible focus ring on the selected card (`Theme.controlFocusBorder`,
  already used by every other focusable control in this app — not a new
  token).

**Verification:** an xvfb case driving `xdotool key` through the overview
(open it, arrow through several cards, assert the visible/model selection
matches, Enter activates the expected window) — the same interaction-driving
style `test-xvfb-runtime.sh` already uses for dwm-level keys, applied here
to a Quickshell popup the way `test-quickshell-command-menu.sh` or the
launcher's own xvfb coverage already drives QML keyboard handling.

## S8-02: multi-monitor labels and a window closing mid-use

Two independent, small correctness items the design doc flagged and
deferred to "once 1-4 are real":

- **Monitor label polish.** Each card already carries a resolved
  `monitorIndex` (Sprint 7); show it only when there is more than one
  monitor (a single-monitor system should not clutter every card with a
  redundant "Monitor 1"), and confirm with the maintainer whether the
  monitor label lives on the card or as a sub-grouping under each tag's
  `SectionLabel` — try the card-label version first, it is less structural
  churn if the sub-grouping is wanted later.
- **A window closing while the overview is open.** Open the overview, then
  close (or crash) one of the windows a visible card represents: the popup
  must not error, the stale card must disappear (or, simpler and safer to
  implement first, the whole popup closes gracefully) rather than acting on
  a `focusWindow` call for a window id that no longer exists. Since
  `DwmState.windows` is driven by the same live `watch` stream as
  everything else, this is mostly "does `OverviewModel.qml` re-derive its
  card list correctly when `DwmState.windows` shrinks while the popup is
  open," not new IPC.

**Verification:** an xvfb case with 2+ monitors configured (the pattern
`tests/test-monitor-tag-switching.sh` already sets up for multi-monitor
xvfb scenarios) confirming labels appear only when needed and point at the
right monitor; a separate case opening the overview, killing a window whose
card is showing, and asserting the popup survives and does not act on the
stale id.

## S8-03: type-to-filter

Not in the design doc's first version, and not asked for by issue `#350` in
so many words, but every "grid of many things, pick one" surface Lyona
already ships (the launcher) supports typing to narrow the list, and an
overview with more than a handful of windows benefits from the same
affordance more, not less, than the launcher does. Reuse, not reinvent:

- A search field using the same component the launcher's own search box
  uses, filtering the tag-grouped card list by title/class substring
  (case-insensitive, the launcher's own matching convention).
- Typing does not need its own hotkey: the overview popup already grabs
  keyboard focus (`ClickAwayPopup`'s `grabFocus: true`), so any printable
  key while no field has focus can route into the search box, the same way
  the launcher's own window behaves.
- Arrow-key navigation (S8-01) operates on the *filtered* list, not the
  full one — matching the launcher's `selectRelative`/`filteredApps`
  relationship exactly.

**Verification:** an xvfb case typing a substring that matches one card
among several, confirming only it remains selectable and Enter activates
that specific window; a case where the filter matches zero cards (must not
error, and Enter must do nothing rather than activate a stale selection).

## S8-04: close a window from its card

Also not in the design doc's first version. The issue explicitly excludes
drag-and-drop to retag a window ("navigate to the existing window rather
than moving it"), which this is not — closing a window is a common,
low-risk companion action in every comparable overview (GNOME Overview,
macOS Mission Control/Exposé), not the thing the issue ruled out.

- A small close affordance on card hover (an "×" in a corner, `ShellButton`
  or similar, `Accessible.name: "Close " + card.title`). `dwm.c`'s own
  `killclient()` only closes `selmon->sel` (the focused client), which most
  cards are not, so this needs a new `dwm-quickshell-state close WINDOWID`
  action — `xdotool windowclose "$window_id"` (sends `WM_DELETE_WINDOW`, the
  same graceful-close request `killclient()` itself sends first, just to an
  arbitrary id instead of the focused one), matching the existing
  `xdotool`-with-a-fallback pattern the `switch` action already uses. No
  `dwm.c` change: this is a plain ICCCM client message sent directly to the
  target window, not something the window manager needs to route.
- The card removes itself (or the list re-derives, same as S8-02's
  window-closes-mid-use handling — this item and that one should share
  code, not duplicate it) rather than waiting for a full `watch` re-poll to
  notice, so the UI feels immediate; the underlying state still converges
  from the same live stream shortly after regardless.

**Verification:** an xvfb case opening the overview, clicking a card's close
affordance, asserting the target window's process actually exits (not just
that the card visually disappears) and the overview does not otherwise
change tag/focus. A keyboard-equivalent (matching S8-01's navigation) is a
reasonable follow-up but not required to land this item — mouse-only close
is an acceptable first cut the way S7-03 landed mouse-only card activation.

---

## Verification (whole sprint)

Same gates as every sprint: `scripts/run-tests make clean all`,
`check-shell`, `check-format`, `check-quickshell-qml`, then `make check`
before the sprint closes, plus the **Full suite (manual)** workflow on the
sprint branch and on `main`.

## Not in this sprint

Live thumbnails, motion/animation polish, an accessibility pass beyond the
focus ring S8-01 already adds, and formal idle-CPU/performance testing at
scale — [`SYNC-SPRINT-9-OVERVIEW-POLISH.md`](SYNC-SPRINT-9-OVERVIEW-POLISH.md).
