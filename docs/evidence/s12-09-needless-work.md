# S12-09 -- stop needless work on events

Plan: `docs/sprints/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-09-stop-needless-work-on-events`.
Issue `#172`. Items 5 and 6 were added on 2026-09-28, from a cleanup of this
repository's test leftovers in `~/tmp` and `/tmp`.

## Change

1. **`dwm-status` publishes the power state only, and only when it changes.**
   - The volume half (`volume_text`, the `pactl subscribe` source and its restart
     handling) is gone. The shell has its own volume and network models, and
     `DwmState.qml` already dropped the `VOL` and `NET` segments. Nothing else reads
     `WM_NAME` for them (checked: QML, scripts, diagnostics, tests).
   - `WM_NAME` is `BAT 82% Discharging` or `AC`, written only when it differs from
     the last write. Every write wakes the shell's state bridge (S12-08).
   - **Found while planning:** the periodic rewrite was also how an orphaned
     `dwm-status` noticed that its X server had gone. The Xvfb smoke test, which kills
     dwm rather than quitting it, left one running. On a tick with nothing new, it now
     reads `WM_NAME` back with `xprop`, and exits when that fails. The 30 s tick
     stays: battery capacity is a sampled value.
   - **Review:** if the value read back differs (another client wrote `WM_NAME`), it
     writes the power state again. New test case: after an outside overwrite, the name
     is restored exactly once. A version that ignores the value read back fails it.
   - `tests/test-dwm-status.sh`: the restart and churn cases now drive the `udevadm`
     source, which shares the restart code. New cases: three ticks with the same
     battery write nothing (but do check the display), and a lost display makes it
     exit within 3 s, taking its providers along.
2. **A config reload runs `theme-apply.sh` only when it is needed** (`dwm.c`).
   `reload_config(int applytheme)`: start-up and `SIGUSR1` (an explicit request) apply
   the theme; an inotify reload applies it only if `themes.toml` is among the changed
   files. `hotkeys.toml` and `window-rules.toml` changes reload without it.
3. **The dwmblocks support is removed** (`dwm.c`, `config.def.h`): `STATUSBAR`,
   `statuspid`, `statussig`, `getstatusbarpid()`, with its `popen("pidof -s
   dwmblocks")` in the event loop, and the `sigstatusbar` hotkey function. Nothing
   bound it and Lyona does not ship dwmblocks. A user `hotkeys.toml` naming
   `sigstatusbar` would now get dwm's unknown-function message for that binding.
   dwm has no `popen` left.
4. **`dwm-window-thumb` drops the `XSync` after each `XGetImage`.** `XGetImage`
   already waits for its reply, and an error for it reaches the error handler before
   it returns, so the per-row `x_error` check stays and costs nothing.
5. **Tests leave nothing behind.**
   - `scripts/quickshell-qmllint` ended with `exec "$qmllint"`, which skipped its
     `EXIT` trap: every `make check-quickshell-qml` left a `tmp.*/qs` import tree (114
     in `/tmp`). It now runs `qmllint` and exits with its status. Its `HUP`/`INT`/`TERM`
     traps used to delete the tree and carry on; they now exit.
   - Workspaces go under `${DWM_TEST_TMP_ROOT:-$HOME/tmp}` for a test run on its own
     too. `tests/lib.sh` sets `TMPDIR` to that root when it is unset, and so does the
     new `tests/lyona_tmp.py`, imported by the ten Python tests that used Python's
     default. `scripts/run-tests` already set `TMPDIR`. `scripts/ci-local.sh` keeps its
     log folder (it prints the path) but puts it under the same root.
   - `tests/lib.sh` gains `kill_session_tree HOME`: it stops every process whose
     environment has the test session's own `HOME` (TERM, then KILL after 2 s), and
     refuses the test's own `HOME`, `/` and an empty path. The smoke, Settings and
     system-management Xvfb tests call it in their cleanup. It reaches what stopping
     dwm and Quickshell does not: autostart's detached children, helpers orphaned by a
     killed Quickshell, and D-Bus services started for the session.
   - **Found through the leftovers (production bugs):**
     - `dwm-settings-display discover` removed its four temp files (`xrandr` output
       and capabilities) with a `RETURN` trap, but its error path calls `die`, which
       exits, and a `RETURN` trap does not run on exit. They now live in one folder
       removed on return or exit.
     - `dwm-settings-input` wrote `xinput` output to bare `mktemp` files; an action
       stopped part-way through a scan left them. Every action except `watch` now
       works in a scratch folder removed on exit, and `HUP`/`INT`/`TERM` exit through
       that trap (`watch-apply`'s own cleanup removes it too).
     - The display and input watchers' fifo folder (`dwm-settings-*-watch.*`) was left
       by a killed watcher, in the user's `/tmp`. It is now created under
       `XDG_RUNTIME_DIR` (cleared at logout, as `dwm-status` does), and the fifo and
       folder are removed as soon as both ends are open, so even SIGKILL leaves
       nothing.
   - The system-management Xvfb test ran the **installed** display and input helpers
     (its Quickshell had the default `PATH`). It now copies them and puts its scripts
     folder first on `PATH`, as the Settings test does. Helper isolation in general is
     S12-13.
6. **Every resident watcher ends with Quickshell.** `Commands.watchCommand(command)`
   (`core/Commands.qml`) starts a watcher through `setpriv --pdeathsig TERM` and the
   S12-07 guard (after the signal is armed, the parent must still be the Quickshell
   that started it). It wraps all 16 watcher launches:
   - Bluetooth `busctl monitor`, network, audio, media, power, `dwm-quickshell-state`;
   - Picom, appearance inventory, autostart, defaults, accessibility;
   - the display, input and notification-owner watchers in Settings;
   - the system-management provider watchers and `watch-operation`.

   The display and input watchers (`scripts/dwm-simple-watch.sh`) polled their owner
   with `read -t 0.1`, 10 wake-ups a second each. That 0.1 s was also how quickly they
   stopped: their TERM trap only recorded the signal, and bash runs such a trap
   without ending a blocked `read`. Measured: `read -t 5` returned after 5.00 s, and a
   `read` with no timeout never returned, while a trap that calls `exit` took effect
   at once. The traps now exit, and the owner check is a backstop every
   `LYONA_PARENT_BOUND_INTERVAL` seconds (default 5, as in S12-07).

   Their `udevadm monitor` is bound to them too, with the same guard and
   `--pdeathsig KILL`: the monitor has nothing to clean up. The first full-suite run
   found two monitors left behind. Quickshell stops a watcher it no longer needs (a
   Settings section left) without waiting for its cleanup, which orphaned the monitor
   until the next udev event. That was an existing leak, which the lifetime test made
   visible. `tests/test-dwm-display-setup.sh` gains the case: SIGKILL the watcher
   itself, and its monitor must be gone within 1 s. It fails with an unbound monitor.

   One caveat: the kernel sends the parent-death signal when the *thread* that
   started the child exits. Quickshell starts its processes from the main thread,
   which exits only with the process.

## Results (2026-09-28, CachyOS, working tree, nothing committed)

| Check | Before (`main`) | After |
|---|---|---|
| Processes still running 3 s after Quickshell is SIGKILLed (full shell, every Settings section opened; `tests/test-quickshell-watcher-lifetime-xvfb.py`) | 12 of 20 | 0 of 20 |
| `theme-apply.sh` runs for a `window-rules.toml` or `hotkeys.toml` change (`tests/test-dwm-reload-theme-xvfb.py`) | 1 each | 0 (still 1 for `themes.toml` and for `SIGUSR1`) |
| `dwm-status` writes over three unchanged ticks | 3 | 0 |
| `dwm-status` after its display goes away | ran on (stale test sessions) | exits within 3 s, providers stopped |
| Files left by `test-dwm-display-setup.sh` + `test-settings.sh` | 8 | 0 |
| Left by `make check-quickshell-qml` | 1 `tmp.*/qs` tree | 0 |
| Left by the smoke, Settings and system-management Xvfb tests | smoke: `dwm-status` + `udevadm` against a dead display; Settings: a `busctl` stub looping `sleep 1`; system-management: 7 files | 0 processes, 0 files |

The 12 survivors on `main`:
- 6 `dwm-system-management` watchers;
- `dwm-accessibility-settings watch`;
- an `inotifywait` pipeline;
- the network helper with `nmcli monitor`, its S12-07 backstop loop and `sleep`. The
  network helper is S12-07's 5 s crash backstop working as designed; binding it
  directly makes it immediate.

Each new test fails against the old code:
- the reload test against `main`'s `dwm.c` ("rewriting window-rules.toml ran
  theme-apply.sh");
- the `dwm-status` test against `main`'s script, and against a version without the
  display check;
- the lifetime test before the QML change (above).

`tests/test-window-thumb-xvfb.py` passes: the visible and off-tag captures are
unchanged. It is not in the Makefile; S12-12 covers the thumbnail tests.

**Review changes to the lifetime test:**
- A failed `settings select` fails the test.
- Each section with an on-demand watcher must show it within 5 s: display, input,
  the notification owner (`busctl --user monitor`, which `dwm-settings-provider`
  execs), and `dwm-system-management`.
- Before killing Quickshell, the test waits until the process set has not changed for
  2 s. With the quicker walk, a one-shot `dwm-system-management snapshot` was
  sometimes still running at the kill. It is bounded by its own timeouts and gone
  within 20 s, so it is a one-shot, not a resident watcher.
- It still fails with `watchCommand` disabled: 8 processes left.

**Full suite** (`scripts/run-tests`): PASS on the third run, and again after the review
changes.
- The first run failed in `check-display-setup`. Its owner-exit case expects the
  watcher gone within 4 s, and the backstop is now 5 s, so the test (like
  `test-settings-input.sh`) now sets `LYONA_PARENT_BOUND_INTERVAL=0.2`.
- The second run failed in the new lifetime test: the two `udevadm` monitors above.

`check-quickshell-qml`: the same 21 warnings as `main`. The six in changed files
predate this change, on the same lines.

Two source-level tests grepped for the old command lines and now expect the wrapped
form: `test-quickshell-system-management.sh` and `test-quickshell-accessibility.sh`.

## Not verified

- **The round trips saved in `dwm-window-thumb`** were not counted; the plan's
  estimate is about 640 per capture.
- **CPU of the display and input watchers**, before and after, was not measured
  (10 wake-ups a second before, one per 5 s after).
- **`RETURN`-only traps elsewhere.** About 15 other functions (`dwm-settings-toolkit`,
  `dwm-settings-theme`, `dwm-xsettings-config.sh` and others) clean up with a
  `RETURN` trap that does not run if they `die`. Not audited here.
- **One display-watch folder, once.** After the final runs, one
  `dwm-settings-display-watch.*` folder, with its fifo, was left in `~/tmp`. It did
  not reappear in five more runs of the lifetime and display tests. The likely source
  is a watcher killed between creating its fifo and opening it, the one window the
  early unlink cannot cover. With no `XDG_RUNTIME_DIR` (`test-dwm-display-setup.sh`
  sets none) the folder lands in `TMPDIR`. A real session always has
  `XDG_RUNTIME_DIR`, which logout clears.
- **Two more fifo folders under `TMPDIR`.** `dwm-quickshell-state watch` (`tmp.*/events`)
  and the appearance-inventory watcher (`dwm-appearance-inventory.*`) create theirs under
  `${TMPDIR:-/tmp}`. A SIGKILL, which runs no trap, leaves the folder behind. The
  lifetime test's teardown hit this (it now sends TERM first). The display and input
  watchers got the fix (runtime directory, early unlink); these two did not.
- **Preview rollback watchdogs** (`dwm-settings-input _watch`) started by
  `tests/test-settings.sh` outlive the test by their timeout (a few seconds), then
  revert and exit on their own. Unchanged.
