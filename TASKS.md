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
  `check-quickshell-qml` clean. **Bug found and fixed**: the ported script's
  `ulimit -f 16384` counts 512-byte blocks, not bytes — that was an 8 MiB
  cap, not the intended 16 KiB one. Corrected to `ulimit -f 32`
  (32 * 512 = 16384 bytes). The arithmetic is unambiguous (POSIX/bash's
  documented unit for `ulimit -f`), but actual enforcement is unverified —
  tested directly in this sandbox and `RLIMIT_FSIZE` is not enforced here at
  all (`dd` wrote 20000 bytes through a 16384-byte limit with no error),
  which looks like a container/sandbox restriction on that rlimit rather
  than a flaw in the fix.
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
- [x] `Makefile`: `INSTALL_COMMANDS`, `check-system-management`,
  `check-quickshell-system-management`. — Landed in **Sync Phase 2** as
  planned here: `INSTALL_COMMANDS` gained `scripts/dwm-system-management` and
  `check-system-management` now runs the new test suite.
  `check-quickshell-system-management` is **not** registered yet — there is
  still no QML consumer (`SystemManagementModel.qml` etc. do not exist until
  Sync Phase 3), so there is nothing for that target to run against.

Acceptance: `make check-shell check-format check-quickshell-qml
check-arch-packages check-install check-settings` all pass — **Met**. The
manual on-a-real-CachyOS-install verification (`pacman -Si packagekit`,
`busctl --system introspect ... VersionM...`, importing `PackageKitGlib` via
`python3 -c`) is unverified in this sandbox — no live PackageKit/D-Bus
session here — and remains a real prerequisite to confirm before Sync Phase 2
starts, per the doc's own "If the last two fail, stop" instruction.
**That gate was not cleared before Sync Phase 2 began** — the project owner
directed moving on regardless; Sync Phase 2's own acceptance section below
carries the same unverified-live-daemon caveat forward rather than treating
it as resolved.

### Sync Phase 2: Bounded Read-Only Update Snapshot

Upstream: `#208` (`bd87fd3c`, the actual ported baseline — see the
correction below). Doc: `docs/SYNC-P2-UPDATE-SNAPSHOT.md`. Delivers
`scripts/dwm-system-management snapshot`: one bounded, read-only,
machine-readable protocol-minor-0 snapshot of pending Arch updates. No
mutation, no journal, no root, no polkit prompt.

- [x] Port `scripts/dwm-system-management` (bounds/codecs, the
  `UpdateBackend` protocol, `PackageKitBackend`, `build_snapshot`, `main`).
  — **Met**, ~830 lines. **Correction to the phase document, found during
  implementation**: fetched `#208`'s actual commit (`bd87fd3c`) rather than
  trusting the doc's line-number citations, and confirmed none of "the four
  Fedora couplings" (§3a–§3c: `read_fedora_identity()`,
  `require_mutation_safe()`, the RPM version gate, Fedora-branded operator
  strings) exist in that baseline at all — they belong to later upstream
  commits coupled to the recovery journal and mutation dispatch, which this
  phase explicitly excludes. The doc's "with `#232`/`#241` folded in" framing
  was also checked directly against each commit's own patch and found
  overstated: those two commits are 19 and 121 lines respectively; the
  5,752-line file size at `#241` comes almost entirely from unrelated
  intervening PRs (the journal/mutation work), not from them. Full reasoning
  recorded in `docs/SYNC-P2-UPDATE-SNAPSHOT.md` section 3's correction note.
- [x] §3d (`#232`'s DNF5 install-preview fix) — **not ported**, recorded as a
  deliberate exclusion in `docs/P6-SYSTEM-MANAGEMENT.md`. There is no live
  PackageKit/alpm daemon in this sandbox to confirm whether the alpm backend
  ever needs the same install-vs-update reconciliation DNF5 does; the
  snapshot layer keeps `#208`'s stricter pre-`#232` check.
- [x] §5 security severity — no code change needed; PackageKit's `InfoEnum`
  vocabulary is shared across backends, not Fedora-specific, so every update
  already reports `unknown` severity honestly on Arch without any porting
  work.
- [x] §5 restart-requirements heuristic — **implemented**
  (`_restart_heuristic_hint()`), applied only when a transaction succeeds
  with pending updates but zero `RequireRestart` signals were seen at all.
  Maps kernel/`systemd`/`glibc`/`dbus` updates to the existing `system`
  restart value and everything else to `unknown` — never a fabricated
  `none`. 5 dedicated test cases, including that a real backend
  `RequireRestart` signal is never overridden by the heuristic.
- [x] `snapshot_generation()`'s domain-separation seed renamed from
  upstream's `dwm-titus-update-plan-v1` to `lyona-update-plan-v1` — an
  internal, non-user-visible constant; test expectations recomputed and
  hardcoded the same way upstream's test does (not derived at test time,
  to also catch regressions in the hashing algorithm itself).
- [x] `tests/test-system-management.py` — ported from upstream's `#208` test
  file (354 lines) nearly unchanged (it had no Fedora/RPM cases to discard —
  those belong to the same later commits as §3a/§3b), plus 5 new cases for
  the restart heuristic. — **Met**, 19/19 passing.
- [x] `Makefile` registration (`INSTALL_COMMANDS`, `check-system-management`)
  — see Sync Phase 1's now-checked item above.

Acceptance:

- `make check-system-management` (19 unit tests against fixture backends) and
  `make check-install` both pass — **Met**.
- The snapshot is genuinely read-only and never prompts for privilege — **Not
  verified end-to-end**: no live PackageKit daemon in this sandbox
  (`packagekit`'s `PackageKitGlib` typelib is not installed here, though
  `python-gobject` itself is). What *was* verified directly: running
  `scripts/dwm-system-management snapshot` for real exercised the guarded
  lazy-import failure path exactly as designed — a complete, correctly
  degraded `missing-provider`/`unavailable` protocol snapshot, exit `0`, no
  traceback. The real-daemon checks (`sudo diff -r /var/lib/pacman/sync`
  before/after, `db.lck` absence, no polkit prompt, real `package_id`
  four-field shape, whether `RequireRestart` populates at all) still need a
  CachyOS install with `packagekit` actually running — carried forward as
  the same open prerequisite Sync Phase 1 already recorded, not newly
  introduced here.
- Bounds and degradation (network down, `packagekit` uninstalled,
  `python-gobject` uninstalled, oversized/malformed PackageKit data, several
  hundred pending updates) — **Met** for everything exercisable without a
  live daemon: covered by the fixture-backed unit tests
  (`test_source_failures_preserve_the_complete_protocol_shape`,
  `test_record_count_limit_discards_the_whole_inventory`, the identity/
  classification rejection tests) and the real `missing-provider` run above.

### Sync Phase 3: Update Model and the System Settings Pane

Upstream: `#209`, `#210`. Doc: `docs/SYNC-P3-SYSTEM-PANE.md`. First
user-visible behavior of the whole port: Settings → System gains a real,
read-only Arch update status pane alongside the existing `lyona-update`
group UPDATE-003 already built there.

- [x] `config/quickshell/systemmanagement/SystemManagementModel.qml`
  (new, ~250 lines) — a `Scope` root model instantiated once in `shell.qml`,
  following the same `settingsVisible`/`openSettings()`/`closeSettings()`
  lifecycle every other Settings-only model already uses (`NetworkModel`,
  `AppearanceModel`, `PanelSettingsModel`, …): never polled, the snapshot
  fetch is gated on `settingsVisible`, and closing the section stops any
  fetch this model owns. — **Met**.
- [x] Strict, all-or-nothing snapshot parsing, per the doc's "parser rules
  that must not be softened": a missing/unsupported
  `system-management-protocol` header or a snapshot without a trailing
  `complete\tsnapshot` discards the whole result rather than rendering a
  partial one; every mandatory provider/state/action ID for protocol minor 0
  must be present; list identity (duplicate package IDs) and a record-count
  cap are re-checked model-side; every enum field (`validStatus`,
  `validSeverity`, `validInstallability`, `validRestart`, `validPlanAction`,
  `validErrorCode`) is checked against an explicit allowlist rather than
  passed through to the UI. — **Met**, exercised end-to-end by the new
  nested-X11 test (below), not just by source inspection.
- [x] `SystemSettingsPane.qml`: added a "System updates" section (provider/
  recovery status line, a responsive `GridLayout` of update-summary/
  last-refresh/restart-guidance `StatusCard`s, the pending-update and
  dependency-preview lists, and the read-only caption the doc specifies —
  *not* Sync Phase 7's mutation-capable wording) — **coexisting** with, not
  replacing, the pre-existing "lyona" group from UPDATE-003 and the generic
  `system health`/`system authorization` capability rows. — **Met**. The
  `additionalCapabilities` filter also now excludes `package-updates`
  (Sync Phase 1's capability id), which gets this dedicated section instead
  of falling through to the generic list.
- [x] `SettingsModel.qml` / `SettingsWindow.qml` / `shell.qml` wiring —
  **Met**: `systemManagementModel` property, open/close pairing in
  `activateSection`, a `refresh()` hook, `required property var` threading
  through `SettingsWindow`, one `SystemManagementModel {}` instantiation in
  `shell.qml`, `import qs.systemmanagement`, and the four IPC probes the doc
  specifies (`systemManagementUpdateCount`, `systemManagementPackageChangeCount`,
  `systemManagementSnapshotState`, `systemManagementRestartState`).
- [x] `tests/test-quickshell-system-management.sh` (new) — a grep-based
  static contract test matching the existing `test-quickshell-update-model.sh`
  idiom (this sandbox cannot run a live Quickshell session in every context,
  so source-level contract checks are the first line of coverage): lifecycle
  wiring, all-or-nothing parsing markers, the restart-heuristic vocabulary,
  no privilege escalation from the pane/model, no mutation entry point yet,
  and the capability-filter coexistence rule. — **Met**, 
  `check-quickshell-system-management` passing.
- [x] `tests/test-quickshell-system-management-xvfb.sh` (new) — a real
  nested-X11 test (Xvfb + `dwm` + `quickshell`, following
  `test-quickshell-large-surfaces-xvfb.sh`'s skeleton) with a stubbed
  `dwm-system-management` emitting one pending `linux-cachyos` update (to
  exercise the Sync Phase 2 restart heuristic's `system` branch) and one
  dependency-preview row. **Actually run in this sandbox and passing** —
  unlike the pre-existing `check-quickshell-settings-xvfb` gap (`xkbset`
  unavailable), this test needs no input/accessibility surface, so it is
  real, executed verification, not a written-but-unexercised test: it opens
  Settings, selects "system", polls the snapshot to `loaded`, asserts the
  parsed update/package-change counts and the restart state via the new IPC
  probes, then re-triggers a (deliberately slowed) fetch and immediately
  navigates away, polling to confirm no `dwm-system-management` process
  survives past its section closing. — **Met**,
  `check-quickshell-system-management-xvfb` passing end-to-end.

Acceptance:

- `make check-quickshell-qml check-quickshell-system-management
  check-quickshell-system-management-xvfb check-settings` all pass —
  **Met**, and unlike every other Sync Phase so far, the xvfb leg is real
  executed coverage in this sandbox, not a documented gap.
- `make check-quickshell-large-surfaces-xvfb` (which exercises the shared
  `shell.qml`/`SettingsWindow.qml` surface this phase modified) still passes
  with closed-shell CPU at baseline — **Met**, confirming the new model adds
  no idle polling.
- Read-only claim: the pane never calls a mutation entry point — **Met** by
  construction (no `installAll`/`cancelUpdate`/`refreshMetadata` function
  exists yet) and asserted by the static contract test. The doc's own manual
  CachyOS-install checks (open with updates pending vs. none, behavior with
  `packagekit` uninstalled on a live system) remain unverified here, carried
  forward from Sync Phase 1/2's same open prerequisite.

### Sync Phase 4: Live Discovery Monitoring

Upstream: `#237`, `#238`, `#260`. Doc: `docs/SYNC-P4-DISCOVERY-EVENTS.md`.
Replaces "click Reload status and hope" with a bounded subscription: while
the System pane is open, the helper watches PackageKit's manager signals and
tells the shell when to re-read. **The last read-only Sync Phase** —
mutation and the recovery journal are next.

- [x] `scripts/dwm-system-management`: `UpdateEventMonitor`, `watch_update_events()`,
  the `watch-updates` command — ported from upstream's real `a30f5fed`
  (#238) source (fetched and read in full, not worked from the doc's
  paraphrase). Distro-neutral: it only subscribes to PackageKit manager
  signals over raw `Gio` D-Bus, never touches `PackageKitGlib`'s
  alpm-vs-dnf-backend-specific transaction machinery. — **Met**,
  `check-system-management` (30 tests, up from 19 — 10 new
  `UpdateEventMonitorTests`, including a real `dbus-run-session`
  integration test against `tests/fixtures/system-update-events-bus.py`,
  actually run in this sandbox, not just written).
- [x] `config/quickshell/systemmanagement/SystemDiscoveryCycle.js` (new, 71
  lines) — the pure two-round (initial/settling) cycle state machine,
  ported verbatim. — **Met**. Directly unit-tested (not only through the
  UI, per the doc's own instruction) with 16 cases via `qmltestrunner`
  (Qt's official QML `TestCase` harness, already a hard dependency of this
  shell — `qmltestrunner` ships with `qt6-declarative`, which `quickshell`
  itself depends on). **Environment gotcha found and fixed**: this Arch dev
  host has both `qt5-declarative` and `qt6-declarative` installed, and the
  plain `qmltestrunner` resolved via `PATH` is the Qt5 build — a
  *different* binary, not a symlink — which silently exits nonzero with
  zero output on this file's Qt6-only `import QtQuick`/`import QtTest`.
  The test script now targets `/usr/lib/qt6/bin/qmltestrunner` explicitly.
- [x] `config/quickshell/systemmanagement/SystemProviderDiscovery.qml` (new,
  ~200 lines) and `SystemUpdateDiscovery.qml` (new, 3 lines) — the
  generic, five-domain-capable lifecycle ported directly from upstream's
  `a6d65c08` (#260) refactored form, per the doc's own instruction not to
  write an updates-only version first. Only `domain: "updates"` has a
  helper behind it at this boundary; `time`/`locale`/`accounts`/`printers`
  are Sync Phase 9. — **Met**.
  **Correction to the phase document, found during implementation**: the
  doc's "Lyona adaptation" instructed wrapping `monitor.command` in
  `Commands.terminatingCheckedCommand(...)`. This is wrong for a streaming
  event source and was caught by the xvfb test genuinely failing (the
  snapshot never left `"idle"` once the fixture stub actually implemented
  `watch-updates` as a real resident process instead of exiting
  immediately) — both `checkedCommand` and `terminatingCheckedCommand`
  redirect the wrapped command's stdout to a temp file and only `cat` it
  once the child exits, which defeats live line-by-line streaming entirely
  (`ready`/`changed` would only ever arrive as one batch at shutdown, after
  `SplitParser` has nothing left to read incrementally). Fixed by using
  `Commands.systemManagementCommand(action, args)` directly, unwrapped —
  matching upstream's own code exactly. This carries no orphaning risk
  either: `helperCommand`'s own script chain reaches the real helper via
  `exec`, so this `Process`'s PID already *is* the helper, and
  `monitor.signal(15)`/`monitor.signal(9)` reach it directly. Also fixed
  along the way: a duplicate `onExited` handler tripped
  `quickshell-qmllint` (`QProcess::ExitStatus` isn't exposed to it); removed
  as genuinely redundant with the existing `onRunningChanged` handler, which
  already covers every exit path.
- [x] `SystemManagementModel.qml`: owns a `SystemUpdateDiscovery`, coalesces
  reads through `take()`/`beforePublish()`/`complete()` rather than firing
  one snapshot fetch per signal — a request arriving mid-fetch is recorded
  (`snapshotPending`) and replayed exactly once. `openSettings()` /
  `closeSettings()` now delegate to the discovery model instead of firing
  an eager fetch directly. **Deliberate simplification**: upstream's
  `Component.onCompleted: Qt.callLater(operationModel.requestSnapshot)`
  (an eager read at whole-app startup, independent of the pane ever being
  opened) was not ported — it exists to prewarm data before first open, but
  it's tied to `operationModel` (Sync Phase 6+, not built yet), and adding
  a bespoke prewarm call for this phase alone would contradict Sync Phase
  3's own established "never polled, on-demand only while `settingsVisible`"
  contract. The tradeoff: first-open latency now depends on how quickly the
  monitor reaches `ready` (or `failed`) — up to 12 s in the pathological
  case — instead of being masked by data fetched before the user ever
  opened Settings.
  **Bug found and fixed after review**: the relaunch-on-completion logic
  originally lived in `finishSnapshot()`, called from
  `StdioCollector.onStreamFinished` — which fires *before*
  `Quickshell.Io.Process` updates `running` to `false`, and `Qt.callLater`
  gives no ordering guarantee relative to that transition either. A queued
  relaunch (or `discoveryModel`'s own `complete()`-triggered
  `snapshotRequested` signal, which fires from the same call) could
  therefore reach `requestSnapshot()` while the previous process was still
  reported `running`. Reassigning `snapshotProcess.running` to `true` while
  it is already `true` is a no-op, so the new read silently never launched
  — and when the *old* process's real `runningChanged` eventually fired,
  its `!root.snapshotAttempted` fallback path (guarded by a flag the new,
  never-launched call had already reset to `false`) completed the *new*
  cycle with the *old* process's exit. Fixed by moving all ownership
  clearing and the relaunch trigger into `onRunningChanged`'s real
  `!running` observation — the only point that observation is trustworthy
  — leaving `finishSnapshot()` as pure cycle bookkeeping; `closeSettings()`
  no longer clears `snapshotOwned` directly either, for the same reason.
  Also added the explicit `snapshotProcess.running` guard in
  `requestSnapshot()` itself (defense in depth: correct now that ownership
  is gated properly, but keeps any future caller from reintroducing the
  no-op-reassignment failure mode) and clear `snapshotProcess.cycleToken`
  once a cycle completes. Verified by reverting to the pre-fix shape and
  confirming the extended static contract test — which checks
  `finishSnapshot()` never touches ownership/relaunch and
  `onRunningChanged` is the sole place that does — fails against it, then
  passes again with the fix restored.
- [x] `SystemSettingsPane.qml`: surfaces `discoveryDetail` as a warning line
  ("Connecting to update change notifications...", the settling-read
  reconciliation message, or the failed-monitor message) — **Met**.
- [x] `shell.qml`: `systemManagementDiscoveryStatus()` IPC probe — **Met**.
- [x] `tests/test-quickshell-system-management.sh` (Sync Phase 3's static
  contract test) updated for the new coalescing shape (the old
  `if (!root.settingsVisible || snapshotProcess.running) return;` guard
  moved into `requestSnapshot()`) and extended with Sync Phase 4 assertions
  (cycle/discovery wiring, the unwrapped `monitor.command`, the 12 s/1.5 s
  timers, `monitor.signal(15)`/`monitor.signal(9)`, the Python
  `UpdateEventMonitor`/`watch_update_events` dispatch, and that the monitor
  code never imports `PackageKitGlib`). — **Met**.
- [x] `tests/test-quickshell-system-management-xvfb.sh` extended: the stub
  `dwm-system-management` now implements `watch-updates` for real (emits
  `ready`, then blocks on `SIGTERM` like the genuine helper does, rather
  than exiting immediately) so the coalesced-read-via-discovery path is
  exercised for real, not bypassed through the `failed` fallback. Verifies
  `systemManagementDiscoveryStatus` reaches `idle:ready`, and — because the
  monitor is now a genuinely long-running process instead of the bounded
  snapshot fetch (whose `pgrep`-based liveness checks turned out unsound;
  see Sync Phase 3's fix note) — a real `pgrep -f 'dwm-system-management
  watch-updates'` check that confirms `stopMonitor()`'s
  `signal(15)`-then-`signal(9)` sequence actually reaches and kills the
  resident process when the Settings window closes. — **Met**, and actually
  run in this sandbox: `check-quickshell-system-management-xvfb` passes,
  including this new orphan-process assertion.

Acceptance:

- `make check-quickshell-qml check-system-management
  check-quickshell-system-management check-quickshell-system-management-xvfb
  check-quickshell-system-discovery-cycle` all pass — **Met**, and (unlike
  every prior Sync Phase) every leg here is real executed coverage in this
  sandbox: the Python monitor against a real private D-Bus session, the
  pure JS state machine via `qmltestrunner`, and the full QML lifecycle via
  a genuinely long-running Xvfb stub.
- `make check-quickshell-large-surfaces-xvfb` still passes with closed-shell
  CPU at baseline (0.50%, within the established threshold) — **Met**,
  confirming the discovery monitor (a blocked `GLib.MainLoop`, per the doc)
  adds no busy-polling.
- The doc's remaining manual CachyOS-install checks (`pkcon refresh`
  triggering a re-read live, PackageKit restart recovery via
  `NameOwnerChanged`, a real `pacman -Syu` reaching `blocked` rather than a
  read-per-signal storm) remain unverified here — no live PackageKit daemon
  in this sandbox, the same open prerequisite carried since Sync Phase 1.

## Phase Completion

When all Phase 6 acceptance criteria pass:

1. Record delivered behavior and validation in `CHANGELOG.md`.
2. Update the Phase 6 status and limitations in `ROADMAP.md`.
3. Replace this file's active task set with the next phase's tasks — the
   upstream-ported system-management work indexed in `docs/UPSTREAM-SYNC.md`'s
   "The system-management port" section (Sync Phases 1–9).
4. Preserve incomplete or deferred work as explicit roadmap limitations.
