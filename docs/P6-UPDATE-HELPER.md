# UPDATE-002 — `lyona-update`

Second boundary of the Phase 6 update path. Architecture and rationale:
[`P6-UPDATE-OVERVIEW.md`](P6-UPDATE-OVERVIEW.md). Depends on
[`UPDATE-001`](P6-UPDATE-PROVENANCE.md) for the installed-version record.

## Context

With provenance in place, a machine can say what it runs. This boundary lets it
move to something newer, and — critically — back again.

Most of the machinery exists. `scripts/dev-sync-install.sh` already builds from
a clean object state, skips work when everything matches, backs up the live
install, runs the full system+user install, verifies the result against the
source tree, restarts Quickshell when safe, and reports whether dwm needs a
session restart. What it assumes is a **developer with a git checkout**.

The new helper supplies what a user lacks — a way to obtain and verify new
sources — and the one thing nobody has: **a restore path**.
`backup_live_install()` (`dev-sync-install.sh:244-300`) writes a complete,
checksummed backup to `$XDG_STATE_HOME/lyona/live-update-backups/`, and nothing
in the repository ever reads it back.

---

## Command surface

```
lyona-update check      [--channel stable|preview] [--json]
lyona-update apply      [--version V] [--file PATH] [--from-checkout DIR]
                        [--allow-downgrade] [--dry-run] [--yes]
lyona-update rollback   [--backup ID] [--list] [--yes]
lyona-update backups    [--json]
```

Unprivileged throughout, except one confirmed step inside `apply` (see
*Privilege* below).

### `check`

Reads the installed version via `lyona-version status`, queries the GitHub
Releases API for the configured channel, and reports. Never writes anything
outside its cache.

```
lyona-update-protocol	1	0
state	behind	A newer stable release is available
installed	2026.08.0-beta.1	b85539b
available	2026.09.0	f4a2c81	2026-09-14T09:22:07Z
channel	stable
asset	lyona-2026.09.0.tar.gz	3f9c…a12	4718592
complete	check
```

`state` ∈ `current`, `behind`, `ahead`, `downgrade-offered`, `unknown`,
`offline`, `unavailable`.

`offline` is a first-class outcome, not an error: `check` exits 0, reports the
installed version, and says the remote could not be reached. A desktop that
errors because it cannot reach GitHub is worse than one that shrugs.

Version comparison follows the documented calendar scheme: `YYYY.MM[.PATCH]`
with an optional `-alpha.N` / `-beta.N` / `-rc.N` suffix ordering *before* the
same version without one (`docs/RELEASING.md`). The `stable` channel takes the
GitHub *Latest* release, which by construction excludes pre-releases because
`lyona-release` publishes them with `--prerelease`.

Cache the release index at `$XDG_CACHE_HOME/lyona/update-index.json` with a
short TTL so a panel indicator does not hammer the API.

### `apply`

Nine steps. Five reuse existing code.

| Step | Action | Reuse |
| --- | --- | --- |
| 1 | Download `lyona-VERSION.tar.gz` to `$XDG_STATE_HOME/lyona/updates/` | new |
| 2 | Verify SHA-256 against the release asset digest, **before unpacking** | new |
| 3 | Unpack to `$XDG_STATE_HOME/lyona/updates/<version>/`; copy the live `config.h` in | new |
| 4 | `make all` in the staging tree, unprivileged | existing target |
| 5 | Back up the live install | `backup_live_install()` |
| 6 | `make install-system` (privileged, confirmed) then `make install-user` | existing targets |
| 7 | Verify installed files against the staged tree | `verify_install()` |
| 8 | Rewrite the provenance record | UPDATE-001 |
| 9 | Restart Quickshell when safe; report if dwm needs a session restart | `runtime_verify()` |

Ordering rules that matter:

- **Verify before unpack** (2 before 3). A tampered or truncated tarball must
  never reach the filesystem as files.
- **Back up before any write** (5 before 6). The backup is worthless if it is
  taken after the first system file has moved.
- **Stamp last** (8 after 7). An interrupted update must never leave a record
  claiming success — that is what makes `lyona-version --consistent` a reliable
  damage detector.
- **Build before escalating** (4 before 6). A compile failure must cost the user
  nothing but time; it must not happen with root held.

`--file PATH` skips steps 1-2 for an already-downloaded tarball (offline
installs, air-gapped machines). It still checksums the file and still requires
`--version` agreement with the tarball's own `config.mk`.

`--from-checkout DIR` skips 1-3 entirely and stages from a git checkout —
the path a user who cloned already has. `LYONA_SOURCE_TREE` from the provenance
record is the default when the flag is bare.

`--dry-run` performs steps 1-4 and then prints exactly what steps 5-9 would
touch, including the full list of privileged paths. Nothing is installed.

### `rollback`

The missing half of `backup_live_install()`.

```
lyona-update rollback --list
lyona-update rollback                # newest backup
lyona-update rollback --backup 20260828T153709Z-1472673
```

1. Locate the backup directory under
   `$XDG_STATE_HOME/lyona/live-update-backups/`.
2. Verify every archive against the recorded `SHA256SUMS` — refuse on any
   mismatch, restore nothing.
3. Read `checkout.txt` for the prefix, data root and config/data homes the
   backup was taken against; refuse if they no longer match the current
   environment rather than restoring into the wrong tree.
4. Restore `system-files.tar` (privileged, confirmed), then `lyona-data.tar` and
   `quickshell.tar` (unprivileged).
5. Re-stamp the provenance record from the backup's recorded version.
6. Report that a session restart is required.

**Rollback must work with no desktop running.** If a release cannot start a
session, the user is at a TTY — so `rollback` may not depend on Quickshell, the
panel, D-Bus, or a polkit *agent*. It falls back to `sudo` with a clear prompt
when no agent is reachable. This is an explicit acceptance criterion below.

Backups are pruned to the newest N (default 5, configurable) at the *end* of a
successful `apply`, never at the start.

---

## Privilege

`make install-system` writes `${PREFIX}/bin`, `${MANPREFIX}`, `${XSESSIONSDIR}`
and `${PREFIX}/libexec/lyona` — all root-owned. Phase 6 requires every
privileged action to be allowlisted, confirmed, auditable and cancelable
(`ROADMAP.md`).

Follow the pattern already in the tree — `PRIVILEGED_HELPERS` installed to
`${PREFIX}/libexec/lyona` (`Makefile:87-88,193-197`), authenticated through
`scripts/dwm-polkit`, as `scripts/dwm-settings-display-root` does:

- Add `scripts/lyona-update-root` to `PRIVILEGED_HELPERS`. It accepts exactly
  two verbs — `install-system <staging-dir>` and `restore-system <backup-dir>` —
  and nothing else. No shell interpolation of caller-supplied strings.
- It validates that the staging directory is under
  `$XDG_STATE_HOME/lyona/updates/`, owned by the invoking user, and contains a
  built `dwm` plus a `config.mk` whose `VERSION` matches the requested one,
  before it does anything.
- The unprivileged parent prints the complete list of paths to be written and
  waits for confirmation (`--yes` to skip in scripted use).
- Declining leaves a staged, built, verified, **uninstalled** update and a
  non-zero exit. Never a half-applied system.
- Every invocation appends to `$XDG_STATE_HOME/lyona/update.log`: UTC timestamp,
  verb, version, target paths, outcome. That is the "auditable" half of the
  exit criteria.

---

## Configuration

`~/.config/lyona/update.conf`, seeded when absent and never overwritten,
matching the `test -f … || install` idiom at `Makefile:274-277`:

```
channel=stable
check_on_login=true
auto_apply=false
keep_backups=5
```

`auto_apply` has no `true` implementation in this boundary and is rejected if
set — the key exists so the file shape is stable, and so that a future
unattended mode is an explicit decision rather than a config typo. Updates
in this boundary are always user-initiated, per the Phase 6 outcome wording.

---

## Tests

### New: `tests/test-lyona-update.sh`

Fully offline. Stub `curl`/`gh` with `stub_command` from `tests/lib.sh`, serve a
fixture release index and a fixture tarball built by the test itself.

| Case | Assertion |
| --- | --- |
| `check`, installed == latest | `state current` |
| `check`, installed older | `state behind`, names the target version |
| `check`, installed newer | `state ahead` |
| `check`, no provenance record | `state unknown`, exit 0 |
| `check`, network stub fails | `state offline`, exit 0, installed version still reported |
| `check --channel preview` | selects a pre-release the stable channel skipped |
| Version ordering | `2026.09.0` > `2026.08.1` > `2026.08.0` > `2026.08.0-rc.1` > `-beta.2` > `-beta.1` > `-alpha.1` |
| Checksum mismatch | aborts before unpacking; staging dir does not exist afterwards |
| Truncated tarball | aborts at verify, not at unpack |
| `apply --dry-run` | lists privileged paths; installs nothing; no backup taken |
| Build failure in staging | exits non-zero **before** any privileged call; live install untouched |
| Privileged step declined | staged tree intact, live install untouched, non-zero exit |
| Downgrade without `--allow-downgrade` | refused with a clear message |
| `config.h` preservation | live `config.h` present in the staging tree before build |
| Stamp ordering | kill after install, before stamp → `lyona-version` reports `consistent no` |
| `rollback --list` | lists backups newest-first with version and date |
| `rollback` checksum mismatch | restores nothing |
| `rollback` prefix mismatch | refuses rather than restoring into the wrong tree |
| Round trip | apply → rollback → provenance and file hashes match the pre-update state exactly |
| Backup pruning | `keep_backups=2` leaves exactly the two newest, after a successful apply |

### Extend: `tests/test-install-preservation.sh`

Run a full apply over a populated user profile and assert survival of
`~/.config/lyona/*.toml`, `~/.xinitrc`, symlinked config dirs, `config.h`, and
every settings-helper file (`panel-widgets.conf`, `wallpaper.conf`, `font.conf`,
`dpi.Xresources`, `xsettingsd.conf`, `cursor.Xresources`, `theme-env.sh`).

### Extend: `tests/test-shell-contracts.sh`

Already enforces `mv -fT` on bare `mv -f` sites; the new scripts must comply.

### `Makefile`

`scripts/lyona-update` in `INSTALL_COMMANDS`; `scripts/lyona-update-root` in
`PRIVILEGED_HELPERS`; both in the `check-shell` and `check-format` explicit
lists; `check-lyona-update:` target added to `check:` and `.PHONY`; the
privileged helper removed by `uninstall`.

---

## Verification

```bash
scripts/run-tests make check-lyona-update
scripts/run-tests make check-install-preservation
scripts/run-tests tests/test-shell-contracts.sh
scripts/run-tests make check-shell check-format
scripts/run-tests make check
```

On a disposable Arch VM (per `docs/RELEASING.md`, not `/tmp`), with two real
published releases:

1. Install release N from the ISO. `lyona-version status` → `available`.
2. `lyona-update check` → `behind`, offering N+1.
3. `lyona-update apply --dry-run` → lists privileged paths, changes nothing.
4. `lyona-update apply` → confirm once; Quickshell restarts; the session-restart
   notice appears if dwm changed. Log out and back in.
5. `lyona-version status` → `consistent yes` at N+1. User config, hotkeys,
   themes, wallpaper and panel-widget state all survived.
6. **Pull the power mid-install.** On reboot, `lyona-version status` reports
   `consistent no`; `lyona-update rollback` restores N and reports it.
7. **From a TTY with no desktop running**, `lyona-update rollback` completes and
   the session starts again. This is the criterion that matters most — it is the
   path a user takes when an update leaves them with no GUI.
8. Disconnect the network: `check` reports `offline` and exits 0;
   `apply --file` still works from a locally copied tarball.
9. Confirm `$XDG_STATE_HOME/lyona/update.log` records every privileged
   invocation with timestamp, verb, version, paths and outcome.
