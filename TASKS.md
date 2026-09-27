# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Phase 6
completion evidence is recorded in `ROADMAP.md`'s Phase 6 "Completion
Evidence" section, `docs/UPSTREAM-SYNC.md`, and `CHANGELOG.md`.

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
Phase 7 actually closes is the gap `docs/RELEASING.md` already states plainly:
*"This build has been verified to produce a bootable ISO on Arch Linux, but
it has not been boot-tested end-to-end on real hardware or in a VM."* That
sentence — real boot, real install, real upgrade/rollback, on real or
virtualized Arch hardware — is Phase 7's actual remaining work. It cannot be
finished from this sandbox: there is no KVM/VM tooling, GPU, or physical
machine available here, and `docs/RELEASING.md` itself requires disposable
VM/ISO qualification to happen outside `/tmp` and outside this kind of
throwaway environment. Every item below is written to be carried out by
whoever has that hardware, using the acceptance criteria and existing
automated coverage as the bar.

**Open questions this first-pass breakdown does not resolve** (need your
input, not a guess):

- Is legacy BIOS an actual target, or is UEFI-only acceptable long-term?
  `docs/RELEASING.md` currently states plainly that the wizard "cannot boot
  BIOS/legacy systems" and only offers a manual `archinstall` fallback for
  that case — Phase 7's own ROADMAP wording ("legacy BIOS where supported")
  already hedges on this, but doesn't say which way.
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
  `dwm_packages arch required|desktop|iso` (`scripts/dwm-packages.sh`) stays
  in sync with them — `check-arch-packages` (67 packages, passing in this
  sandbox as of 2026-09-19).
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
  proprietary driver stack against the current Arch `nvidia`/`nvidia-dkms`
  packages, not just that the flag is threaded through correctly.
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

- [ ] Boot the built ISO in a KVM virtual machine (per `docs/RELEASING.md`'s
  own instruction), run `lyona-install` to completion against a UEFI target,
  and reboot from the installed virtual disk.
- [ ] Verify LightDM presents a session, dwm starts, and the managed
  Quickshell shell (panel, Settings, Control Center) comes up without manual
  repair.
- [ ] Verify the manual fallback path (boot the ISO, run `archinstall`
  directly, then `/root/lyona-postinstall.sh` against the mounted target)
  produces the same working result as the wizard path, at least once.
- [ ] Record the source ISO checksum, firmware mode, architecture,
  package-resolution result, first-boot result, and any untested hardware —
  `docs/RELEASING.md`'s own qualification-recording instruction.

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
- [ ] Qualify `lyona-update apply` and `lyona-update rollback` against a real
  previous release tarball on a real installed system (VM or hardware), not
  just the test harness's synthetic fixtures — confirm user data and
  managed-configuration ownership survive an actual version-to-version
  upgrade and a subsequent rollback.
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

- [ ] Resolve the open legacy-BIOS question above, then qualify or
  explicitly document it as unsupported.
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

Tracked independently of the Phase 7 checklist above: `docs/UPSTREAM-SYNC.md`
and its per-sprint `docs/SYNC-SPRINT-N-*.md` documents own the day-to-day
detail. `docs/UPSTREAM-SYNC.md`'s own "Commit and tracking" section requires
every sprint item to also land a `TASKS.md`/`CHANGELOG.md`/`docs/evidence/`
update in the same PR, so completed items are pinned here too, not only in
`CHANGELOG.md`.

- [x] Sync Sprint 8 S8-01 — cross-tag window overview keyboard navigation
  (arrow keys, Home/End move the selection, Enter activates it; selection
  wraps and clamps; the selected card gets a visible highlight), issue
  `#350` — `tests/qml/tst_overview_selection.qml` (pure selection math,
  `qmltestrunner`), `tests/test-quickshell-overview.sh` (wiring pins).
  Evidence: `docs/evidence/s8-01-overview-keyboard-nav.md`, which records a
  passing Qt 6 `qmltestrunner` run (11 selection tests, 148 in the suite).
- [x] Sync Sprint 8 S8-02 to S8-04 — multi-monitor labels, type-to-filter and
  close-from-card, issue `#350`. UI in #138, model in Sprint 10 S10-01. Verified
  by `tests/test-quickshell-overview-xvfb.sh` (`make check-quickshell-overview-xvfb`,
  22 assertions), `tests/qml/tst_overview_filter.qml`, and the **Full suite
  (manual)** run on `main`: https://github.com/technicks89/Lyona/actions/runs/36242445295. Not tested: real key presses and mouse
  clicks against the popup, and a multi-monitor label check (single stub
  monitor only).
- [x] Sync Sprint 10 — completion audit
  (`docs/SYNC-SPRINT-10-COMPLETION-AUDIT.md`). S10-01 to S10-06 and S10-08
  done; S10-07 (issue `#147`) done on its own terms — the plan only asks for
  a ledger making hardware-gated checks visible, not for running them. Its
  table (`docs/SYNC-SPRINT-10-COMPLETION-AUDIT.md#s10-07-qualification-ledger-for-sprints-closed-with-hardware-checks-open`) is the standing tracker for what still needs real
  hardware or a real install: the Picom NVIDIA backend, fresh-install media
  defaults on both ISOs, a full privileged `lyona-update` run, Settings panes
  and floating toggles on a slow provider, a Flathub-remote refusal, a fresh
  LightDM login, a live PackageKit transaction, a live polkit denial, and
  D-4's read-only `pacman.lck` check on a real CachyOS install. None of that
  is done; only its visibility is.
- [x] Sync Sprint 11 S11-04 -- keep the xvfb runtime test's "bad config" notification off the real desktop, issue `#155`
  -- `tests/test-xvfb-runtime.sh`. Evidence: `docs/evidence/s11-04-notification-capture.md`.
- [x] Sync Sprint 11 S11-01 -- shell text stays readable on hover and selected surfaces (completes S6-03, closes `#116`),
  issue `#152` -- `config/quickshell/core/Theme.qml` and 15 components; `tests/test-quickshell-theme-contrast-xvfb.sh`
  (`make check-quickshell-theme-contrast`). Evidence: `docs/evidence/s11-01-theme-contrast.md`. Not verified by eye.
- [x] Sync Sprint 11 S11-06 -- Qt palettes for qt5ct/qt6ct and a GTK 2 theme, issue `#157` -- `scripts/lyona-gtk-theme`,
  `scripts/theme-apply.sh`; `tests/test-app-palettes.py`, `tests/test-qt-palette-xvfb.sh`,
  `tests/test-theme-apply-qt-palette.sh`. Evidence: `docs/evidence/s11-06-qt-gtk2-palettes.md`. GTK 2 rendering not
  verified.
- [x] Sync Sprint 11 S11-07 -- square popups and a 1 px focus ring (decision D-10), issue `#158` --
  `config/quickshell/core/Theme.qml`, two notification files; pins in `tests/test-quickshell-design-system.sh` and
  `tests/test-quickshell-accessibility.sh`. Evidence: `docs/evidence/s11-07-square-popups.md`. Not verified by eye.
- [x] Sync Sprint 11 S11-02 -- broadcast the GTK and icon theme over XSETTINGS (upstream #351), issue `#153` --
  `scripts/theme-apply.sh`; `tests/test-dwm-settings-theme.sh`. Evidence:
  `docs/evidence/s11-02-xsettings-broadcast.md`. A live GTK application repainting is not verified.
- [x] Sync Sprint 11 S11-03 -- clicking the empty panel closes open popups and floating windows (upstream #340), issue
  `#154` -- `config/quickshell/panel/DwmPanel.qml`; pins in `tests/test-quickshell-panel-menus.sh`. Evidence:
  `docs/evidence/s11-03-panel-click-away.md`. Bar buttons keeping their clicks is not verified.
- [x] Sync Sprint 11 S11-05 -- document desktop dependencies and install profiles for Arch (upstream 2a0e9b3), issue
  `#156` -- `docs/src/dependencies.md`; drift check in `tests/test-arch-packages.sh`. Evidence:
  `docs/evidence/s11-05-dependencies-page.md`. The mdBook build was not run.
- [x] Sync Sprint 11 S11-09 -- a Picom window corner-radius slider (D-12), issue `#160` -- `scripts/dwm-settings-picom`,
  `config/quickshell/appearance/PicomModel.qml`, `config/quickshell/settings/PicomSettingsPane.qml`; tests in
  `tests/test-picom.py`, `tests/test-picom-xvfb.py`. Evidence: `docs/evidence/s11-09-picom-corner-radius.md`. Rounded
  corners not verified on a real compositor.
- [x] Sync Sprint 11 S11-08 -- a layout switcher in the Control Center (D-12), issue `#159` -- `dwm.c`,
  `scripts/dwm-quickshell-state`, `config/quickshell/state/DwmState.qml`,
  `config/quickshell/controlcenter/ControlCenterWindow.qml`; tests in `tests/test-xvfb-runtime.sh`,
  `tests/test-quickshell-state.sh`, `tests/test-quickshell-panel-menus.sh`. Evidence:
  `docs/evidence/s11-08-layout-switcher.md`. The UI was not run by hand.
- [ ] Sync Sprint 9 S9-01 -- live per-window thumbnails, spike only (issue `#350`) -- feasible only with Picom running
  (off-tag `XGetImage` works with it, fails with BadMatch without it; name-window-pixmap returned black); not
  implemented, maintainer decision needed. Evidence: `docs/evidence/s9-01-thumbnail-spike.md`.
- [x] Sync Sprint 9 S9-02 -- overview motion and visual polish, issue `#350` --
  `config/quickshell/overview/OverviewCard.qml`, `WindowOverview.qml`; pins in `tests/test-quickshell-overview.sh`;
  cases in `tests/qml/OverviewInteraction.qml`. Evidence: `docs/evidence/s9-02-overview-motion.md`. Not judged by eye.
- [x] Sync Sprint 9 S9-03 -- overview accessibility and keyboard-only pass, issue `#350` -- `OverviewModel.qml`,
  `OverviewCard.qml`, `WindowOverview.qml`; `tests/test-quickshell-accessibility.sh`,
  `tests/test-overview-keyboard-xvfb.py`. Evidence: `docs/evidence/s9-03-overview-accessibility.md`. No screen reader
  or second monitor tried.
- [x] Sync Sprint 9 S9-04 -- overview idle-CPU and many-window test, issue `#350` -- `tests/test-overview-load-xvfb.py`.
  Evidence: `docs/evidence/s9-04-overview-load.md`. Virtualization is not needed up to 600 windows; idle windows are
  10 s, not the plan's 30 s.
- [ ] Sync Sprint 12 -- whole-repo review findings
  (`docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md`), 18 items, all findings recorded
  unreviewed; awaiting maintainer review. D-13 (blank and lock after 10 min),
  D-14 (no release signing for now) and D-17a (one ISO, NVIDIA detected) are
  decided, as are D-15 (remove checkout mode), D-16 (system copy only, plus a
  developer override) and D-17b (keep per-screen panels). No item is gated.
- [x] Sync Sprint 12 S12-01 -- rollback restores only what root has checked, issue `#164` -- `scripts/lyona-update-root`,
  `scripts/lyona-update`, `docs/src/updating.md`; tests in `tests/test-lyona-update-root-backups.sh`
  (`make check-update-root-backups`, container-only, and a Full suite job) and `tests/test-lyona-update.sh`. Evidence:
  `docs/evidence/s12-01-rollback-restore.md`. A real polkit prompt and a rollback on real hardware are not tested.
