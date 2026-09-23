# S8-01 — Overview popup keyboard navigation

Evidence for the item recorded in `CHANGELOG.md` under "Added" as "Keyboard
navigation for the cross-tag window overview (Sync Sprint 8 S8-01, ... issue
`#350`)", and pinned in `TASKS.md`. This file exists because that PR
(`89b36f7`, "keyboard nav") updated `CHANGELOG.md` but not `TASKS.md` or
`docs/evidence/`, which `docs/UPSTREAM-SYNC.md`'s "Commit and tracking"
section requires in the same PR; this file and the `TASKS.md` entry close
that gap after the fact.

## What was implemented

`config/quickshell/overview/WindowOverview.qml` gained the same
`Keys.onPressed` shape `LauncherWindow.qml` already uses: Up/Down/Left/Right
move the selection by one, Home/End jump to the first/last card, and Enter
activates the selected card. Escape already closed the popup (Sprint 7
S7-03).

`config/quickshell/overview/OverviewModel.qml` gained:

- `selectedIndex` (the currently selected flat index),
- `flatCards` (the tag-grouped card list flattened into keyboard-navigation
  order),
- `selectRelative(delta)`, `selectAbsolute(index)`, `activateSelected()`.

The wrap-around/clamping arithmetic itself lives in a new pure library,
`config/quickshell/overview/OverviewSelection.js` (`.pragma library`), the
same split already used for `PanelTooltipPosition.js` and
`DwmStateWindows.js`. `DwmStateWindows.js`'s `groupByTag()` now assigns each
window a `flatIndex` in render order, which the selected card compares
against `OverviewModel.selectedIndex` for its highlight
(`Theme.menuSelectedBackground`/`controlSelectedBorder`, the same tokens
`LauncherResultDelegate.qml`'s own `selected` state uses), independent of
mouse hover.

Out of scope for this item (left for the rest of S8-02, per the CHANGELOG
entry): multi-monitor label polish and the window-closes-while-open edge
case.

## Plan-document note

The CHANGELOG entry and the new source comments cite
`docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md` as this item's plan document.
That file does not exist anywhere in this repository (checked the working
tree and `git log --all --diff-filter=A -- docs/SYNC-SPRINT-8*`, no hits) —
either it was never committed or it was deleted as a "retired plan document"
per `docs/UPSTREAM-SYNC.md`'s convention of removing a sprint doc once all of
its items land, even though S8-02 is still open. Rather than invent its
content, the closest present, real planning source for this feature is
`docs/SYNC-SPRINT-6-THEME-CONSISTENCY-AND-WINDOW-OVERVIEW.md#s6-04-cross-tag-window-overview`
(issue `#350`, the feature this item is part of) and `docs/UPSTREAM-SYNC.md`'s
own "Verification" section, whose gates are used below.

## Automated test coverage

- `tests/qml/tst_overview_selection.qml` — direct `TestCase` coverage of
  `OverviewSelection.js`'s pure math under `qmltestrunner`: forward/backward
  wrap at the ends, in-bounds single steps, a multi-step ("PageDown-style")
  delta, an empty-list reset, and `selectAbsolute()` clamping to
  `length - 1`/`0`.
- `tests/test-quickshell-overview.sh` (lines ~132-168 of the version in this
  commit) — structural/wiring pins: `WindowOverview.qml`'s `Keys.onPressed`
  calls `selectRelative(1|-1)`, `selectAbsolute(0)`,
  `selectAbsolute(flatCards.length - 1)`, and `activateSelected()`;
  `OverviewModel.qml` defines `selectRelative()`, `selectAbsolute()`,
  `activateSelected()`, `flatCards`, and `selectedIndex`, and delegates the
  arithmetic to `OverviewSelection.js`; the selected card's `selected:`
  binding compares `flatIndex` against `selectedIndex`.
- `tests/qml/tst_dwm_state_windows.qml` — covers `groupByTag()`'s
  `flatIndex` assignment (render order), which the keyboard-nav wiring above
  depends on.

## Verification actually performed here

This sandbox has no `make`, no `qmltestrunner`/`qml6-testrunner`, and no
GUI/X server, so the full gate list in `docs/UPSTREAM-SYNC.md#verification`
(`scripts/run-tests make clean all`, `check-shell`, `check-format`,
`check-quickshell-qml`, `qmltestrunner -input tests/qml`, `make check`) could
not be run here. What was actually run, with real output:

```
$ sh tests/test-quickshell-overview.sh
Quickshell window overview: PASS
$ echo "exit=$?"
exit=0
```

This is a real pass of the structural test above, run directly (not through
`make check-quickshell-overview`, whose `all` prerequisite needs a C
toolchain-built `dwm` this sandbox does not need for this shell-only check;
the script itself has no such dependency).

```
$ sh tests/test-quickshell-state.sh
dwm-quickshell-state: expected pid 1 to be root-owned; cannot exercise the uid skip
exit=1
```

This failure is a pre-existing sandbox limitation (no root-owned pid 1
available here) unrelated to keyboard navigation; it is not evidence for or
against this item, and is not run by the wiring test above.

`tests/qml/tst_overview_selection.qml` — **not executed in this sandbox**:
neither `qmltestrunner` nor `qml6-testrunner` is installed here
(`command -v qmltestrunner` reports nothing). The wrap/clamp arithmetic it
exercises was instead read directly against `OverviewSelection.js` and cross-
checked by hand against each `compare()` assertion in the test file, but that
is a manual read, not a test run, and is recorded as such rather than claimed
as a pass. Whoever has `qmltestrunner` available should run
`QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml` and record the
result here.

No CI run URL is recorded here either, for the same reason
`docs/UPSTREAM-SYNC.md#verification` asks for one: this environment cannot
trigger the **Full suite (manual)** GitHub Actions workflow.
