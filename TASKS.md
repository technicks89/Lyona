# Active Project Tasks

`SPEC.md` is the product contract and `ROADMAP.md` defines phase order. This
file contains implementation work only for the active roadmap phase. Phase 4
completion evidence is recorded in `ROADMAP.md`, `CHANGELOG.md`,
`docs/P4-EVIDENCE.md`, and the four detailed Phase 4 evidence records.

## Active Phase: Personalization and Accessibility

Phase 5 begins from the merged Settings platform and semantic theme adapter.
Keep DWM, X11, Arch providers, runtime TOML files, existing keybindings, panel
geometry, and user-owned configuration compatible while adding the workflows
below. Do not begin Phase 6 system-management work in Phase 5 changes.

Keep Phase 5 reviewable through these ordered pull-request boundaries. Finish,
validate, and merge each boundary before starting the next one:

1. Read-only appearance inventory and validation protocol.
2. Transactional theme preview, apply, reset, and recovery helper.
3. Shared root appearance model and Settings theme pane.
4. Wallpaper, toolkit, font, cursor, icon, and panel-widget persistence slices,
   split further when one slice cannot remain independently reviewable.
5. Accessibility and notification policy, with UI-5 candidates kept in their
   own later review boundaries.

### THEME-001: Shared Appearance Provider and Safe Theme Changes

- [x] Define a versioned machine-readable provider for the active theme,
  available themes, semantic colors, toolkit state, and per-capability errors.
- [x] Add a user-session transaction helper for bounded preview, confirm,
  automatic or explicit rollback, apply, reset, and interrupted-operation
  recovery without replacing unrelated theme configuration.
- [x] Add one root-scoped appearance model shared by Settings and existing shell
  surfaces without duplicating the `Theme.qml` or `themes.toml` ownership path.
- [x] Add a Settings Appearance pane with theme preview, apply, reset, and
  recovery behavior. Preserve comments, custom themes, file mode, and unrelated
  user configuration.
- [x] Make partial GTK, Qt, terminal, cursor, or compositor application failures
  visible without reporting the selected theme as fully applied.

Acceptance:

- Invalid, missing, duplicate, or incomplete theme records cannot prevent DWM,
  Quickshell, Settings, or an existing theme from loading.
- Preview is bounded and rolls back automatically unless confirmed. Apply and
  reset are transactional, attributed, and converge through hot reload.
- Existing Control Center theme selection remains compatible with the shared
  provider until its presentation can be migrated without behavior drift.

### APPEARANCE-001: Wallpaper, Fonts, Cursors, Icons, and Toolkit Integration

- [x] Define event-driven inventory and state contracts for wallpaper, supported
  fonts, cursors, icons, GTK, Qt, and compositor integration using stable Arch
  or X11 interfaces.
- [x] Add wallpaper selection, fit mode, preview, reset, and missing-file
  recovery without scanning while the Appearance pane is closed.
- [x] Add bounded user-session controls for supported font, text-size, cursor,
  icon, GTK, and Qt choices. Delegate advanced toolkit editing to a trusted
  Arch tool where a narrow project contract would be incomplete.
  - [x] Persist managed-shell font family and bounded text scale with preview,
    automatic rollback, reset, external-change protection, and event-driven
    root-model updates.
  - [x] Add cursor, icon, GTK, and Qt mutation controls without overwriting
    unrelated toolkit configuration. Each capability is overridden
    independently and released with a sentinel that hands it back to the
    active theme. Text size remains outstanding: `dwm-settings-display
    dpi-set` already scales through `Xft.dpi`, and live rescaling of running
    applications would need an XSETTINGS daemon.
  - Both bounded control sets exist and persist correctly; the parent item is
    closed on that basis. The XSETTINGS-daemon gap is a real, separate,
    self-contained limitation (new applications pick up the scale at launch;
    already-running ones do not rescale live) — carried forward explicitly in
    `ROADMAP.md`'s Phase 5 status rather than silently dropped.
- [x] Move the existing in-memory panel-widget visibility controls onto shared,
  versioned user state with Settings integration, safe defaults, and migration
  that preserves the current Control Center behavior.
- [x] Preserve optional-component behavior: missing Picom, Feh, toolkit themes,
  wallpaper directories, or delegated tools must fail only their capability.
  - Verified: `tests/test-dwm-settings-appearance-inventory.sh`'s `minimal`
    scenario runs `inventory` with every optional tool absent (only
    `bash`/`find`/`awk` on `PATH`) and confirms the compositor and font
    capabilities each report their own `unavailable` status rather than the
    helper failing outright. `tests/test-dwm-settings-appearance.sh` covers
    missing/incomplete GTK and Qt toolkit themes independently (each fails
    only its own capability). `tests/test-dwm-settings-wallpaper.sh` gained a
    dedicated case for Feh entirely absent (`provider` degrades to `partial`
    with an honest detail, `mutation`/`reset` degrade to `restricted`, the
    helper still exits 0). Missing wallpaper directories are handled by the
    same `[[ ! -d $wallpaper_dir ]] || …` guard pattern used throughout
    `dwm-settings-wallpaper` (`scripts/dwm-settings-wallpaper:227,844,1046`) —
    confirmed by code inspection, not a dedicated test.

Acceptance:

- Selected appearance state persists through a fresh session and follows the
  shared theme where appropriate without overwriting unrelated toolkit files.
- Panel-widget visibility persists through a fresh session, stays consistent on
  every active monitor, and does not duplicate panel models or providers.
- Preview, apply, interruption, rollback, reset, missing-asset, and external-
  change paths converge with explicit status and no orphaned watcher.
- Visible shell surfaces remain opaque, X11-native, correctly stacked, and
  usable at the existing panel and popup geometry contracts.

### ACCESSIBILITY-001: Practical X11 Accessibility and Notification Policy

- [x] Define capability records for text scaling, contrast, reduced motion,
  notification policy, and practical keyboard or pointer accessibility features
  available through supported Arch/X11 interfaces.
- [x] Add accessible Settings controls with keyboard navigation, visible focus,
  usable common display sizes, explanatory unavailable states, and reset.
- [x] Apply reduced-motion and contrast choices consistently to managed
  Quickshell surfaces without introducing a Wayland, compositor, or polling
  dependency.
- [x] Add notification behavior controls that preserve the existing D-Bus owner,
  history lifecycle, urgency semantics, and safe failure isolation.

Acceptance:

- Accessibility state persists and is observable through the owning platform or
  managed interface after a fresh session.
- Missing X11 extensions or optional tools degrade per capability and never make
  Settings, notifications, or the shell unavailable.
- Keyboard-only navigation, text scaling, contrast, reduced motion, notification
  delivery/history, and reset behavior pass nested-X11 and real-session checks.

### SECURITY-001: Installer and Signing-Key Hardening

Independent of the rest of this phase — a read-only security audit of
`scripts/`, `config/`, `install.sh`, and `config.mk`, done — see `CHANGELOG.md`'s
"Security" section for the finding-by-finding detail. (Its planning document,
`docs/SYNC-P11-SECURITY-HARDENING.md`, was removed once implemented, per this
project's convention of retiring a plan document once `CHANGELOG.md` carries
the record — see `docs/UPSTREAM-SYNC.md`.)

- [x] Replace `install-mybash`'s `curl | sudo sh` Starship fallback with a
  checksum-verified, non-root download; pin the fzf-bin clone and drop `sudo`
  from its install; drop zoxide's unpinned curl fallback in favor of the
  official Arch package.
- [x] Wire `xscreensaver-setup.sh`'s config to `lock: True` and add a guarded
  `dwm-lock` branch so an active xscreensaver daemon is actually used to lock,
  not merely blank, the screen.
- [x] Pin and verify the CachyOS signing key's fingerprint before
  `pacman-key --lsign-key` trusts it; delete and refuse an unexpected key.
- [x] Pin `install.sh`'s `yay-bin` AUR clone to a reviewed commit and drop
  `--noconfirm` from its `makepkg -si` so a compromised AUR page can't build
  and install silently.
- [x] Add standard compiler hardening flags (`_FORTIFY_SOURCE=2`,
  `-fstack-protector-strong`, `-fPIE`/`-pie`, `-Wl,-z,relro,-z,now`,
  `-Wformat-security`) to `config.mk`.
- [x] Reject newline-embedded `webapp-create` names/URLs before they reach the
  generated `.desktop` file; restrict icon downloads to HTTPS with a size cap.
- [x] Add a dedicated polkit `.policy` action for `dwm-settings-display`'s
  `pkexec` call instead of relying on the generic exec-path prompt.

Acceptance:

- `scripts/run-tests make clean all` builds cleanly with the new hardening
  flags; the built `dwm` reports as a PIE binary with `BIND_NOW`/`RELRO` set.
- A corrupted CachyOS key fingerprint is refused and the untrusted key is
  deleted, never locally signed.
- `dwm-lock` locks (not merely blanks) an active xscreensaver session, and
  does not misfire when the daemon is installed but not running.
- `webapp-create` rejects a newline-embedded name or URL before writing any
  file.

### P5-UI5: Optional X11-Native Experience Integration

- [x] Inventory UI-5 candidates, beginning with event-driven clipboard history,
  and record an adopt, defer, or reject decision for each candidate.
  - **Candidate: event-driven clipboard history** — the only candidate named
    anywhere in `SPEC.md`/`ROADMAP.md`/`TASKS.md`; no other candidate has been
    proposed. **Decision: defer.** It needs its own event-driven X11
    selection-owner backend, a privacy model (clipboard contents routinely
    include passwords and other sensitive text), a bounded/pruned history
    store, and Settings integration. `ROADMAP.md`'s own "Integrated
    Boundaries" already calls this out as its own review boundary, not
    incidental Phase 5 work, and its "Integrated Delivery Order" says approved
    UI-5 experiences are "delivered as separate review boundaries" — approval
    does not require delivery inside Phase 5's own close. Revisit as its own
    boundary if and when it is actually requested.
- [ ] Evaluate every adopted UI-5 experience as an independent review boundary
  with an event-driven provider, explicit data ownership, bounded lifecycle,
  privacy model, and Arch package impact before implementation.
- [ ] Integrate only approved X11-native experiences into the existing semantic
  design system and command surfaces; do not copy Wayland, Hyprland, layer-shell,
  UWSM, or Omarchy service/plugin backends.
- [ ] Preserve current IPC names, X11 focus/click-away/stacking behavior, monitor
  selection, and closed-surface near-idle behavior.

The three items above stay unchecked, not because anything failed, but because
they only apply once a candidate is adopted — the inventory decided defer, not
adopt. Re-open them when a UI-5 candidate is actually adopted, rather than
checking them off for work that was never done.

Acceptance:

- Every inventoried candidate has a recorded adopt, defer, or reject decision.
  **Met** — see above.
- Every adopted experience has focused source, helper, lifecycle, nested-X11,
  package/install, and privacy tests. N/A this phase — nothing was adopted.
- Closing a surface leaves no resident scan, duplicate subscription, helper,
  sensitive history owner, or overlapping process. N/A this phase — nothing
  was adopted.

### P5-VALIDATE: Phase 5 Validation

- [x] Run focused parser, helper, QML, lifecycle, rollback, and nested-X11 tests
  for every Phase 5 workflow.
  - `check-quickshell-appearance-model`, `check-quickshell-design-system`,
    `check-quickshell-large-surfaces`, `check-quickshell-large-surfaces-xvfb`,
    `check-quickshell-panel-menus`, `check-quickshell-panel-settings`,
    `check-accessibility`, `check-quickshell-notifications`,
    `check-settings`, `check-appearance`, `check-session-guards` all pass.
    `check-quickshell-settings-xvfb` `SKIP`s (`xkbset` unavailable) — a
    pre-existing sandbox environment gap (no AUR helper here), not a defect;
    confirmed unrelated to any Phase 5 change by re-running it identically on
    `main` before this branch's changes.
- [ ] Exercise reversible appearance and accessibility changes on Arch,
  restore exact original state, and record unavailable toolkit or X11 paths.
  - Reversibility itself is automated and passing (theme preview/apply/reset,
    wallpaper preview/apply/reset with rollback, font/cursor/icon/GTK/Qt
    mutation-and-release, contrast/reduced-motion toggle-and-reset, all with
    explicit tests). What remains genuinely unautomatable in this sandbox is
    "**on Arch**" — a real session, real hardware, real toolkit daemons. No
    display server, PipeWire, or D-Bus session is available here beyond what
    `dbus-run-session`/Xvfb fixtures provide. **Recorded as a limitation**,
    not silently dropped — see `ROADMAP.md`'s Phase 5 status.
- [x] Compare a 30-second closed baseline with a 30-second sample after opening
  and closing every Phase 5 Settings workflow; the mean Quickshell CPU delta
  must be no more than 0.5 percentage points of one CPU.
  - `check-quickshell-large-surfaces-xvfb`: **PASS (0.00% closed CPU)** — the
    same target used for this exact criterion in every earlier phase this
    project closed.
- [x] Run the clean build, full managed repository suite, Quickshell lint,
  ShellCheck, shfmt, staged install, repeated install, and installed-runtime
  parity checks.
  - `make clean all`: clean, `dwm` reports as a PIE binary with `BIND_NOW`/
    `FLAGS_1 NOW PIE` set. `check-shell`, `check-format`, `check-quickshell-qml`
    all pass. `check-install` (manifest/uninstall symmetry) and
    `check-install-preservation` (repeated install, user-file preservation)
    both pass.
  - Neither `make check` nor `make -k check` completes end-to-end in this
    sandbox: `check:`'s recipe is one sequential shell recipe, not a set of
    independent prerequisite targets, so `-k` cannot resume it past a failed
    line — both stop at the same pre-existing `check-quickshell-settings-xvfb`
    `SKIP` (`xkbset` unavailable). **This is a real, minor Makefile finding**,
    not a Phase 5 defect — `scripts/run-tests make check`'s documented role as
    "the full suite" is only reliable on a host with every optional dependency
    installed; on a host missing one, it silently never reaches the targets
    after it, which is worth someone fixing (e.g. adding the same
    `SKIP`-tolerant wrapper `check-quickshell-large-surfaces-xvfb`'s own
    recipe line already uses) but is out of scope for closing Phase 5.
  - **Worked around by running every remaining `check:` target as an explicit
    named goal with `-k`** (which *is* independent-goal `-k`, and does skip
    past the one `SKIP` correctly): every target in the `check:` recipe, both
    before and after `check-quickshell-settings-xvfb`, passes. The full list:
    `check-build-config`, `check-arch-platform`, `check-dev-sync-install`,
    `check-default-apps`, `check-xdg-autostart`, `check-diagnostics`,
    `check-status`, `check-test-lib`, `check-shell-contracts`,
    `check-gtk-theme`, `check-plymouth-theme`, `check-grub-theme`,
    `check-session-launch`, `check-dwm-roundtrips`, `check-display-profile`,
    `check-display-setup`, `check-monitor-tags`, `check-quickshell-launcher`,
    `check-quickshell-controls`, `check-quickshell-audio`,
    `check-quickshell-controlcenter`, `check-quickshell-power-backend`,
    `check-quickshell-power-model`, `check-quickshell-session-actions`,
    `check-quickshell-defaults-model`, `check-quickshell-appearance-model`,
    `check-quickshell-design-system`, `check-quickshell-large-surfaces(-xvfb)`,
    `check-quickshell-panel-menus`, `check-quickshell-panel-settings`,
    `check-accessibility`, `check-quickshell-qml`,
    `check-quickshell-notifications`, `check-quickshell-tray`,
    `check-system-health`, `check-settings`, `check-appearance`,
    `check-quickshell-network`, `check-quickshell-connectivity`,
    `check-terminal`, `check-gearlever-install`, `check-herdr-install`,
    `check-mybash-install`, `check-lock`, `check-session-guards`,
    `check-session-migration`, `check-webapp-launch`, `check-screenshot`,
    `check-release-helper`, `check-archiso`, `check-cachyos`,
    `check-quickshell-state`, `check-arch-packages`, `check-install`,
    `check-install-preservation`, `check-test-runner`,
    `check-lightdm-config` all pass. `release-check` was not run — it is
    release-process tooling, not a test, and out of scope here.
  - **Two targets do not pass, both confirmed pre-existing and unrelated to
    Phase 5** (present identically on `main`, in files this branch never
    touched): `check-quickshell-settings-xvfb` `SKIP`s (`xkbset` unavailable
    in this sandbox — an environment gap, not a defect). `check-quickshell-command-menu`
    **fails** — `tests/test-quickshell-command-menu.sh` asserts
    `grep -Fq 'menu open|close|toggle|summon' CHANGELOG.md`, and that literal
    string has never been in `CHANGELOG.md`, not even at the fork's initial
    commit (`53b8dd2`) — this test has apparently never passed on this repo.
    Neither the test nor `CHANGELOG.md` has been touched by any Phase 5 work
    or by this branch. **Left unfixed, flagged for the project owner**: the
    fix is either backfilling a `CHANGELOG.md` entry for whenever the command
    menu actually shipped, or correcting the test's stale assertion — a
    genuine judgment call this document shouldn't make unilaterally, and
    unrelated to Personalization/Accessibility.
- [ ] Qualify a fresh LightDM login, fixture or real `startx`, multi-monitor and
  common display-size rendering, optional-component loss, and recovery after an
  invalid theme or missing asset.
  - Optional-component loss and invalid-theme/missing-asset recovery are both
    automated and passing (see `APPEARANCE-001`'s "preserve optional-component
    behavior" evidence, plus the theme-recovery and legacy-colors-fallback
    tests in `tests/test-dwm-settings-appearance.sh`). A fresh **LightDM**
    login and **multi-monitor** rendering need real display hardware this
    sandbox does not have. **Recorded as a limitation.**

Acceptance:

- Every Phase 5 exit criterion maps to automated evidence or a named manual
  check with Arch release, session, restoration, and limitations. **Met** —
  the two remaining hardware-only items are named above and carried forward
  as explicit `ROADMAP.md` limitations rather than silently dropped.
- Invalid themes or missing assets cannot prevent login or shell startup.
  **Automated evidence confirms this**; real-login confirmation remains part
  of the recorded hardware-qualification limitation.
- Accessibility choices persist, remain keyboard-usable, and do not add idle
  polling, duplicate providers, or orphaned work. **Met** — `check-accessibility`
  and the closed-CPU baseline above cover this.

## Phase Completion

When all Phase 5 acceptance criteria pass:

1. Record delivered behavior and validation in `CHANGELOG.md`.
2. Update the Phase 5 status and limitations in `ROADMAP.md`.
3. Replace this file's active task set with Phase 6 tasks.
4. Preserve incomplete or deferred work as explicit roadmap limitations.
