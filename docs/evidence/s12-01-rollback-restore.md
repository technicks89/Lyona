# S12-01 -- rollback restores only what root has checked

Plan: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-01-rollback-restores-only-what-root-has-checked`.
Issue `#164`.

## Why the plan's diff was not enough

The plan proposed copying the user's `system-files.tar` into a root-owned directory,
extracting it with `--no-same-owner --no-same-permissions`, and refusing members under
`libexec/lyona`. That fixes owners, modes and the double read, but not the contents: a
backup any program running as the user can write could still put a root-owned file of
its choosing into `/usr/local/bin`, which root runs later (root's `PATH`, sudo's
`secure_path`, and the display helper's `dwm-display-setup`). Refusing `libexec`
members would also have made every genuine rollback fail, since every backup holds the
helpers. So root now makes and keeps the system backups itself, and a rollback names
one by id. That is the plan's "longer-term fix", done now.

## Change

- `scripts/lyona-update-root`:
  - `install-system release` and `install-system checkout` take a backup id as a new
    last argument and call `backup_system_files` just before `make install-system`. It
    reads the file list from the tree about to be installed (`dwm $(THUMB)
    $(INSTALL_COMMAND_NAMES)`, `$(PRIVILEGED_HELPERS)`, the two cursor themes, the man
    page, the X session file, `licenses/lyona`, `/etc/lyona-release`), and archives the
    live files that exist into `/var/lib/lyona/backups/<id>/system-files.tar` with
    `--numeric-owner`. The store is created 0700 and must be a real root-owned
    directory with no group or other access, or nothing is written. It records the
    replaced version in `backup.txt` and keeps the newest 5 backups.
  - `restore-system` takes an id (`YYYYMMDDTHHMMSSZ-PID`), never a path. It requires the
    store and the backup directory to be private to root and the archive to be a
    root-owned regular file, keeps the member allowlist and the setuid/setgid/sticky
    refusal as defence in depth, allows symlinks only inside the cursor themes, and
    extracts with `--numeric-owner -xpf`.
- `scripts/lyona-update`: `apply` passes `${backup_dir##*/}` to both install modes, and
  `rollback` passes the id to `restore-system`. The user-side backup still holds the
  user trees, which `lyona-update` restores itself, without root.
- `docs/src/updating.md`: where the two halves of a backup live, and that older
  backups cannot restore system files.
- `Makefile`: `check-update-root-backups` (container-only, exit-77 convention).
  `.github/workflows/full-suite.yml`: an `update-helper-backups` job in
  `archlinux:base-devel` with the build dependencies.

Two defects fixed along the way:

- The old allowlist refused every symlink, and the shipped cursor themes hold 128, so a
  restore of any backup that included the cursor themes failed.
- The system backup never held `dwm-window-thumb` (the list came from
  `INSTALL_COMMANDS` only) or `/etc/lyona-release`.

## Results (2026-09-27, CachyOS host, Docker, nothing committed)

- `tests/test-lyona-update-root-backups.sh` as root in `lyona-ci:f63532b17846` (with
  build dependencies): PASS, both parts.
  - Part 1, `restore-system`, refuses:
    - a path into the user's backup directory, `../../etc`, `<id>/..`, an empty or
      missing id;
    - no store, or no backup for the id;
    - a store that is 0750 or user-owned;
    - a user-owned backup directory, or a symlink to one;
    - a user-owned archive;
    - an archive member under `etc/cron.d`, a setuid member, and a symlink in `bin/`
      (and writes none of them).

    It restores a good backup's contents with owner 0 and mode 0755.
  - Part 2: a real `install-system release` from a source tarball, over a live install
    whose `dwm-status` carries a marker. The new backup is `0 700`, holds the marked
    live file and the helper itself, pruning keeps 5 of 7, the install replaced the
    file, and `restore-system <id>` brings the marker back.
- The same test in `archlinux:base-devel` (no build dependencies): part 1 PASS, part 2
  skipped with a message.
- Mutation checks, each run in the container. All caught:
  - dropping the id check in `restore-system`;
  - dropping the store privacy check;
  - dropping the archive owner check;
  - allowing symlinks anywhere;
  - allowing setuid;
  - not calling `backup_system_files` before install;
  - not pruning.
- `tests/test-lyona-update.sh`: new pins that `rollback` passes `"$backup_id"`, never
  `"$backup_dir"`, and that both install modes pass the id. Changing the rollback
  call back to `"$backup_dir"` fails the test.
- `scripts/run-tests make clean all check-lyona-update check-install-manifest
  check-install-preservation check-shell check-format check-quickshell-update-model`
  and `tests/test-ci-parity.sh`: PASS.

## Found while testing, not fixed here

**The published release asset cannot be installed by `lyona-update` at all.**
`scripts/lyona-release` publishes the output of `make release` as
`lyona-<version>.tar.gz`. That archive is a runtime bundle: the `dwm` binary,
`assets/`, `config/`, `scripts/`, with no `Makefile`, `config.mk` or sources.
`lyona-update apply` extracts it and runs `make -C "$staging_dir" clean`
(`scripts/lyona-update:680`), and `lyona-update-root install-system release` reads
`config.mk` and runs `make` on it. Both fail on a real release. Part 2 of the test
therefore builds a source tarball, the form the helper's contract expects. This needs
its own item; the ROADMAP's packaging plan would replace this path, but today's path
should either publish a source archive or install the bundle as built.

## Not verified

- A real polkit prompt, and a rollback on real hardware; the container runs the
  helper through `PKEXEC_UID` without polkit. Recorded in S10-07's ledger.
- A rollback in a real session through the Settings pane.
- Files that a newer version added are still left in place by a rollback, as before;
  this change does not remove them.
