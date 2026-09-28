# S12-10 -- power and memory defaults

Plan: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-10-power-and-memory-defaults`.
Issue `#173`. Decision D-13: after 10 minutes idle the screen turns off and the
desktop locks.

## Change

1. **The screen turns off and the desktop locks when idle, by default.**
   - `scripts/dwm-quickshell-controlcenter` `read_power_config` now defaults
     `power_dpms_enabled=1` and `power_lock_enabled=1`; the timeouts stay at 600 s,
     with a 5 s lock grace.
   - `power-apply` then runs `xset +dpms`, `xset dpms 600 600 600` and `xset s 600`,
     sets light-locker's `lock-after-screensaver 5` and `lock-on-suspend true`, and
     starts light-locker. Moving the mouse in the 5 s grace cancels without a password.
   - A value saved in `~/.config/lyona/power.conf` still wins: the defaults apply only
     to keys that were never saved, so a user who turned either off keeps it off.
   - With no Control Center helper, `scripts/autostart.sh` now blanks the screen at
     600 s (`xset s 600`, `+dpms`, `dpms 600 600 600`) instead of turning blanking off.
     Locking needs light-locker, which only the helper starts.
   - **No double prompt.** `dwm-lock`, the explicit lock action, locks through
     `light-locker-command` and starts light-locker only if none is running, so it
     reuses the one `power-apply` started.
   - **Limit:** light-locker locks through LightDM, Lyona's display manager. In a
     `startx` session the screen still turns off, but the automatic lock does not
     happen. `docs/src/control-center.md` and the CHANGELOG say so.
   - `docs/src/control-center.md` describes the defaults. The CHANGELOG has the
     migration note (AGENTS.md: a changed default needs one).
2. **A leaner Picom default:** tabled on 2026-09-28, asked of the user directly. It
   changes how the desktop looks and needs a by-eye check on real hardware.
3. **Releasing Settings panes after Settings closes:** built, measured, then dropped
   on 2026-09-28, asked of the user directly (below).

## Results (2026-09-28, CachyOS, working tree, nothing committed)

- **`tests/test-quickshell-controlcenter.sh`:** the first `power-apply` runs with no
  `power.conf`, and the test now checks the D-13 defaults it applies:
  `xset +dpms`, `xset dpms 600 600 600`, `xset s 600`, light-locker's 5 s grace and
  lock on suspend, `power-status` reporting both as on, and still no `power.conf`
  written. Against the old defaults it fails.
  - The existing tests all passed unchanged before this. They save explicit values,
    so none of them covered the no-saved-config case.
- **`tests/test-autostart.sh`:**
  - A display-manager session now starts light-locker exactly once. The test used to
    assert that it did not start at all.
  - New case: `apply_power_settings` run on its own, with no helper beside it and a
    `PATH` holding only a logging `xset`. It must run `s 600`, `+dpms` and
    `dpms 600 600 600`. The old code ran `s off`, `s noblank` and `-dpms`, and fails.
- `check-quickshell-controlcenter`, `check-quickshell-power-backend`,
  `check-quickshell-power-model`, `check-session-guards`, `check-shell` and
  `check-format`: PASS.

### Item 3, measured

The change was built before it was dropped:
- `DeferredSettingsPane` released a visited pane 5 minutes after Settings closed.
- Each pane reported `hasUnsavedInput`, and such a pane was kept:
  - Appearance: an edited theme, wallpaper, font or toolkit choice, or an unapplied
    Picom change;
  - Display: a typed profile name;
  - Input: edited row values;
  - System: a picked timezone or locale, or a pending confirmation.
- A Quickshell test of the mechanism passed and failed against both mutations (never
  releasing, and ignoring unsaved input).
- In the full shell, a debug build logged all 9 panes released after closing.

Quickshell's RSS, full shell under Xvfb (dwm autostart, the repository's helpers):

| | Idle | Every section opened | 15 s after closing (panes released) |
|---|---|---|---|
| With the release | 156 MiB | 183 MiB | 183 MiB |
| `main` (no release) | 152 MiB | 178 MiB | 179 MiB |
| With the release and `gc()` after it | 158 MiB | 184 MiB | 184 MiB |
| The same, eager glibc trimming (`trim_threshold=65536`, `arena_max=2`) | 153 MiB | 179 MiB | 179 MiB |

The memory stays with the QML engine (compiled component types, the JS heap and the
allocator), not with the pane objects, so unloading them gave nothing back. The cost
would have been a reload ("Loading settings...") and lost scroll positions after 5
minutes closed. The review's 289 to 418 MB came from a different environment; here
opening Settings adds about 26 MiB.

### Full suite

`scripts/run-tests`: PASS, after two fixes to S12-09's
`tests/test-quickshell-watcher-lifetime-xvfb.py`, which failed under `run-tests`.
Neither failure came from this item: the first also failed with `main`'s power
scripts.

- **IPC socket path.** Quickshell's IPC socket lives under `XDG_RUNTIME_DIR`. With
  `run-tests`' deeper workspace the path reached 107 characters, the Unix socket limit,
  so `quickshell ipc` found no server (`ServerNotFoundError`). The test's folder is now
  `lifetime-` with runtime folder `rt`, 13 characters shorter. Opening Settings also
  retries for up to 30 s.
- **A one-shot in flight.** Under the suite's load, a `dwm-system-management
  snapshot` (run through `checkedCommand`) was still running when Quickshell was
  killed. It is bounded by its own timeouts and ends on its own. Known one-shots (that
  wrapper and `snapshot`) now get 20 s, and the test fails if one is still running
  then. Everything else, the resident watchers included, still has to be gone within
  3 s.

## Not verified

- **On a real display:** the screen turning off and the desktop locking after 10
  minutes idle, with a real light-locker and LightDM. The tests use stubs for `xset`,
  `gsettings` and light-locker.
- **The `startx` behaviour** (screen off, no automatic lock) is from how light-locker
  works, not a run.
