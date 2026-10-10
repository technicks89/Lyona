# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Phase 6
completion evidence is recorded in `ROADMAP.md`'s Phase 6 "Completion
Evidence" section, `docs/sprints/UPSTREAM-SYNC.md`, and `CHANGELOG.md`.

## Active Phase: Arch Image and Release Qualification

Phase 7 begins from the completed system-management port (Phase 6). Its
scope is narrower than the phases before it: the archiso profile
(`archiso/packages.x86_64`, `archiso/pacman.conf`, `archiso/airootfs/`), the
builder (`scripts/build-lyona-arch-iso.sh`), the unattended installer wizard
(`archiso/airootfs/root/lyona-install.sh`/`lyona-postinstall.sh`), and
`lyona-update`'s own check/apply/rollback path all already exist and are
individually exercised by automated tests
(`check-arch-packages`, `tests/test-arch-iso-builder.sh`,
`tests/test-lyona-update.sh`, `tests/test-install-preservation.sh`). What
Phase 7 closes is real boot, real install and real upgrade/rollback. The first
VM runs are done: on 2026-10-03 an image built on the maintainer's host
installed in a UEFI KVM virtual machine, three times, the last reaching a
working desktop with no manual help (recorded in `docs/RELEASING.md`). On
2026-10-09 the `2026.10.0-beta.6` images installed fresh with btrfs and ext4,
and an update from `beta.5` to `beta.6` applied and rolled back, in the same
kind of VM (`docs/evidence/280-config-split.md`). Real hardware, and the paths
those VMs did not exercise, remain.
Every item below uses the acceptance criteria and existing automated coverage
as the bar.

**Open questions this first-pass breakdown does not resolve** (need your
input, not a guess):

- Is legacy BIOS a qualified target? It boots: since #235 the wizard installs
  GRUB for both UEFI and a legacy BIOS (MBR disk, ext4 `/boot`), as
  `docs/RELEASING.md` says. But it has not been qualified, in a VM or on
  hardware, and Phase 7's ROADMAP wording ("legacy BIOS where supported")
  does not say whether it must be.
- Which specific hardware and VM targets actually matter for the matrix
  (ARCH-004 below)? The ROADMAP names categories (UEFI, common display
  configs, audio, networking, suspend, NVIDIA) but not concrete machines/VM
  configurations to qualify against.
- Is there real NVIDIA hardware available to qualify the opt-in driver path
  against, or does that stay a documented, unqualified limitation for this
  release?

Keep Phase 7 reviewable through these ordered boundaries. Finish, validate,
and merge each before starting the next:

1. ARCH-001 — archiso profile and package-manifest qualification against the
   currently supported Arch release.
2. ARCH-002 — first real boot/install qualification (the explicit
   `docs/RELEASING.md` gap above).
3. ARCH-003 — installation, upgrade, migration, and rollback path
   qualification on a real installed system.
4. ARCH-004 — VM/hardware matrix and release-notes limitation statements.

### ARCH-001: Archiso Profile and Package-Manifest Qualification

- [x] `archiso/packages.x86_64`/`archiso/pacman.conf` exist and
  `dwm_packages arch iso` (`scripts/dwm-packages.sh`) stays in sync with
  them — `check-archiso`. Since #229 the image carries only what the live
  medium runs (7 packages on top of `releng`); the desktop was 66 packages the
  new system downloads anyway.
- [x] `scripts/build-lyona-arch-iso.sh --profile-only` stages the branded
  profile and stamps `VERSION`/commit/label into every required field without
  needing root or `mkarchiso` — `tests/test-arch-iso-builder.sh` (passing in
  this sandbox as of 2026-09-19).
- [ ] Run the real (non-`--profile-only`) build on an Arch host with
  `archiso` installed (`sudo scripts/build-lyona-arch-iso.sh --output
  release/`) and confirm `mkarchiso` itself resolves every package in the
  current official repositories without a missing/renamed/moved package —
  this sandbox has never actually invoked `mkarchiso`, only the staging step.
- [ ] Confirm the NVIDIA opt-in path in `lyona-install.sh`/
  `lyona-postinstall.sh` (`LYONA_NVIDIA_DRIVER=1`) actually installs a working
  proprietary driver stack against the current Arch `nvidia-open`/
  `nvidia-open-dkms` packages, not just that the flag is threaded through
  correctly. (Arch dropped `nvidia`/`nvidia-dkms`; the open modules need a
  Turing or newer GPU. Older cards get the 580xx or 470xx legacy driver, Sync
  Sprint 14, and a card no packaged driver supports stays on nouveau.)
- [ ] Re-validate the `archinstall` JSON schema in `lyona-install.sh` against
  whatever `archinstall` version the current `releng` profile actually pulls
  in — `docs/RELEASING.md` already flags this as version-sensitive and known
  to have been wrong for at least one prior `archinstall` release.

Acceptance:

- A real `mkarchiso` run on a current Arch host produces
  `lyona-VERSION-x86_64.iso` with no unresolved package and a correct
  `/etc/lyona-iso-release` stamp (checksum, label, commit, build date all
  present and correct).
- The NVIDIA opt-in path is proven against real NVIDIA hardware or stated as
  an explicit, unqualified limitation in release notes — never silently
  assumed to work.

### ARCH-002: First Real Boot and Install Qualification

- [x] Boot the built ISO in a KVM virtual machine (per `docs/RELEASING.md`'s
  own instruction), run `lyona-install` to completion against a UEFI target,
  and reboot from the installed virtual disk. Done 2026-10-03 (btrfs, no
  LUKS, no NVIDIA), with an image built on the maintainer's host; an image
  the release workflow built is still to do.
- [ ] Verify LightDM presents a session, dwm starts, and the managed
  Quickshell shell (panel, Settings, Control Center) comes up without manual
  repair. LightDM, dwm, the panel, the launcher and the power menu were
  verified in the 2026-10-03 VM; the Control Center, keybind viewer and
  overview too in the 2026-10-09 beta.6 VM, and Settings in the 2026-10-10 VM,
  where it offered and ran a downgrade and showed a cancelled prompt's outcome
  (`docs/evidence/324-328-install-update-rollback.md`).
- [ ] Verify the manual fallback path (boot the ISO, run `archinstall`
  directly, then `/root/lyona-postinstall.sh` against the mounted target)
  produces the same working result as the wizard path, at least once.
- [x] Record the source ISO checksum, firmware mode, architecture,
  package-resolution result, first-boot result, and any untested hardware —
  `docs/RELEASING.md`'s own qualification-recording instruction. Recorded
  there for the 2026-10-03 VM run; record each later run the same way.

Acceptance:

- At least one full wizard-path boot→install→reboot→working-desktop cycle is
  recorded, on UEFI, in a VM, with the exact evidence `docs/RELEASING.md`
  asks release notes to carry.
- The ISO is not treated as release-qualified (per `docs/RELEASING.md`'s own
  explicit statement) until this item is done at least once.

### ARCH-003: Installation, Upgrade, Migration, and Rollback Qualification

- [x] `lyona-update check|apply|rollback|backups` is unit-tested end to end
  (staged tarball verification, no in-place swap, backup restore) —
  `tests/test-lyona-update.sh`.
- [x] A repeated `make install`/`install-user` preserves existing user
  configuration and provenance stamps rather than clobbering them —
  `tests/test-install-preservation.sh` (passing in this sandbox as of
  2026-09-19).
- [x] Qualify `lyona-update apply` and `lyona-update rollback` against a real
  previous release tarball on a real installed system (VM or hardware), not
  just the test harness's synthetic fixtures — confirm user data and
  managed-configuration ownership survive an actual version-to-version
  upgrade and a subsequent rollback. Done 2026-10-09 in a VM only: a fresh
  `2026.10.0-beta.5` image install updated to `beta.6` with beta.5's updater,
  verified, and rolled back (`docs/evidence/280-config-split.md`); hardware is
  still to do.
- [ ] Qualify the existing-system installer (`install.sh`) against a
  pre-existing, non-lyona Arch install with real user data present, per
  `SPEC.md`'s existing-system installer contract.

Acceptance:

- A real upgrade-then-rollback cycle on an installed system leaves the
  system in the exact pre-upgrade state the unit tests already assert in
  isolation.
- `install.sh` on a real pre-existing Arch system does not lose or silently
  overwrite user data or configuration outside its documented, owned paths.

### ARCH-004: VM/Hardware Matrix and Release-Notes Limitations

- [ ] Legacy BIOS boots but is not yet qualified: resolve the question above,
  then qualify it or document it as unsupported.
- [ ] Qualify common display configurations (single monitor at minimum;
  multi-monitor if hardware is available — Phase 5's own real-hardware
  multi-monitor qualification is still separately outstanding too, see
  `ROADMAP.md`'s Phase 5 Completion Evidence).
- [ ] Qualify audio, networking, and suspend/resume on at least one real or
  virtualized target.
- [ ] Qualify or explicitly limitation-document NVIDIA hardware (open
  question above).
- [ ] Write the release-notes "tested Arch release, architectures, X11
  environments, known limitations" statement `docs/RELEASING.md` step 9
  requires, from the actual results of ARCH-001 through ARCH-004 rather than
  an assumed baseline.

Acceptance:

- Every category the ROADMAP names (UEFI, legacy BIOS, display, audio,
  networking, suspend, NVIDIA) has either a qualification result or an
  explicit, precise "untested"/"unsupported" statement — never left silently
  unstated.

## Parallel Track: Quickshell Upstream Sync

Tracked in `docs/sprints/UPSTREAM-SYNC.md` and each sprint's own document;
completed work is in `CHANGELOG.md` and `docs/sprints/completed/`. Open here
is only what is left (Sync Sprint 16 R16-61 replaced the checklist of finished
items that used to be kept here):

- [ ] Sync Sprints 4, 5 and 11 -- code complete; a green **Full suite (manual)**
  run and the hardware and by-eye checks in Sprint 10's S10-07 ledger
  (`docs/sprints/completed/SYNC-SPRINT-10-COMPLETION-AUDIT.md`) are open.
- [ ] Sync Sprint 12 -- implemented; sign-off needs a green Full suite on
  `main` and the checks in the doc's Close-out.
- [ ] Sync Sprints 14 and 15 -- implemented; real NVIDIA hardware (S14-04) and
  a live session (S15-05) are open.
- [ ] Sync Sprint 16 -- the 2026-10-03 whole-repo review's fixes
  (`docs/sprints/SYNC-SPRINT-16-REVIEW-FIXES.md`): merged (#228) and released
  in `2026.10.0-beta.2`; real hardware is open.
