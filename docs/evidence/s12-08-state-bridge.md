# S12-08 -- the state bridge coalesces events and stops forking per window

Plan: `docs/sprints/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-08-the-state-bridge-coalesces-events-and-stops-forking-per-window`.
Issue `#171`.

## Change

Steps 1-3 of the plan. Step 4 (one structured root property from dwm, or an xcb
watcher binary) is not done.

- **`scripts/dwm-quickshell-state` is now bash** (`#!/bin/bash`, `set -euo pipefail`).
  Bash gives `read -t` with a fractional timeout, `EPOCHREALTIME` and an associative
  array. `#!/bin/bash` rather than `env bash`, because `tests/test-quickshell-state-close.sh`
  runs the helper with a PATH holding only its stubs.
  - **Coalescing.** After one event, `drain_events` takes every event that arrives in
    the next 50 ms, then runs one `show_state`. The window is fixed from the first
    event, so a steady stream cannot postpone a rebuild. The deadline strips every
    non-digit from `EPOCHREALTIME`, so a locale with a comma decimal still works.
  - **Per-window watchers.** `sync_client_watchers` keeps one `xprop -spy` per window
    in an associative array. When the client list changes it starts watchers for new
    windows only and stops those of windows that are gone; before, it restarted all of
    them. A new watcher prints the window's properties at once, and a drain after
    starting it takes them into the same rebuild.
  - **Errors under `pipefail`.** `show_state` reads the root snapshot with `mapfile`,
    because command substitution dropped empty trailing fields (the layout and status of
    a bare session), and bash's `read` then failed at EOF. `active_window_id` and the
    client-list read are guarded with `|| true`.
  - **Unset properties.** A property the root lacks prints `NAME:  not found.` (or
    `no such atom on any window.`), and that text used to be parsed as a value. With no
    windows open, that produced `windows=found.:::` (a phantom window) and
    `status=not found.`. Such lines are now skipped. Found while testing.
- **`dwm.c`.**
  - `updatefullscreenmonitors` writes `_DWM_FULLSCREEN_MONITORS` only when the list
    changes, as `updatelayoutprop` does. It is called on every tag switch and every
    client-list update.
  - `setclientdesktop` records the tags and window it last published for each client
    and writes nothing (not `_NET_WM_DESKTOP`, not `DWM_TAG_UPDATE`) when they are
    unchanged. Examples: the monitor re-sort loop, or a move to the tag the window is
    already on. The window is part of the key because swallowing swaps `c->win`. It
    still re-checks the fullscreen list, which a monitor move can change.
- **`DwmState.qml`.** `parseState` keeps the last raw text of each key and skips keys
  whose text has not changed. Views of an unchanged list are no longer rebuilt; before,
  every block reassigned every list.
- **`WindowOverview.qml`.** The card `Repeater` has no model while the popup is not
  visible (`root.visible ? root.overviewModel.groups : []`). `OverviewModel.groups` and
  `flatCards` stay live for the `windowCount` IPC, which is cheap JS. Before, the closed
  popup recreated one card per window on every update.

## Results (2026-09-28, CachyOS, working tree, nothing committed)

- **`tests/test-quickshell-state-bridge-xvfb.py`** (new,
  `make check-quickshell-state-bridge-xvfb`): real dwm under Xvfb, 10 real windows (Tk),
  `dwm-quickshell-state watch` printing one block per rebuild.

  | | Before (`main`) | After |
  |---|---|---|
  | Opening 10 windows (0.3 s apart): rebuilds | 286 | 10 |
  | Opening 10 windows: watcher CPU | 9.12 s in 8.6 s (106% of a core) | 0.31 s in 4.0 s; 3.3% over the 10 s from the first window |
  | Tag switch and back: rebuilds | 3 and 5 | 1 and 1 |
  | 10 title changes, 1 a second: rebuilds | 20 | 10 |
  | Root properties dwm writes for one tag switch | `_NET_ACTIVE_WINDOW`, `_DWM_MONITOR_DESKTOPS`, `_DWM_FULLSCREEN_MONITORS` | the first two |
  | Move a window to the tag it is on: property writes | 2 | 0 |

  - **The plan's 30 s check** (`DWM_STATE_BRIDGE_SECONDS=30`, CPU over the 30 s from the
    first of 10 windows opening): **1.07%** of a core, 10 rebuilds, PASS. The old script
    on the same (new) dwm: **30.17%**, 266 rebuilds, and 2 and 4 rebuilds per tag switch
    (one fewer event than on `main`, because dwm no longer rewrites the fullscreen
    list): FAIL. The review measured 9.7% over the same window with its own
    workload.
  - It also checks that the last block is right: the switched tag, all 10 windows and
    the last title.
  - It checks that SIGTERM, which is how Quickshell stops the watcher, ends it and all
    11 `xprop` watchers. `make check-quickshell-state-bridge-xvfb`: 11 resident, 0 left
    after SIGTERM, PASS.
  - Against the old dwm (with the new script) it fails on the fullscreen rewrite and
    the same-tag move. Against the old script it fails on the rebuild counts.
- **`tests/test-quickshell-state-model-xvfb.py`** (new,
  `make check-quickshell-state-model-xvfb`): the real `DwmState`, `OverviewModel` and
  `WindowOverview` against a stub watcher that sends a state, the same state again,
  then one changed title.
  - An identical state notifies nothing.
  - The title change notifies `windowStates` only (not `runningApps`, the monitor rows,
    the status segments, the names or the active title).
  - Closed, the overview holds 0 cards and counts 6 windows; open, it shows 6.
  - Against the old `DwmState` it fails (every list notifies again). Against the old
    `WindowOverview` it fails (6 cards while closed).
- **Existing tests.** The full suite (`scripts/run-tests`) passed, including
  `check-quickshell-state`, `-state-close`, `-overview`, `check-monitor-tags`,
  `check-xvfb-runtime`, `check-overview-load-xvfb`, `check-overview-keyboard-xvfb`,
  `check-quickshell-overview-xvfb`, `check-quickshell-idle-watchers-xvfb`,
  `check-shell` and `check-format`. `test-quickshell-overview.sh` now greps for the
  gated model. `check-quickshell-qml`: the same 21 warnings as `main`, none in the
  changed files.

## Not verified

- **Multi-monitor.** The `setclientdesktop` cache on the monitor re-sort path, and
  fullscreen changes across monitors, were not run with more than one screen.
- **Step 4** of the plan (a structured root property, or an xcb watcher) is not done.
  A rebuild still costs about N+8 process starts for N windows. Rebuilds are now one
  per burst instead of growing with N squared.
