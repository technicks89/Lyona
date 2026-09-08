# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Phase 5
completion evidence is recorded in `ROADMAP.md`'s Phase 5 "Completion
Evidence" section and `CHANGELOG.md`.

## Active Phase: System Management

Phase 6 begins from the completed Personalization and Accessibility phase.
Keep DWM, X11, Arch providers, runtime TOML files, and existing user-owned
configuration compatible while adding the workflows below.

lyona's own update path (`UPDATE-001…003`, `docs/P6-UPDATE-*.md`) — solving a
different problem, updating lyona itself via signed release tarballs, than
Arch system-package updates and regional/account/printer management — is
**done** (merged `3c8adb2`, `d489f1f`, `fdb0995`). That was a prerequisite,
not the whole of Phase 6: the active work is now the upstream-ported
system-management work itself, tracked as its own nine-phase sequence in
`docs/UPSTREAM-SYNC.md`'s "The system-management port" section (Arch package
updates, timezone/NTP/locale, accounts, printers, software sources). The two
efforts meet at exactly one point: UPDATE-003 laid out the Settings → System
pane so an "Arch packages" group can be added beside the "lyona" group
without rework — that "later" is `docs/UPSTREAM-SYNC.md`'s Sync Phases 3 and 7.

Keep Phase 6 reviewable through these ordered boundaries. Finish, validate,
and merge each before starting the next:

1. UPDATE-001 — install provenance. **Done.**
2. UPDATE-002 — `lyona-update` check/apply/rollback with backup restore. **Done.**
3. UPDATE-003 — Settings and Control Center surfaces over that helper. **Done.**
4. The upstream-ported system-management work (`docs/UPSTREAM-SYNC.md`'s Sync
   Phases 1–9) — **active**, Sync Phase 1 below.

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

- [x] Ship `lyona-update check|apply|rollback|backups`, staging to
  `$XDG_STATE_HOME/lyona/updates/<version>/`, verifying a release tarball's
  SHA-256 against the GitHub release asset digest before unpacking, and never
  swapping the live tree in place. — **Met**, `scripts/lyona-update`,
  `tests/test-lyona-update.sh`.
- [x] Reuse `scripts/dev-sync-install.sh`'s existing backup/verify machinery
  (`backup_live_install()`, `verify_install()`, `verify_tree()`,
  `runtime_verify()`) rather than rebuilding it, and add the missing restore
  path so `rollback` actually reads a backup back — provably from a bare TTY
  with no desktop running (falls back from `pkexec` to `sudo` when no
  graphical session/agent is reachable). — **Met**: a
  `DEV_SYNC_INSTALL_LIB_ONLY`/`DEV_SYNC_INSTALL_REPO_DIR` sourcing guard added
  to `dev-sync-install.sh` (its own direct-invocation behavior unchanged,
  `tests/test-dev-sync-install.sh`); `scripts/lyona-update-root`'s
  `restore-system` verb accepts either `PKEXEC_UID` or `SUDO_UID`. The
  power-loss-mid-install and bare-TTY scenarios themselves need the
  disposable-VM pass in `docs/P6-UPDATE-HELPER.md`'s Verification section —
  no root is available to exercise them in the automated suite.
- [x] One confirmed privileged step (the existing `${PREFIX}/libexec/lyona`
  polkit pattern) for `make install-system` alone; everything else — check,
  download, verify, build, stage — runs unprivileged. Declining leaves a
  staged, verified, uninstalled update and a non-zero exit, never a
  half-applied system. — **Met**, `scripts/lyona-update-root`,
  `config/polkit/com.lyona.update.policy`; the "declined" path is exercised
  in `tests/test-lyona-update.sh` (no trusted root-owned helper exists in the
  unprivileged test sandbox, which is itself the natural "unavailable" case).
  Hardened after review: the privileged helper originally ran `make -C
  <staging-dir> install-system` against a directory the invoking user could
  still write to at that point — a Makefile/`config.mk` executes arbitrary
  shell during GNU Make's own variable expansion (`$(shell ...)`), not only
  through the recipe someone thinks they're invoking, so this was arbitrary
  root code execution behind an "Install a lyona update" auth prompt. Fixed
  by having `install-system release` re-verify the tarball's SHA-256
  immediately before use, then extract, rebuild, and install from a fresh
  root-owned-only scratch directory the invoking user has never had write
  access to (closing the verify-then-mutate window down to nothing, and
  ensuring the binary every user on the machine runs is one root itself
  built from verified source, not a copy the invoking user could have
  swapped after their own unprivileged build finished). `restore-system` had
  the same shape (`tar -xpf` onto `/` from a manifest and checksum both
  living in the same user-writable backup directory) and now validates every
  archive member — path, type, and mode — before extracting: the path must
  fall under a fixed set of managed locations (no `..` or absolute escape),
  the type must be a regular file or directory (never a symlink, hardlink,
  device, FIFO, or socket, any of which GNU tar preserves and creates by
  default when run as root), and the mode must carry no setuid, setgid, or
  sticky bit (a setuid-root `dwm` is a root shell for every user on the
  machine, since dwm can spawn arbitrary configured commands). Verified
  against a small harness covering a legitimate backup plus each rejected
  shape (symlink, hardlink, setuid, FIFO, a nested path under a directory
  that should only ever be flat, and a path outside every managed prefix) —
  the legitimate case is accepted and every hostile shape is refused with a
  specific reason. `--from-checkout` (`install-system checkout`) is
  unaffected — it carries the same trust level as running `sudo make
  install-system` directly from a developer's own checkout, not a weaker one
  introduced by going through `lyona-update`.
- [x] `check`/`apply` support a channel (`stable`/`preview`) recorded in
  `~/.config/lyona/update.conf`, seeded but never overwritten. — **Met**,
  `tests/test-lyona-update.sh`.

Acceptance:

- An interrupted `apply` leaves a mixed tree recoverable by `rollback`, never
  a silent claim of success — the provenance stamp from UPDATE-001 is written
  last, after `rollback` re-verifies. — Ordering is correct by construction
  (backup before any write, stamp last, per the nine-step sequence in
  `docs/P6-UPDATE-HELPER.md`); the actual power-loss/recovery run needs the
  disposable-VM pass, not covered by the unprivileged automated suite.
- A downgrade or offline `check` degrades explicitly (`apply --file PATH`,
  `--allow-downgrade`) rather than failing unhelpfully. — **Met**,
  `tests/test-lyona-update.sh`.
- Preservation carries over unweakened: everything `tests/test-install-preservation.sh`
  already guards (`config.h`, `~/.config/lyona/*.toml`, symlinked config
  directories, settings-helper-owned files) survives an update the same way
  it survives a fresh install. — The preservation machinery itself is reused
  unmodified (`make install-user`, `dev-sync-install.sh`'s verify functions);
  a full `apply`-driven end-to-end preservation run requires real privilege
  and is part of the disposable-VM pass, not the automated suite.

### UPDATE-003: Settings and Control Center Surfaces

- [x] Add a "lyona" group to Settings → System backed by `lyona-update`,
  laid out so an "Arch packages" group can be added beside it later without
  rework — that group is `docs/UPSTREAM-SYNC.md`'s Sync Phases 3 and 7, gated
  on this boundary landing first. — **Met**: `SystemSettingsPane.qml` over
  `UpdateModel.qml`, wired into the "system" section `SettingsModel.qml`
  already reserved (alongside its existing `health`/`authorization`/
  `administration` capabilities, now joined by a fourth `updates` capability
  from `dwm-settings-provider`).
- [x] Surface check/apply/rollback with visible confirmation, live progress
  — **partially met**. Confirmation (naming the target version before
  calling `apply()`), phase-by-phase progress surviving Quickshell's own
  restart (via the new `update.status` file), and channel/backups/rollback
  are all implemented and covered by `tests/test-quickshell-update-model.sh`.
  **Cancellation is not implemented** — once `apply`/`rollback` is started
  there is no way to interrupt it from the pane. `auto_apply` stays rejected
  — no silent background updates; unattended updates need their own
  specification.
- [x] Rollback from within a broken session is explicitly out of scope for
  this pane — if the desktop will not start there is no UI to click. Document
  the TTY path (UPDATE-002) as the answer. — **Met**, `docs/src/updating.md`
  and `README.md`'s Troubleshooting section both lead with the TTY path.
  `rollback` now also restarts Quickshell itself when a desktop session is
  present, so a live rollback from the pane actually takes effect.

Acceptance:

- The update surface never auto-applies without explicit confirmation. —
  **Met**: `SystemSettingsPane.qml`'s `confirmVersion` gate, matching
  `DisplaySettingsPane.qml`'s existing confirmation idiom for a privileged
  action rather than inventing a new dialog.
- Declining the privileged step leaves a staged, verified, uninstalled update
  and a clear non-zero result, not a half-applied system. — **Met**, carried
  over unchanged from UPDATE-002's `run_privileged` behavior; the pane
  surfaces the CLI's own stderr as `message`.
- Closing the pane leaves no resident scan, duplicate subscription, or
  orphaned helper process. — `UpdateModel` uses no polling timer (only
  `FileView` watches and one one-shot login-check `Timer` with
  `repeat: false`, asserted by `tests/test-quickshell-update-model.sh`), so
  there is nothing to leave running. Not independently exercised under Xvfb
  in this environment (`xkbset` is unavailable in the sandbox this was built
  in, matching the same pre-existing gap noted for `check-quickshell-settings-xvfb`
  since Phase 5) — the extension to `tests/test-quickshell-settings-xvfb.sh`
  (a stubbed `lyona-update`, IPC probes, and a real phase-progression check
  through the stub's `apply`) is written and passes `check-shell`/
  `check-format`, but has not itself been run end-to-end.

### Sync Phase 1: System-Management Provider Decision, Contract, and Packaging

Upstream: `#207`, `#209`, `#265`. Doc:
`docs/SYNC-P1-SYSTEM-PROVIDER-DECISION.md`. Lands no user-visible behavior —
it exists because the subsystem cannot be ported until one question is
answered, and answering it later would mean rewriting whatever came before.

- [x] **The core decision.** Adopt upstream's Python helper
  (`scripts/dwm-system-management`, PackageKit over D-Bus via PyGObject's
  `Gio`) largely as-is (Option A), rather than a POSIX-shell reimplementation
  (Option B, rejected — the doc's own analysis found the highest-risk part of
  the whole port, a crash-safe atomic journal and async D-Bus reads, is
  exactly what shell is worst at) or a read-only shell-only subset (Option C).
  — **Met**: recorded in `docs/SYNC-P1-SYSTEM-PROVIDER-DECISION.md`'s
  `Decision:` line, 2026-09-08.
- [x] Write `docs/P6-SYSTEM-MANAGEMENT.md`, Lyona's own contract, adapted from
  upstream's real 2,492-line Fedora document (fetched and read in full, not
  worked from summary) with Arch substitutions applied throughout. — **Met**,
  349 lines — deliberately condensed relative to upstream: the exhaustive
  D-Bus retry/timeout/byte-budget detail belongs to each Sync Phase document
  that implements that piece, not to this contract, which fixes the protocol
  grammar, the protocol-minor staging table, the authorization/lifecycle
  rules, and the Arch interface substitutions. D-3 and D-4 carried through as
  still open, not resolved by writing it.
- [x] New `arch:system-management` / `arch:system-management-optional`
  package profiles (`python`, `python-gobject`, `packagekit`,
  `accountsservice`, `cups` required; `system-config-printer`, `arch-audit`
  optional), wired into `arch:recommended`/`arch:optional`, `install.sh`.
  — **Met**, `tests/test-arch-packages.sh` (now also asserting these two
  profiles against live `pacman -Si`, not just `required`/`desktop`)
  confirms all packages are real and installable: "Arch required, desktop,
  and system-management package map: PASS (67 packages)".
  **`archiso/packages.x86_64` deliberately does not include them** —
  correcting the doc's own "mirror the required half" instruction: that file
  is a strictly `required + desktop + iso` derivation, test-enforced by
  `check-archiso` (`tests/test-arch-iso-builder.sh`), and does not carry
  `desktop-optional`'s packages either. The live ISO installs the target
  system via `pacstrap`, not PackageKit; these are target-system runtime
  dependencies for a Settings feature, the same category as
  `desktop-optional`'s thunar/gvfs, not ISO bootstrap requirements. Manually
  adding them broke `check-archiso`, caught and reverted.
  `scripts/check-deps.sh` reports the new packages automatically — it walks
  the same aggregate profiles, no separate edit was needed there.
- [x] `Commands.qml`: `systemManagementCommand()` and
  `terminatingCheckedCommand()` (the latter forwards surface-close signals to
  a long-running helper instead of orphaning it, porting `dd55e585`'s
  corrected mktemp/trap ordering, not the original's). — **Met**,
  `check-quickshell-qml` clean.
- [x] `scripts/dwm-settings-provider`: replace the placeholder `system
  administration` record with a real `dwm-system-management` availability
  check. — **Met**, with one deviation from the doc's literal diff, disclosed
  here: the doc names this capability `updates`, but that id was already
  taken by UPDATE-003's `lyona-update` capability in the same `system`
  section. Used `package-updates` instead (label "System updates", matching
  the doc) to avoid two capabilities silently colliding on one id.
- [x] `docs/SETTINGS-CAPABILITIES.md`: row for the new operations, and the
  upstream `#207` correction applied — **`unsupported` is a capability
  status, not an operation class.** — **Met**, both the "System and
  diagnostics" summary row and the "System Health and Administration"
  operations table corrected; a not-yet-implemented capability is *omitted*
  by selecting the highest fully implemented protocol minor, never
  advertised as `unsupported`.
- [ ] `Makefile`: `INSTALL_COMMANDS`, `check-system-management`,
  `check-quickshell-system-management`. — **Deliberately deferred to Sync
  Phase 2**, not done here: `scripts/dwm-system-management` and
  `tests/test-system-management.py` do not exist yet (Sync Phase 1 is
  decision-and-packaging only; the actual script lands in
  `SYNC-P2-UPDATE-SNAPSHOT.md`). Registering `INSTALL_COMMANDS` or a
  `check-system-management` target against files that do not exist would
  break `make install`/`check-install`/`make check` immediately — a real
  sequencing gap in the phase document as written, not a shortcut. Land this
  half of the Makefile diff together with the script itself in Sync Phase 2.

Acceptance: `make check-shell check-format check-quickshell-qml
check-arch-packages check-install check-settings` all pass — **Met**. The
manual on-a-real-CachyOS-install verification (`pacman -Si packagekit`,
`busctl --system introspect ... VersionM...`, importing `PackageKitGlib` via
`python3 -c`) is unverified in this sandbox — no live PackageKit/D-Bus
session here — and remains a real prerequisite to confirm before Sync Phase 2
starts, per the doc's own "If the last two fail, stop" instruction.

## Phase Completion

When all Phase 6 acceptance criteria pass:

1. Record delivered behavior and validation in `CHANGELOG.md`.
2. Update the Phase 6 status and limitations in `ROADMAP.md`.
3. Replace this file's active task set with the next phase's tasks — the
   upstream-ported system-management work indexed in `docs/UPSTREAM-SYNC.md`'s
   "The system-management port" section (Sync Phases 1–9).
4. Preserve incomplete or deferred work as explicit roadmap limitations.
