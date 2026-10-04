# S12-03 -- the root helper writes and builds nothing through user paths

Plan: `docs/sprints/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-03-the-root-helper-writes-and-builds-nothing-through-user-paths`.
Issue `#166`. Decision D-15 (remove checkout mode). Builds on S12-01 and S12-02.

## Change

- **The helper's log is written as the invoking user.** `log_outcome`
  (`scripts/lyona-update-root`) ran `mkdir -p` and `>>` as root on
  `~/.local/state/lyona/update.log`, so a symlink there, or on a parent directory, made
  root create or append to any file.
  - It now pipes the line to `runuser -u "$invoking_user" -- sh -c 'umask 077 && mkdir -p
    -- "${1%/*}" && cat >>"$1"'`.
  - Control characters in the logged target are replaced with `?`, so a crafted path
    cannot forge log lines.
  - A failure to log is still ignored, as before.
- **Checkout mode is removed (D-15).**
  - `lyona-update-root`: the `install-system checkout` branch is gone, along with
    `user_owned_dir`, which only it used. The usage text lists only the release mode
    and `restore-system`.
  - `lyona-update`: `--from-checkout` is gone from the usage text and the option parsing,
    and so are the `install_mode` switch and the checkout branch. The apply path is
    release-only, with one privileged call.
  - `lyona-update apply --from-checkout` now fails with a message pointing to
    `sudo make install-system` or `scripts/dev-sync-install.sh`.
  - `lyona-update status` still recognises an install made from a checkout
    (`LYONA_SOURCE=checkout`), since `sudo make install-system` still produces those.
  - The backup record file keeps its name, `checkout.txt`: it describes any backup, not
    checkout mode.
- **`install-cursors` installs root-owned files.** It used `cp -a`, which as root keeps
  the building user's ownership. It now uses `cp -a --no-preserve=ownership`, the way
  `install-grub-theme` already did.
- `docs/src/updating.md`: the `--from-checkout` entry says it was removed and what to
  use instead.

## Results (2026-09-27, CachyOS host, Docker, nothing committed)

- **`tests/test-lyona-update-root-backups.sh`**, run as root in `lyona-ci:f63532b17846`:
  PASS.
  - After a restore, the log is the user's own 0600 file, holding the
    `restore-system ... succeeded` line.
  - With `update.log` replaced by a symlink to `/etc/lyona-planted-log`, a restore still
    succeeds and creates nothing in `/etc`.
  - Part 2 installs the cursor themes as root from a tree owned by the building user,
    and every installed cursor file is root-owned.
- **`tests/test-lyona-update.sh`** (`check-lyona-update`): PASS.
  - The eight apply cases that used `--from-checkout` now install a source tarball with
    `--file` (built once; the broken-build case builds its own). They cover downgrade,
    dry run, build failure, missing privileged helper, status and log, declining, and
    the D-18 `config.h` case.
  - A new case asserts `--from-checkout` is refused with the replacement command.
  - Pins: exactly one privileged site in `cmd_apply` (the release install, which passes
    the backup id); no `install-system checkout` in `cmd_apply`; no `checkout)` branch
    in the helper.
- **Mutation checks**, both caught by the container test:
  - writing the log as root;
  - `install-cursors` without `--no-preserve=ownership`.
- `check-shell`, `check-format`: PASS.

## Found while testing (historical; since fixed)

An earlier updater passed the `lyona-update apply --file` path directly to the
privileged step, which accepts only tarballs under `~/.local/state/lyona/updates/`.
The current updater (`75bb338`) copies an external archive into that directory before
calling `lyona-update-root`, and reuses one already staged there;
`tests/test-lyona-update.sh` covers both. Recorded under S12-11 as item 6a, marked
historical.

## Not verified

- A real polkit prompt. The container runs the helper through `PKEXEC_UID`.
- Developers' workflows after the removal: `sudo make install-system`, and
  `dev-sync-install.sh` itself, were not changed or rerun here.
