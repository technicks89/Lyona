# Sync Sprint 10 -- Completion audit: close what was marked done but is not

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Follows
[Sprint 8](SYNC-SPRINT-8-OVERVIEW-INTERACTION.md) and is independent of
Sprint 9. It exists because an audit of `main` at `8448bb5` (2026-09-25)
against every plan and every item marked done found work that is closed on
GitHub, or ticked in a status table, but is not actually complete.

Nothing in this sprint adds a feature. Every item either finishes something a
closed issue already claimed, or makes a claim in the repository checkable.

| Item | Kind | Size |
| --- | --- | --- |
| [S10-01](#s10-01-restore-the-overview-model-behind-type-to-filter-and-close-from-card) | Bug: shipped item is broken at runtime | ~+35 QML, ~+15 tests |
| [S10-02](#s10-02-repair-the-command-menu-pin-that-the-overview-popup-broke) | Bug: red test since #135 | ~+2 tests |
| [S10-03](#s10-03-run-the-tests-that-make-check-never-ran) | Coverage gap | ~+15 Makefile/CI |
| [S10-04](#s10-04-drive-the-overview-through-real-input-under-xvfb) | Missing verification from Sprint 8 | new xvfb test |
| [S10-05](#s10-05-backfill-sprint-7-and-8-tracking) | Tracking gap | docs only |
| [S10-06](#s10-06-get-the-full-suite-green-on-main-and-record-it) | Qualification | CI run, no code |
| [S10-07](#s10-07-qualification-ledger-for-sprints-closed-with-hardware-checks-open) | Qualification | docs only |
| [S10-08](#s10-08-correct-the-status-tables) | Tracking gap | docs only |

**Order:** S10-01 and S10-02 first (they turn `make check` from red toward
green), then S10-03, S10-04, S10-05, then S10-06 last among the code items
because it needs the earlier ones. S10-07 and S10-08 are docs and can go
any time.

**Status:** This PR includes S10-01 through S10-05 and S10-08, validated
locally as described under each item. S10-06 remains open: it needs this
merged and the workflow run. S10-07 remains open: it needs real hardware.

---

## What the audit found

Method: every sprint issue (S1-01 to S9-04) compared with `CHANGELOG.md`,
`TASKS.md`, `docs/evidence/` and the code on `main`; every path, make target
and test a plan cites checked against the tree; `make check` and the QML unit
tests actually run on a CachyOS host with Qt 6, `xvfb-run`, `quickshell`,
`shellcheck` and `shfmt` installed (the sandbox the earlier evidence was
gathered in had none of these).

### Confirmed problems

| # | Finding | Evidence |
| --- | --- | --- |
| 1 | **Type-to-filter (S8-03, issue #127) and close-from-card (S8-04, issue #128) are closed but broken.** `WindowOverview.qml` reads `overviewModel.query`, calls `setQuery()` and `closeCard()`, but `OverviewModel.qml` defines none of them and never imports `OverviewFilter.js`. PR #138's file list does not include `OverviewModel.qml`. | Quickshell logs `WindowOverview.qml[115]: Unable to assign [undefined] to QString` and `[160]: TypeError: Cannot read property 'length' of undefined` on load |
| 2 | `make check` is red on `main` and stops at `check-quickshell-queued-run-xvfb`, so every target after it never runs. | `Makefile:583`; that test fails on the `TypeError:` above |
| 3 | Five more targets fail for the same cause: `check-quickshell-picom-model-xvfb`, `-settings-responsiveness-xvfb`, `-update-progress-xvfb`, `-wallpaper-reconcile-xvfb` (each loads the real shell), plus queued-run | Each log carries the same `WindowOverview.qml[160:-1]` TypeError |
| 4 | `check-quickshell-command-menu` has been red since #135. `shell.qml` now closes both menus in an `onVisibleChanged` block; the test still greps for the old one-line form. | `tests/test-quickshell-command-menu.sh:46` |
| 5 | Three passing xvfb tests are never run by `make check`: `check-quickshell-health-navigation-xvfb`, `check-quickshell-information-ui-xvfb`, `check-quickshell-health-xvfb`. Sprint 2 and `ROADMAP.md` Phase 6 cite the first two as evidence. | Targets exist; absent from the `check` recipe (`Makefile:~850-940`) |
| 6 | `tests/test-settings-display-security.sh` is referenced nowhere (no target, no workflow, no doc). It is a root-only, container-only test of the privileged display helper. | `grep -r display-security` finds only the file itself |
| 7 | The **Full suite (manual)** workflow, required by Sprints 1, 4, 5 and 8, has run 3 times and failed all 3 (2026-09-21, on `7dc32ab`, `b40e0aa`, `502a0e0`). It has not run since, across 36 commits. | Actions runs 35553275713, 35554146230, 35555369803 |
| 8 | S7-02 (#134), S7-03 (#135) and S8-02 to S8-04 (#138) have **no** dedicated `CHANGELOG.md` entry, and none of them has a `TASKS.md` entry or evidence, although issues #123, #124 and #126 to #128 are closed. Only a later bug-fix entry (`CHANGELOG.md:1535`) mentions S7-02 and S7-03. The plan's required xvfb interaction cases do not exist; `tests/test-quickshell-overview.sh` only greps source. | `git show --stat` of `2e2ee14`, `e67658e` and `7ea11ff`: `e67658e` and `2e2ee14` touch no `CHANGELOG.md`; `7ea11ff` touches none either |
| 9 | S8-01's evidence file says its `qmltestrunner` run "was not executed"; issue #125 is closed anyway. (Run now: see S10-05.) | `docs/evidence/s8-01-overview-keyboard-nav.md` |
| 10 | `UPSTREAM-SYNC.md` still says Sprints 7 and 8 are "Not started". | `docs/UPSTREAM-SYNC.md` status table |
| 11 | Milestones for Sprints 4 and 5 are closed while their own status rows say "qualification open"; issue #43 (S1-10) is closed while decision D-4 is still "Open". | `gh api .../milestones`; `UPSTREAM-SYNC.md` "Open decisions" |

### Checked and found sound

- Sprints 1 to 6 and S7-01: every code item has a matching `CHANGELOG.md`
  entry (S1-02, S1-10, S4-07, S4-08 are docs or decisions and are recorded in
  `UPSTREAM-SYNC.md`; S6-02 is recorded at `CHANGELOG.md:1300`; S7-01 in
  `b03ee83`). The exceptions are the S7-02, S7-03 and S8 items in finding 8.
- Tests the plans named but that are absent by path
  (`tst_display_profiles.qml`, `test-image-user-defaults.sh`,
  `test-dwm-xsettings.sh`) were ported under Lyona names
  (`tests/qml/DisplayAutomaticProfiles.qml`, `tests/test-seed-default-apps.sh`)
  or were explicitly ruled not to apply.
- `ROADMAP.md` records the D-5 firewall limitation (lines 410-431), the D-8
  decision (433) and the Self-Heal default (Future Evaluation), as S4-08
  step 4 required.
- Phases 1 to 6 carry their real-hardware limitations inside their own
  "Completion Evidence" sections; they are not silently claimed.
- The Qt 6 QML unit suite passes here: 148 passed, 0 failed
  (`/usr/lib/qt6/bin/qmltestrunner -input tests/qml`, offscreen).
  `tests/test-quickshell-overview.sh`, `test-quickshell-state.sh` and
  `test-quickshell-state-close.sh` pass.

### Not resolved by this audit

- `check-system-management` fails on this host with
  `Namespace PackageKitGlib not available` (`packagekit` is not installed
  here). That is a host gap, not a repository defect, and matches the
  "16 PackageKitGlib-unavailable cases" `ROADMAP.md` already records. S10-06
  finds out whether the CI container has it.
- `check-session-guards` failed inside a batched run and passed when run
  alone. Cause not established; S10-06 re-checks it on a clean run.
- Nothing here exercised real hardware, a real install, NVIDIA, or a live
  polkit/PackageKit transaction. Those remain S10-07.

---

## S10-01: Restore the overview model behind type-to-filter and close-from-card

Fixes findings 1, 2 and 3. `OverviewFilter.js` (`filterWindows`,
`excludeIds`), `DwmState.closeWindow()`, `dwm-quickshell-state close`,
`OverviewCard.closeRequested` and the `WindowOverview.qml` search box all
exist. Only the model that connects them is missing.

**`config/quickshell/overview/OverviewModel.qml`**

Add the import:

```diff
 import Quickshell
 import "../state/DwmStateWindows.js" as WindowsLib
+import "OverviewFilter.js" as Filter
 import "OverviewSelection.js" as Selection
```

Add the state:

```diff
     property bool visible: false
     property var targetScreen: null
     property int selectedIndex: 0
+    property string query: ""
+    // Window ids a card close was requested for. Filtered out immediately
+    // (OverviewFilter.excludeIds) rather than waiting for the next watch
+    // update; reset whenever the popup opens or closes so a window that
+    // refuses to close reappears next time instead of staying hidden.
+    property var closingIds: []
```

Feed `groups` from the filtered list, and keep the selection in range when
the list shrinks:

```diff
-    readonly property var groups: WindowsLib.groupByTag(root.dwmState.windowStates, root.dwmState.monitorWorkspaceRows,
+    readonly property var visibleWindows: Filter.excludeIds(
+        Filter.filterWindows(root.dwmState.windowStates, root.query), root.closingIds)
+
+    readonly property var groups: WindowsLib.groupByTag(root.visibleWindows, root.dwmState.monitorWorkspaceRows,
         root.dwmState.workspaceNames, root.dwmState.monitorCount())
+
+    // Filtering or closing a card can shrink the list under the selection.
+    onFlatCardsChanged: root.selectedIndex = Selection.selectAbsolute(root.selectedIndex, root.flatCards.length)
```

Reset on open/close and add the two functions `WindowOverview.qml` calls:

```diff
     function open(screen) {
         root.targetScreen = screen || null;
         root.selectedIndex = 0;
+        root.query = "";
+        root.closingIds = [];
         root.visible = true;
     }

     function close() {
         root.visible = false;
+        root.query = "";
+        root.closingIds = [];
+    }
+
+    function setQuery(value) {
+        root.query = value;
+        root.selectedIndex = 0;
+    }
+
+    // Close a card's window without closing the popup: hide the card now,
+    // then ask dwm-quickshell-state to send WM_DELETE_WINDOW.
+    function closeCard(windowId) {
+        root.closingIds = root.closingIds.concat([windowId]);
+        root.dwmState.closeWindow(windowId);
     }
```

**`tests/test-quickshell-overview.sh`** -- the existing pin hard-codes the
old `groupByTag(root.dwmState.windowStates,` call, and, more importantly,
nothing checked that the members the popup uses are defined. Replace the
one line and add a check that would have caught this bug:

```diff
-grep -Fq 'WindowsLib.groupByTag(root.dwmState.windowStates,' "$overview/OverviewModel.qml"
+grep -Fq 'WindowsLib.groupByTag(root.visibleWindows,' "$overview/OverviewModel.qml"
+# The filtered list must still start from windowStates (never the renamed-away
+# `windows`), and every member WindowOverview.qml and OverviewCard.qml read off
+# the model must actually be defined on it. A member used but never defined
+# (query, setQuery, closeCard) shipped once already and only failed at runtime.
+grep -Fq 'Filter.filterWindows(root.dwmState.windowStates, root.query)' "$overview/OverviewModel.qml"
+grep -Fq 'import "OverviewFilter.js" as Filter' "$overview/OverviewModel.qml"
+undefined_members=$(grep -ohE 'overviewModel\.[A-Za-z_]+' "$overview"/*.qml | sed 's/^overviewModel\.//' | sort -u |
+	while IFS= read -r member; do
+		case $member in dwmState) continue ;; esac
+		grep -Eq "(property [a-z]+ $member\b|function $member\()" "$overview/OverviewModel.qml" || printf '%s\n' "$member"
+	done)
+if [ -n "$undefined_members" ]; then
+	printf 'OverviewModel.qml does not define what the overview QML uses:\n%s\n' "$undefined_members" >&2
+	exit 1
+fi
```

(The script is POSIX `sh`; the loop is written without `[[` or process
substitution so `check-shell` stays clean.)

**Validated.** With exactly the changes above these pass:
`check-quickshell-overview`, `check-quickshell-queued-run-xvfb`,
`check-quickshell-picom-model-xvfb`,
`check-quickshell-settings-responsiveness-xvfb`,
`check-quickshell-update-progress-xvfb`,
`check-quickshell-wallpaper-reconcile-xvfb`, `check-quickshell-qml`,
`check-shell`, `check-format`. Mutation check: the new pin **fails** (rc=1)
when run against `main`'s unmodified `OverviewModel.qml`.

Behaviour (typing in the box, clicking a card's close button) is checked
model-level by S10-04, not by simulated key or mouse events.

Known trade-off: `closingIds` is only cleared on open/close, so a window
that ignores `WM_DELETE_WINDOW` stays hidden until the popup is reopened.
Acceptable for a first cut; note it in the CHANGELOG entry (S10-05).

## S10-02: Repair the command-menu pin that the overview popup broke

Fixes finding 4. #135 changed `shell.qml`'s launcher block from
`if (visible) commandMenuModel.close();` to a two-line block that also closes
the overview:

```qml
        onVisibleChanged: {
            if (visible) {
                commandMenuModel.close();
                overviewModel.close();
            }
        }
```

The test only cared that opening the launcher closes the command menu. Pin
that, not a formatting:

```diff
-grep -Fq 'if (visible) commandMenuModel.close();' "$shell"
+launcher_visible_body=$(awk '/LauncherModel \{/{f=1} f&&/onVisibleChanged/{g=1} g{print} g&&/^        \}/{exit}' "$shell")
+printf '%s\n' "$launcher_visible_body" | grep -Fq 'commandMenuModel.close();'
```

Validated in the same worktree: `check-quickshell-command-menu` passes. Also
extend the pin so the overview is covered the same way, since the launcher
now closes it too:

```diff
 printf '%s\n' "$launcher_visible_body" | grep -Fq 'commandMenuModel.close();'
+printf '%s\n' "$launcher_visible_body" | grep -Fq 'overviewModel.close();'
```

Both lines run and pass under `sh tests/test-quickshell-command-menu.sh`.

## S10-03: Run the tests that make check never ran

Fixes findings 5 and 6.

**Three passing xvfb targets.** Run on this host inside a batched run, all
three passed (`Health navigation tests: PASS (15 assertions)`,
`Information UI tests: PASS (31 assertions)`,
`Quickshell System Health Xvfb: PASS`). Add them to the `check` recipe beside
their siblings:

```diff
 	$(MAKE) check-quickshell-update-ui-xvfb
+	$(MAKE) check-quickshell-health-navigation-xvfb
+	$(MAKE) check-quickshell-information-ui-xvfb
+	$(MAKE) check-quickshell-health-xvfb
 	$(MAKE) check-quickshell-notifications
```

**The container-only display-helper security test.** It needs root, a
disposable container (`/.dockerenv` or `/run/.containerenv`) and
`DWM_SECURITY_CONTAINER=1`, so it cannot run inside the existing
`full-suite` job (which drops to `nobody`). Give it a target that honours
the repository's exit-77 skip convention (as `check-quickshell-queued-run-xvfb`
does):

```make
.PHONY: check-settings-display-security
check-settings-display-security:
	@tests/test-settings-display-security.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status
```

and add a job to `.github/workflows/full-suite.yml`, after `full-suite` and
before `clang-build`, that runs it as root:

```yaml
  display-security:
    name: display helper security (root, disposable container)
    runs-on: ubuntu-latest
    timeout-minutes: 20
    container: archlinux:base-devel
    env:
      DWM_SECURITY_CONTAINER: "1"
    steps:
      - name: Install checkout dependency
        run: pacman -Syu --noconfirm --needed git

      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Run the display helper security test
        run: make check-settings-display-security
```

**Validated.** `make check-settings-display-security` skips cleanly (exit 0)
outside a container. Inside a disposable local container it passes:

```text
$ docker run --rm --network none -e DWM_SECURITY_CONTAINER=1 \
    -v "$PWD":/work:ro -w /work archlinux:base-devel \
    make check-settings-display-security
Privileged display-helper trust and authorization denial: PASS
```

It needs no extra packages and no network, so the job has no dependency
step. The workflow file parses as YAML; the job itself has not yet run on
GitHub (that is S10-06).

## S10-04: Drive the overview through real input under Xvfb

Fixes finding 8. Sprint 8's plan requires xvfb interaction cases and none
existed; `tests/test-quickshell-overview.sh` only greps source, which is how
finding 1 got through.

Added `tests/test-quickshell-overview-xvfb.sh`,
`tests/qml/OverviewInteraction.qml` and `make check-quickshell-overview-xvfb`
(wired into `check`), following the Health navigation harness: a stub
`ShellRoot` loads the **real** `OverviewModel`, the real libraries and the
real `WindowOverview` popup (on a real `PanelWindow`) against a stub
`dwmState`, and the script fails on `TypeError:`, `ReferenceError:`,
`Unable to assign` or `Binding loop` in the log.

22 assertions cover: the popup loads clean; cards in tag order; filtering by
class, by title, case-insensitively; a tag with nothing left is absent; no
match gives no groups and Enter does nothing; clearing restores everything;
selection moves and wraps within the filtered list; closing a card asks dwm
to close it, hides the card at once, clamps the selection and keeps the
popup open; a window vanishing while open drops its card and Enter acts on
the survivor, not a stale id; close and reopen start clean.

**Mutation-checked.** It fails against `main`'s unfixed model (reproducing
the original `Unable to assign` and `TypeError`), against a model without the
selection clamp, and against a model whose `closeCard` does not hide the
card. It passes against the fixed model.

**Not covered:** real key presses and mouse clicks are not simulated; the
handlers' model calls are exercised directly. The multi-monitor label (S8-02)
is not tested (a single stub monitor), and `xdotool` input into the popup was
not attempted because a `PopupWindow` with `grabFocus` under Xvfb without a
window manager is unlikely to receive focus reliably. Do not treat those
three as verified.

## S10-05: Backfill Sprint 7 and 8 tracking

Fixes findings 8, 9 and part of 10. `UPSTREAM-SYNC.md` requires each item
to land `TASKS.md`, `CHANGELOG.md` and `docs/evidence/` in the same PR. Add
them now, from what is true.

**`CHANGELOG.md`** -- under "Added", three entries (adjust after S10-04
runs). First the two Sprint 7 items that never got one:

```md
- `DwmState.qml` exposes the per-window list as `windowStates` and resolves
  each window to a tag and monitor through `DwmStateWindows.js`
  (`windowsByTag()`, `groupByTag()`) (Sync Sprint 7 S7-02, issue `#350`),
  covered by `tests/qml/tst_dwm_state_windows.qml`.
- A cross-tag window overview popup (`config/quickshell/overview/`): one
  card per open window, grouped by tag, click to switch tag and focus the
  window, Escape or click-away to close (Sync Sprint 7 S7-03, issue `#350`).
```

Then the Sprint 8 entry:

```md
- The cross-tag window overview gained multi-monitor labels, type-to-filter
  and close-from-card (Sync Sprint 8 S8-02 to S8-04, issue `#350`).
  `OverviewCard.qml` shows a monitor label only when more than one monitor is
  present; a search box in `WindowOverview.qml` narrows cards by title or
  class through `OverviewFilter.js`; each card has a close button that sends
  `WM_DELETE_WINDOW` through `dwm-quickshell-state close` and hides the card
  at once. The UI half merged in #138 without the model half
  (`OverviewModel.query`, `setQuery()`, `closeCard()`), so the popup logged
  a `TypeError` on load and neither feature worked until Sprint 10 S10-01.
  A window that ignores the close request stays hidden until the popup is
  reopened.
```

**`TASKS.md`** -- replace the unchecked S8-01 bullet under "Parallel Track"
with these, ticking only what has evidence:

```md
- [x] Sync Sprint 8 S8-01 -- overview keyboard navigation, issue `#350`.
  Evidence: `docs/evidence/s8-01-overview-keyboard-nav.md`, including a real
  Qt 6 `qmltestrunner` run.
- [ ] Sync Sprint 8 S8-02 to S8-04 -- monitor labels, type-to-filter and
  close-from-card. Not done until Sprint 10 S10-01 (model) and S10-04
  (xvfb interaction tests) land; then record the Full suite run URL.
```

**`docs/evidence/s8-01-overview-keyboard-nav.md`** -- append the run the file
said was missing. Measured 2026-09-25 on CachyOS with Qt 6:

```text
$ QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
Totals: 148 passed, 0 failed, 0 skipped, 0 blacklisted
  OverviewSelection 11, OverviewFilter 12, DwmStateWindows 22,
  PanelTooltipPosition 9, DisplayLayout 9, SystemDiscoveryCycle 16,
  SystemInformationProtocol 17, SystemOperationProtocol 18,
  SystemRegionalPreflightProtocol 34
```

Note in that file that plain `qmltestrunner` on Arch/CachyOS hosts with Qt 5
also installed is the Qt 5 binary and reports failure with no output; the
repository's own harness (`tests/test-quickshell-system-discovery-cycle.sh`)
already uses `/usr/lib/qt6/bin/qmltestrunner` for that reason.

Also record there that #125 was closed before this evidence existed.

## S10-06: Get the Full suite green on main and record it

Fixes finding 7. Requirements: S10-01 to S10-03 merged.

**Local result with S10-01 to S10-04 applied** (2026-09-25, CachyOS, this
branch, `scripts/run-tests make check`): every target now runs to the end
except one. The first stop moved from `check-quickshell-queued-run-xvfb` to
`check-system-management`, which fails only in `RepositoryReadTests` (14
errors and 1 failure) because this host has no `packagekit`
(`gi.require_version("PackageKitGlib", ...)` raises). The 28 targets after it
in the recipe were run separately and all pass. See the CI-image result
below for the same suite where `PackageKitGlib` exists.

**CI-image result.** The local `lyona-ci` Docker image has `packagekit`
and its Python bindings. `tests/test-system-management.py` there ran 686
tests with 0 errors and 1 failure; the failure
(`RegionalInterruptionTests.test_actual_cli_signal_matrix_on_private_bus`)
was caused by running it outside `scripts/run-tests`, which sets
`DWM_TEST_WORKSPACE` (`KeyError: 'DWM_TEST_WORKSPACE'`), and it passes when
that variable is set. So on this evidence the suite is clean wherever
`PackageKitGlib` exists; the `check-system-management` stop on this host is
the host, not the repository. That is inference from a partial rerun, not a
full `run-tests` pass in that image.

Still to do, after merge:

1. `scripts/run-tests make clean all check-shell check-format check-quickshell-qml`.
2. Start **Actions -> Full suite (manual)** on `main` (default target
   `check`). It now also runs the `display-security` job. Record the URL in
   `CHANGELOG.md` and the S8-01 evidence.
3. If `check-system-management` fails in the CI container on
   `PackageKitGlib`, add `packagekit` to the workflow's package step (and to
   `dwm_packages arch` if it is a real test dependency); do not skip it.
4. Re-run `check-session-guards` in that clean run. It failed once inside a
   batched run during the audit and passed alone and in the full branch run;
   open an issue if it recurs.

Done when a Full suite run on `main` is green and its URL is recorded.
Until then no sprint may cite "Full suite passed".

## S10-07: Qualification ledger for sprints closed with hardware checks open

Fixes finding 11. These are recorded as open in the sprint docs and
`ROADMAP.md` but no open issue or task tracks them. None can be done without
real hardware, a real install or elevated access; this item only makes them
visible so a closed milestone stops implying they happened.

| From | Check | Needs | Evidence to record |
| --- | --- | --- | --- |
| S1-10 / D-4 | `pacman -Sup --dbpath "$CHECKUPDATES_DB"` stays read-only (no root, no live `pacman.lck`) | Real CachyOS install; `strace -f -e trace=openat,flock` | Result in `UPSTREAM-SYNC.md` "Open decisions" |
| S4-01 | Picom NVIDIA backend | NVIDIA hardware | Backend chosen, tearing/flicker notes |
| S4-02 | Media/image defaults on a fresh install, both ISOs | Fresh installs of standard and NVIDIA ISO | `xdg-mime query` output |
| S4-06 | Full privileged `lyona-update` run | Real installed system | Before/after version, rollback result |
| S5-01, S5-03 | Settings panes stay put while loading; floating toggles shrink to 85% | Real desktop, slow provider | Short manual log |
| S5-02 | `install-gearlever` refuses an unverified Flathub remote | Real Flatpak setup | Command output |
| Phases 5, 6 | Fresh LightDM login; multi-monitor rendering; live PackageKit transaction; live polkit denial | Real hardware | Per `ROADMAP.md` limitations |
| Phase 7 | Already tracked in `TASKS.md` ARCH-001 to ARCH-004 | -- | -- |

Decided: the closed issues (#43, #67 and the closed milestones) stay
closed. This table is the tracker for the checks they left open, and
`TASKS.md` links here.

## S10-08: Correct the status tables

Fixes findings 10 and 11. **Already applied** in the change that introduced
this document: the corrected Sprint 7 and 8 rows, the Sprint 10 rows in both
`UPSTREAM-SYNC.md` tables, and the matching `sync-sprints-github.sh` arrays
(not run). What remains here is updating those rows as items land, plus the
Sprint 4 and 5 pointers and the two housekeeping decisions below. The diff
applied to `docs/UPSTREAM-SYNC.md`:

```diff
-| **Sprint 7** (...) | 📋 **Not started.** Cross-tag window overview (issue `#350`, no upstream code), version-one foundation: per-window data, `DwmState.qml` resolution, a mouse-only popup |
+| **Sprint 7** (...) | 🚧 **Code merged (#134, #135); verification gaps.** The popup shipped with `check-quickshell-command-menu` red (S10-02) and a model that fails at load once Sprint 8's UI landed (S10-01) |
-| **Sprint 8** (...) | 📋 **Not started.** Same feature: keyboard navigation, multi-monitor labels, a window closing mid-use, plus type-to-filter and closing a window from its card |
+| **Sprint 8** (...) | 🚧 **Partly delivered.** S8-01 merged (#137). S8-02 to S8-04 merged as UI only (#138); the model is missing, so filter and close do not work (S10-01), and no interaction tests exist (S10-04) |
```

Add a Sprint 10 row to both the status table and the sprint plan table,
and extend the "Sprints 7-9 exist because ..." paragraph with one sentence
on Sprint 10. Adjust the Sprint 4 and 5 rows to point at S10-07 for their
open qualification items.

Housekeeping, **decided**: sprint documents are kept. No sprint document
has been removed (only the earlier phase-numbered plans were), so Sprints 1
to 3 keep theirs, and `UPSTREAM-SYNC.md`'s convention paragraph now says so.

Also close issue #117 (S6-04) as superseded by Sprints 7 to 9 once S10 lands,
and leave #116 (S6-03) open: it needs a maintainer screenshot.

`docs/sync-sprints-github.sh` needs the matching arrays, so the milestone
and issues can be created (do not run it without confirming):

```diff
 	"9|Sync Sprint 9 -- Cross-tag overview: polish|SYNC-SPRINT-9-OVERVIEW-POLISH.md"
+	"10|Sync Sprint 10 -- Completion audit|SYNC-SPRINT-10-COMPLETION-AUDIT.md"
```

```diff
 	"9|S9-04|s9-04-idle-cpu-and-many-window-performance|Idle-CPU and many-window performance|issue #350"
+	"10|S10-01|s10-01-restore-the-overview-model-behind-type-to-filter-and-close-from-card|Restore the overview model behind type-to-filter and close-from-card|audit"
+	"10|S10-02|s10-02-repair-the-command-menu-pin-that-the-overview-popup-broke|Repair the command-menu pin that the overview popup broke|audit"
+	"10|S10-03|s10-03-run-the-tests-that-make-check-never-ran|Run the tests that make check never ran|audit"
+	"10|S10-04|s10-04-drive-the-overview-through-real-input-under-xvfb|Drive the overview through real input under Xvfb|audit"
+	"10|S10-05|s10-05-backfill-sprint-7-and-8-tracking|Backfill Sprint 7 and 8 tracking|audit"
+	"10|S10-06|s10-06-get-the-full-suite-green-on-main-and-record-it|Get the Full suite green on main and record it|audit"
+	"10|S10-07|s10-07-qualification-ledger-for-sprints-closed-with-hardware-checks-open|Qualification ledger for sprints closed with hardware checks open|audit"
+	"10|S10-08|s10-08-correct-the-status-tables|Correct the status tables|audit"
```

---

## Verification (whole sprint)

```bash
scripts/run-tests make clean all check-shell check-format check-quickshell-qml
scripts/run-tests make check-quickshell-overview check-quickshell-overview-xvfb \
  check-quickshell-command-menu check-quickshell-queued-run-xvfb \
  check-quickshell-picom-model-xvfb check-quickshell-settings-responsiveness-xvfb \
  check-quickshell-update-progress-xvfb check-quickshell-wallpaper-reconcile-xvfb \
  check-quickshell-health-navigation-xvfb check-quickshell-information-ui-xvfb \
  check-quickshell-health-xvfb
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
scripts/run-tests make check      # must reach the end
```

Then the **Full suite (manual)** workflow on `main` (S10-06). Run
`quickshell --no-duplicate` in a real or nested X11 session with the overview
open and confirm the log has no `TypeError` and the process is near idle
with the popup closed (`AGENTS.md`).

## Not in this sprint

New overview features (Sprint 9), the Arch image and release work in
`TASKS.md` ARCH-001 to ARCH-004, and any hardware qualification itself
(S10-07 only makes it visible).
