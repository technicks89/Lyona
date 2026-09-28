# S12-07 -- watchers stop polling for their parent

Plan: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-07-watchers-stop-polling-for-their-parent`.
Issue `#170`.

## Change

`scripts/dwm-watchdog.sh`, `run_parent_bound`, used by four always-on watchers:
`nmcli monitor` (network), `pactl subscribe` (audio), `playerctl --follow` (media) and
`power_watch_sources` (control center).

- **Before.** Every 0.25 s a subshell ran `sed`, `awk` and `sleep` to check the
  helper's parent (Quickshell): about 12 process starts and 4 wake-ups a second, per
  watcher.
- **A program child now runs as `setpriv --pdeathsig TERM -- CMD`** (util-linux, in
  Arch `base`). The kernel sends it SIGTERM as soon as the helper shell exits,
  including by SIGKILL, which is what a killed `QProcess` gets. No polling is
  involved.
- **A shell-function child** (`power_watch_sources`) cannot be exec'd, so it runs as
  before. Its own `EXIT` trap already ends its children on SIGTERM.
- **The remaining loop is only a backstop**, for Quickshell dying without taking its
  helpers along (a crash).
  - It reads `/proc/PID/stat` with shell builtins (`read`, `set --`); the state and
    start time are the same fields as before, now shared as `parent_bound_record`.
  - It sleeps `$LYONA_PARENT_BOUND_INTERVAL` seconds between checks (default 5), so a
    tick costs one `sleep` and nothing else.
  - The loop and its `sleep` are both bound to the helper by pdeathsig, so neither can
    outlive it. Found while testing: without that, a stopped loop left its `sleep`
    running for the rest of its interval.
- **Start-up race (review).** `setpriv` arms the signal and then execs, so a helper that
  died in between would never send it. Each bound process (child, loop, the loop's
  `sleep`) therefore starts through `parent_bound_guard`, which, with the signal armed,
  checks `$PPID` is still the shell that started it (read from `/proc/self/stat`, so
  right in a subshell too) and exits if not, then execs the command.
- **Interval (review).** `LYONA_PARENT_BOUND_INTERVAL` must be a positive number of
  seconds; zero (`0`, `0.0`, `00`) or a malformed value (`1.2.3`, `5.`, `.5`, text,
  empty) falls back to 5 instead of making the loop spin.
- **Without `setpriv`,** both still run, as a plain child and a plain loop.
- **Trade-off.** A Quickshell crash is noticed within 5 s instead of 0.25 s. Until
  then the orphaned watcher sits blocked and costs nothing.

QML (the plan's other two points):

- `ControlsModel.qml`: when `media-watch` reports "MEDIA unavailable" (no
  `playerctl`), `mediaWatchUnavailable` is set and the watcher is not restarted.
  Before, it was restarted every 3 s for the whole session. A shell restart looks
  again.
- `NetworkModel.qml`:
  - Monitor lines restart a 300 ms settle timer instead of calling `refresh()` each,
    the way `BluetoothModel` already did.
  - A `refresh()` asked for while a snapshot is running is kept (`refreshPending`,
    also keeping any rescan request) and run when the snapshot ends. Before, it
    returned early and the change was lost.

Not done: moving media to Quickshell's native Mpris service. `playerctl` stays.

## Results (2026-09-27, CachyOS, working tree, nothing committed)

- **`tests/test-dwm-watchdog.py`** (new, `make check-dwm-watchdog`): PASS.
  - A fake parent that outlives its helper, as Quickshell does, starts a helper that
    sources the watchdog. Checked:
    - the child's status is returned;
    - SIGKILL on the helper ends the child, and the backstop loop and its `sleep`,
      within 1.5 s;
    - a crashed parent ends the child and the helper;
    - a function child is cleaned up on SIGTERM;
    - idle, no process at all starts in 3 s;
    - the guard runs the command under its starting parent and refuses under another;
    - zero and malformed intervals resolve to 5, `0.2` and `10` are kept.
  - Mutations caught: a guard that never refuses; the old interval check (accepted
    `0`, `5.`, `1.2.3`).
  - Against the old watchdog it fails: "the child outlived a SIGKILLed helper". With
    that case removed, it also fails idle: 12 process starts in 3 s, and the sampling
    at 20 ms undercounts.
- **`tests/test-quickshell-watchers-xvfb.py`** (new, `make check-quickshell-watchers-xvfb`):
  PASS three times running.
  - It loads the real `NetworkModel` and `ControlsModel` against stub helpers that log
    every call. Checked:
    - `media-watch` is started once in 12 s;
    - six monitor lines in 50 ms cause one snapshot;
    - a line arriving during a 1 s snapshot causes a second snapshot afterwards.
  - Against the old models it fails: media started 4 times; and, with the old network
    model alone, the mid-snapshot change dropped (1 snapshot, not 2).
  - The burst check does not tell the old model apart: it also ended up with one
    snapshot, by dropping the other five lines rather than debouncing them.
- **`tests/test-quickshell-idle-watchers-xvfb.py`** (new, review; `make
  check-quickshell-idle-watchers-xvfb`, 10 s): the plan's full-shell check. dwm runs
  under Xvfb and its autostart starts the managed Quickshell with the repository's
  helpers; after 8 s of start-up it sums the CPU of everything Quickshell started,
  including children it reaped, and counts process starts.
  - `DWM_IDLE_WATCHERS_SECONDS=30`: **0.07% of a core**, 6 process starts (all the
    backstop `sleep`), within 0.5 points of zero: PASS. Resident: `xprop` 2, `nmcli` 1,
    `inotifywait` 1, `sh` 3, `bash` 1, `sleep` 1.
  - Same run with the original watchdog (`802289a`): **1.70%**, 120 process starts
    (118 `sleep`): FAIL.
  - 10 s default in `make check`: 0.00%, 2 starts: PASS.
- **Existing tests.** `tests/test-quickshell-network.sh` and
  `tests/test-quickshell-power-backend.sh` crash a watcher's owner and expect cleanup
  within a 2-5 s window. They now set `LYONA_PARENT_BOUND_INTERVAL=0.2`, because the
  default backstop is 5 s; they test the mechanism, not the latency.
  - `check-quickshell-network`, `-connectivity`, `-controls`, `-controlcenter`,
    `-audio`, `-power-backend`, `check-shell`, `check-format` and
    `check-quickshell-plain-text`: PASS.
  - `check-quickshell-qml`: the same 21 warnings as `main`, none in the two changed
    models.

## Not verified

- **Idle CPU on real hardware.** Measured under Xvfb with the full shell (above), not
  in a session on a physical display; the watchers do not depend on the display.
- **The path without `setpriv`.** Both halves fall back to plain processes; that path
  was not run.
