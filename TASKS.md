# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Phase 5
completion evidence is recorded in `ROADMAP.md`'s Phase 5 "Completion
Evidence" section and `CHANGELOG.md`.

## Active Phase: System Management

Phase 6 begins from the completed Personalization and Accessibility phase.
Keep DWM, X11, Arch providers, runtime TOML files, and existing user-owned
configuration compatible while adding the workflows below.

lyona's own update path (`UPDATE-001…003`, `docs/P6-UPDATE-*.md`) lands
first. It solves a different problem — updating lyona itself via signed
release tarballs — than Arch system-package updates and regional/account/
printer management, which is separate, already-planned, upstream-ported work
tracked as its own nine-phase sequence in `docs/UPSTREAM-SYNC.md`'s "The
system-management port" section. The two meet at exactly one point: UPDATE-003
lays out the Settings → System pane so an "Arch packages" group can be added
beside the "lyona" group later without rework — that "later" is
`docs/UPSTREAM-SYNC.md`'s Sync Phases 3 and 7. Do not begin that upstream-sync
work in a change scoped to complete UPDATE-001…003.

Keep Phase 6 reviewable through these ordered boundaries. Finish, validate,
and merge each before starting the next:

1. UPDATE-001 — install provenance.
2. UPDATE-002 — `lyona-update` check/apply/rollback with backup restore.
3. UPDATE-003 — Settings and Control Center surfaces over that helper.
4. The upstream-ported system-management work (`docs/UPSTREAM-SYNC.md`'s Sync
   Phases 1–9), once UPDATE-001…003 land.

### UPDATE-001: Install Provenance

- [x] Add a system-scope provenance record (`/etc/lyona-release`, written by
  `make install-system`) and a user-scope one
  (`$XDG_STATE_HOME/lyona/install.state`, written by `make install-user`),
  each stamped last — as `stamp-system`/`stamp-user`, the final recipe line in
  each target — so a failed install never claims success.
- [x] Add `scripts/lyona-version` — a read-only, versioned-protocol reader
  (`status`, `status --json`, `print`) that degrades safely: a missing record
  reads as `defaults`; a symlinked, wrong-owner, oversized, or
  group/other-writable one reads as `unavailable` and is never read through
  or rewritten; a malformed one is preserved byte-for-byte.
- [x] Converge the ISO and existing-system install paths: the ISO build's own
  commit stamp (`/etc/lyona-iso-release`) now carries through
  `archiso/airootfs/root/lyona-postinstall.sh` into the target's
  `LYONA_SOURCE=iso`/`LYONA_COMMIT` (passed as `make` arguments, not relied on
  through `sudo`'s environment, which does not preserve it by default),
  instead of every ISO-installed machine recording `unknown`. The live
  medium's own `/etc/lyona-iso-release` is also copied onto the target
  unchanged, so it keeps recording which *image* built the machine after
  later updates move `/etc/lyona-release` on.
- [x] `install.sh`'s completion banner reports the version `lyona-version
  print` actually recorded, not an assumed one.

Acceptance:

- `lyona-version status` reports `available`/`consistent yes` after a fresh
  install where the system record, user record, and `dwm -v` all agree. —
  **Met**, `tests/test-lyona-version.sh`.
- A half-applied install (mismatched system/user/binary versions) reports
  `consistent no` naming the differing values, not a false `available`. —
  **Met**, `tests/test-lyona-version.sh`.
- A missing, malformed, symlinked, or world-writable record degrades to its
  own honest state without crashing the helper or being rewritten. — **Met**,
  `tests/test-lyona-version.sh`.
- A failed `install-system`/`install-user` writes no stamp, and re-running an
  install replaces rather than appends. — **Met**,
  `tests/test-install-preservation.sh`.

### UPDATE-002: `lyona-update` Helper

- [ ] Ship `lyona-update check|apply|rollback`, staging to
  `$XDG_STATE_HOME/lyona/updates/<version>/`, verifying a signed release
  tarball's SHA-256 against the GitHub release asset digest before unpacking,
  and never swapping the live tree in place (`Commands.helperCommand`
  resolves helpers from the data dir of a *running* session).
- [ ] Reuse `scripts/dev-sync-install.sh`'s existing backup/verify machinery
  (`backup_live_install()`, `verify_install()`, `verify_tree()`,
  `runtime_verify()`) rather than rebuilding it, and add the missing restore
  path so `rollback` actually reads a backup back — provably from a bare TTY
  with no desktop running, per `docs/P6-UPDATE-HELPER.md`'s acceptance.
- [ ] One confirmed privileged step (the existing `${PREFIX}/libexec/lyona` +
  `dwm-polkit` pattern) for `make install-system` alone; everything else —
  check, download, verify, build, stage — runs unprivileged. Declining leaves
  a staged, verified, uninstalled update and a non-zero exit, never a
  half-applied system.
- [ ] `check`/`apply` support a channel (`stable`/`preview`) recorded in
  `~/.config/lyona/update.conf`, seeded but never overwritten.

Acceptance:

- An interrupted `apply` leaves a mixed tree recoverable by `rollback`, never
  a silent claim of success — the provenance stamp from UPDATE-001 is written
  last, after `rollback` re-verifies.
- A downgrade or offline `check` degrades explicitly (`apply --file PATH`,
  `--allow-downgrade`) rather than failing unhelpfully.
- Preservation carries over unweakened: everything `tests/test-install-preservation.sh`
  already guards (`config.h`, `~/.config/lyona/*.toml`, symlinked config
  directories, settings-helper-owned files) survives an update the same way
  it survives a fresh install.

### UPDATE-003: Settings and Control Center Surfaces

- [ ] Add a "lyona" group to Settings → System backed by `lyona-update`,
  laid out so an "Arch packages" group can be added beside it later without
  rework — that group is `docs/UPSTREAM-SYNC.md`'s Sync Phases 3 and 7, gated
  on this boundary landing first.
- [ ] Surface check/apply/rollback with visible confirmation, live progress,
  and cancellation. `auto_apply` stays rejected — no silent background
  updates; unattended updates need their own specification.
- [ ] Rollback from within a broken session is explicitly out of scope for
  this pane — if the desktop will not start there is no UI to click. Document
  the TTY path (UPDATE-002) as the answer.

Acceptance:

- The update surface never auto-applies without explicit confirmation.
- Declining the privileged step leaves a staged, verified, uninstalled update
  and a clear non-zero result, not a half-applied system.
- Closing the pane leaves no resident scan, duplicate subscription, or
  orphaned helper process.

## Phase Completion

When all Phase 6 acceptance criteria pass:

1. Record delivered behavior and validation in `CHANGELOG.md`.
2. Update the Phase 6 status and limitations in `ROADMAP.md`.
3. Replace this file's active task set with the next phase's tasks — the
   upstream-ported system-management work indexed in `docs/UPSTREAM-SYNC.md`'s
   "The system-management port" section (Sync Phases 1–9).
4. Preserve incomplete or deferred work as explicit roadmap limitations.
