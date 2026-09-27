# S11-04 -- xvfb runtime test no longer notifies the real desktop

Plan: `docs/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md#s11-04`. Issue `#155`.

## Change

`tests/test-xvfb-runtime.sh` puts a fake `notify-send` first on the `PATH` dwm is
launched with, logs its arguments to `$work/notifications.log`, and asserts:

- nothing was logged after the default configuration and the valid reload;
- after the deliberately invalid `hotkeys.toml`, the log contains
  `-u critical dwm: bad config hotkeys.toml: invalid config - loaded defaults`.

## Results (2026-09-26, CachyOS, working tree, nothing committed)

- `scripts/run-tests make check-xvfb-runtime`: `Xvfb runtime smoke: PASS` (17 s).
- `shellcheck`: 2 findings, the same 2 as the file before the change. `shfmt -d`: clean.
- Mutation: expecting a different message fails with
  `missing captured invalid-config notification`. Pre-seeding the log so a
  "valid" configuration appears to notify fails with
  `a valid configuration emitted a notification`. Both exit 1, both with the
  fake still in place, so neither could reach the desktop.
- dwm reported the invalid file twice per run (its file watcher and the test's
  `USR1` each reload it), so the assertion is "at least once".

## Other tests

Twelve tests launch the dwm binary. None other than this one writes an invalid
`hotkeys.toml`, `themes.toml` or `window-rules.toml` (checked by reading their
config writes; the settings test only appends comments, which stay valid TOML),
and `test-quickshell-large-surfaces-xvfb.sh`, which calls `notify-send` on
purpose, does so on its own bus. So this was the only test that could leak.

## Not verified

That the notification no longer appears on a live desktop was not observed
directly; it follows from the fake being first on dwm's `PATH` and from the
captured line above. Run `make check-xvfb-runtime` once on a live desktop and
watch for a popup.
