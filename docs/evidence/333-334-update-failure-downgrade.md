# #333 and #334: the update's failure story and the downgrade wording, validated

Branch `update-failure-downgrade-333-334`, uncommitted, on `main` at `1bfafac`
(PR 1 of 4 from the 2026-10-10 review,
`docs/reviews/2026-10-10-whole-repo-review.md`).

## What changed

- `scripts/lyona-update`: `die` keeps its message in `die_message`, which the
  EXIT trap records as the outcome (with the exit status) instead of the phase
  text; the status before the privileged step names both versions when the
  release is older than the installed one; the helper's exit 3 is told apart
  from a refusal and says to run `lyona-update rollback` with the backup id;
  a dismissed polkit dialog (126) is a cancel on a terminal too, and only 127
  falls back to `sudo`; `--help` describes `--allow-downgrade`.
- `scripts/lyona-update-root`: `die_part_way` exits 3 when `make
  install-system` fails after it began writing, naming the backup.
- `config/polkit/com.lyona.update.policy`: the downgrade prompt refers to the
  progress that named both versions, and to rollback.
- `config/quickshell/system/UpdateModel.qml`: `downgradeOffered`;
  `--allow-downgrade` is passed only when the channel offers an older release.
- `config/quickshell/settings/SystemSettingsPane.qml`: "Go back to V", a
  confirmation that says OLDER and names the installed version, "Install the
  older release".
- Docs: `docs/src/updating.md`, `docs/src/settings.md`, `SPEC.md` 5.5 and
  5.10, decisions D-34 and D-35 in `docs/sprints/UPSTREAM-SYNC.md`,
  `CHANGELOG.md`.

## Tests

Run through `scripts/run-tests`, each on its own:

| Check | Result |
| --- | --- |
| `make check-lyona-update` | PASS |
| `make check-quickshell-update-model` | PASS |
| `make check-shell-contracts` | PASS |
| `scripts/quickshell-qmllint --root config/quickshell` on the two QML files | exit 0 (two pre-existing `signal-handler-parameters` warnings on the `onExited` lines) |
| `shellcheck` on the two scripts and three tests | no new findings (the `SC2154` notes on sourced variables are pre-existing) |
| `shfmt -d` on the same | clean |
| `xmllint --noout` on the polkit policy | clean |

New assertions:

- `tests/test-lyona-update.sh`: the status file after a failed apply carries
  die's reason ("trusted privileged update helper is unavailable (exit 1)"),
  never "authentication required) (exit"; the notification carries it too;
  `pkexec` exiting 126 on a terminal is a cancel (exit 4, no `sudo`), 127
  still falls back to `sudo`; `cmd_apply` tells exit 3 apart and points at
  `rollback (backup ID)`; the status before a downgrade prompt names both
  versions; the policy no longer says "lyona-update named both"; `--help`
  describes the flag.
- `tests/test-quickshell-update-model.sh`: `downgradeOffered` exists,
  `--allow-downgrade` is pushed only under it and never in the routine
  command, the pane says "Go back to", "OLDER than the installed" and "Install
  the older release".
- `tests/test-lyona-update-root-backups.sh` (part 2, root): a regular file
  where `DATADIR/applications` should be makes `install-system` fail after
  `bin/dwm` was written and before the commands; the helper exits 3, names the
  backup and says to roll back, the backup exists, `bin/dwm` is newer while
  `dwm-status` still has the old marker, and `restore-system` brings the old
  `dwm` back.

## Not tested

- `tests/test-lyona-update-root-backups.sh` part 2 needs root in an
  `archlinux:base-devel` container (`make check-update-root-backups`): not run
  here. The new block was written against the helper's code paths and the
  test's existing conventions only.
- No real or nested X11 session: the Settings pane's new texts were not seen
  rendered, and no update, downgrade or part-way failure was run on a VM.
- `pkexec` exit codes were exercised with the test's stub, not a real polkit
  agent.
