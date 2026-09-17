# Changelog

All notable project changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses calendar
versions (`YYYY.MM`, or `YYYY.MM.PATCH` for a second release in the same
month) from `config.mk`. A pre-release appends `-alpha.N`, `-beta.N` or
`-rc.N`.

## [Unreleased]

### Added

- Add bounded local, hardware, and filesystem information readers to
  `dwm-system-management` (Sync Sprint 2 S2-01,
  `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported from upstream
  `#277`/`#278`/`#279`): `read_local_information()` reads OS identity
  (`/etc/os-release`), CPU model (`/proc/cpuinfo`), memory/swap
  (`/proc/meminfo`), kernel release/architecture (`uname`), logical CPU
  count, and boot-time uptime, each field failing independently rather than
  blanking the whole read. `read_hardware_information()` reads vendor/model
  from `org.freedesktop.hostname1` over a fresh, bounded D-Bus connection.
  `read_filesystem_information()` runs a fixed, deadline-bounded
  `findmnt --json` and validates its output into per-mount rows (source,
  target, filesystem type, size/used/available bytes), rejecting duplicate
  or oversized JSON without losing valid peer rows. None of this is wired
  into the snapshot protocol or any UI yet -- that starts at S2-05.
  Lyona adaptation: upstream's OS-identity mapping only reads `VERSION_ID`,
  which renders "unknown" on Arch and CachyOS since both are rolling
  releases with no `VERSION_ID` at all; `parse_os_information()` now falls
  back to `BUILD_ID` (which Arch's `os-release` sets to `rolling`) only
  when `VERSION_ID` itself was not reported, verified against both a
  synthetic fixture and this repository's own CachyOS sandbox.
- Add a manual `Full suite (manual)` GitHub Actions workflow
  (`.github/workflows/full-suite.yml`, Sync Sprint 1 S1-01,
  `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`) that runs `scripts/run-tests
  make check` (or one named target) as an unprivileged user in an
  `archlinux:base-devel` container, uploads the log, and optionally builds
  dwm with clang. Push and pull-request CI is unchanged.
- Add confirmed delegated administration (Sync Sprint 1 S1-04,
  `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`, ported from upstream `#266`/`#267`):
  the Accounts/Password/Printers/Software-sources launch buttons in
  Settings → System now show a visible "Open *tool*?" confirmation card
  before launching, the same as regional (timezone/NTP/locale) changes
  already do, instead of dispatching on the first click.
  `SystemManagementModel.qml` gains `nativeConfirmation`/
  `prepareDelegate()`/`confirmDelegate()`/`discardDelegate()`/
  `delegateActionReason()`, replacing `launchDelegated()`, which dispatched
  immediately with no confirmation step. A live account or printer change
  retires an in-progress confirmation prepared against stale data. The new
  `config/quickshell/settings/SystemDelegateControls.qml` also lists the
  accounts and software sources the system currently reports, read-only.
  D-3 (`accounts-open`/`sources-open` permanently `unsupported` on Arch, no
  `lxqt-admin-user`/`dnfdragora` equivalent) is unchanged; their launch
  buttons stay disabled and now show the helper's own reason text.
- Give regional (timezone/locale/NTP) preview and confirmation its own model
  (Sync Sprint 1 S1-05, `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`, ported
  from upstream `#268`/`#269`): the new
  `config/quickshell/systemmanagement/SystemRegionalSettingsModel.qml`
  replaces the regional preview/confirm state that used to live directly on
  `SystemManagementModel.qml` (`regionalPreview`/`prepareRegional()`/
  `confirmRegional()`/`discardRegional()`), the same split S1-04 already
  gave delegated actions. `SystemRegionalControls.qml` is rewritten to
  match: timezone and locale changes now load a reported choices catalog
  first and require an exact selection from it, rather than accepting free
  text, before reviewing and confirming a change. A pending update,
  delegated, or regional confirmation now blocks starting any of the other
  two consistently in both directions -- closing gaps in the S1-04 mutual
  exclusion where an update confirmation in flight did not block starting a
  delegated one, and a live confirmation-invalidation signal did not clear
  a pending delegated confirmation.
- Share one timezone-aware minute clock between the panel and Settings
  (Sync Sprint 1 S1-06, `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`, ported
  from upstream `#270`): the new `config/quickshell/core/ClockModel.qml`
  replaces a bare `SystemClock` instance in the panel that never noticed a
  live `timezone-set` change -- Qt's `Date` does not re-read the system
  timezone on its own, so nothing previously called
  `Date.timeZoneUpdated()` after a confirmed timezone mutation. The
  System Settings page now also shows the current local date and time next
  to the timezone/locale controls.
- Add a bounded, event-driven read path for network time status to
  `dwm-system-management` (Sync Sprint 1 S1-07,
  `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`, ported from upstream
  `#271`/`#272`/`#273`): new `ntp-sample` and `time-status` CLI commands
  publish one finite record each, and a new `watch-time` command emits a
  `time-event\towner-arrived` record distinct from an actual `timedate1`
  property change, separating "the service came back, state is uncertain"
  from "state actually changed" for the first time. A local stop (SIGTERM/
  SIGINT/SIGHUP) during a regional change or its verifying read now
  terminalizes the in-flight journal operation as `interrupted` and returns
  promptly instead of leaving it ambiguous or blocking on the change's own
  timeout; a repeated stop coalesces rather than reordering cleanup, and an
  unrelated `SystemExit` (such as the locale catalog collector's own signal
  handling) is never reclassified as a stop. `finite_status_command()` also
  fixes a case the ported test suite caught during development: a closed,
  readonly, or Python-level-closed stdout previously reached the network
  read before failing on the write, wasting a live D-Bus round trip on
  output nobody could receive; it now fails immediately instead.
- Reconcile network-time-service owner arrivals and sample synchronization
  while System Settings is open (Sync Sprint 1 S1-08,
  `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`, ported from upstream
  `#274`/`#275`/`#276`): the "time" domain now watches with S1-07's
  `watch-time` instead of `watch-regional time`, so an authenticated
  `timedate1` owner arrival (uncertainty) is reconciled with a bounded
  `time-status` read through the new `SystemTimeReconciliationModel.qml`,
  instead of being treated as an unconditional invalidation the way every
  other watched property change is. A confirmed `ntp-set` change now also
  triggers an immediate `ntp-sample` read, and network time synchronization
  is sampled every 30 seconds while Settings is open rather than only at the
  last full snapshot; `SystemRegionalControls.qml` preserves and restores
  keyboard focus around either read the same way it already does around a
  regional confirmation. Found and fixed along the way: porting
  `tests/qml/SystemRegionalPreflightOwner.qml` (upstream's own bespoke
  integration harness for `SystemRegionalPreflightModel.qml`, closing a
  coverage gap Sync Phase 9 deferred) against a real Quickshell process
  surfaced a real crash -- `SystemRegionalPreflightProtocol.js`'s `consume()`
  threw a `TypeError` on the empty buffer a reused `StdioCollector` can
  deliver when its process restarts or fails to start, never previously
  exercised; a `0`-byte buffer is now a no-op instead.
- Show live per-package update progress and recover user-service session
  evidence (Sync Sprint 1 S1-09, `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`,
  ported from the system-management half of upstream `#291`): PackageKit's
  `Package`/`ItemProgress` signals now publish a bounded, ephemeral
  `package-progress` record (name, phase, percent) separate from the
  operation's own overall progress and log, and System Settings shows it as
  a labeled progress bar in place of the previous raw operation-log
  scrollback. A terminal operation's `error` record now always carries the
  operation's own detail rather than a caller-supplied override, so a failed
  acknowledgment's recovery instructions ("Reload status to retry") stay
  visible instead of being replaced by unrelated internal audit text. Restart
  evidence (`session_started()`) now also works when the helper is launched
  as a `systemd --user` service outside any login session scope: it falls
  back to logind's verified primary graphical display instead of failing
  outright on `NoSessionForPID`, re-verifying that display's identity hasn't
  changed before trusting its session timestamp. Ported and verified at the
  Python and QML-model/protocol layers (7 new/adapted Python tests, 1 new
  qmltestrunner test), plus upstream's own dedicated `SystemUpdateUi.qml`
  xvfb integration harness (a pre-`#291` file, predating this item by a
  long way -- see the sprint doc's S1-09 implementation notes) as
  `make check-quickshell-update-ui-xvfb`: porting it surfaced and fixed a
  real gap in its own fixture, not in production code -- with no active
  operation and a `partial` recovery reading, `journalAdmitted` (S1-03,
  from upstream's `#262`) had no evidence to trust the journal, since this
  update-only fixture never emitted the minor-1 native provider/state/
  action rows a real `dwm-system-management` always does; `operationModel`
  correctly, if unhelpfully, retried into `blocked`. Fixed in the fixture,
  not the model.
- Add a durable, crash-safe operation journal to `dwm-system-management`
  (Sync Phase 5, `docs/SYNC-P5-OPERATION-JOURNAL.md`): a double-buffered
  8,192-byte frame codec, an `openat`-relative directory chain hardened
  against symlink/group-writable tampering, operation/restart/handoff record
  codecs, admission control, and collision-safe operation IDs. Ships no
  user-visible behavior on its own — it is the crash-durable record Sync
  Phase 6 writes into and recovers from.
- Turn the journal into a working, confirmed execution owner (Sync Phase 6,
  `docs/SYNC-P6-UPDATE-EXECUTION.md`): `dwm-system-management` gains
  `updates-refresh`, `updates-install-all GENERATION`,
  `watch-operation OPERATION_ID`, `ack-operation OPERATION_ID`, and
  `updates-cancel OPERATION_ID` CLI commands that actually run PackageKit
  transactions, stream bounded progress, can be cancelled, and recover exact
  evidence (never a fabricated success) after a crash or shell restart mid
  update. `require_mutation_safe()`'s PackageKit-version gate now checks the
  daemon's own D-Bus version properties directly instead of Fedora's RPM
  database (Arch has neither). Still CLI-only; the Settings/Control Center
  button is Sync Phase 7. `config/quickshell/systemmanagement/SystemManagementModel.qml`
  gains `active-operation`/`terminal-handoff` snapshot parsing so a
  Quickshell restart mid-update can reattach via `watch-operation` instead of
  showing nothing.
- Put a button on the confirmed execution path (Sync Phase 7,
  `docs/SYNC-P7-OPERATION-SURFACE.md`): Settings -> System can now refresh
  PackageKit metadata and install Arch updates, not just read their status.
  `SystemOperationProtocol.js` (new) is a pure UTF-8-safe stream parser over
  `watch-operation`/`ack-operation` output; `SystemOperationModel.qml` (new)
  owns the process lifecycle over it, including reattaching to an operation
  the shell did not start after a Quickshell restart. Confirmation is a
  captured snapshot, not a flag: `SystemManagementModel.qml`'s
  `prepareUpdate()`/`confirmUpdate()` re-validate the plan's generation, this
  model's own read counter, and the live discovery cycle epoch all still
  match at confirm time, invalidating the prompt rather than dispatching a
  stale plan. `SystemUpdateControls.qml` (new) is the confirm/cancel UI,
  mounted in the System pane above the status grid, with live progress, a
  verified-result card, and cancellation gated on PackageKit reporting it
  safe. `build_snapshot()`/`build_managed_snapshot()` now thread a
  `mutation_blocker`/`mutation_failure` result so `updates-refresh`/
  `updates-install-all` actually report `available` once recovery evidence
  and `require_mutation_safe()` allow it -- ported from the same upstream
  commit as the rest of this phase, but missed in the original port (found
  and fixed while starting Sync Phase 8; without it every confirm/cancel
  control above was unconditionally disabled).
- Add five bounded, read-only backend readers to `dwm-system-management`
  (Sync Phase 8, `docs/SYNC-P8-REGIONAL-READERS.md`): system timezone/NTP
  (`RegionalRead`), locale (`RegionalRead`, `read_locale_choices()`), the
  local `AccountsService` account list (`AccountRead`, current-user-reserved,
  concurrency-bounded, overflow-safe), CUPS's running state (`CupsRead`,
  a systemd unit query, not a print-queue connection), and the PackageKit
  repository list (`RepositoryRead`, reusing the update snapshot's
  transaction handshake). Four `ServiceRead` subclasses back these five
  reads (`RegionalRead` is instantiated fresh per kind, for both the
  timezone/NTP and locale reads); each read is its own single-use instance
  with an independent deadline, so one source failing (e.g. `timedate1`
  unreachable) never blanks another. No mutation, no D-Bus write, and
  no caller yet -- these are backend building blocks with no snapshot
  protocol record, model property, or Settings row until Sync Phase 9 wires
  them into the snapshot alongside the timezone/NTP/locale/account/printer/
  source mutation and delegated-tool-launch actions.
- Wire Sync Phase 8's readers into a confirmed timezone/NTP/locale mutation
  path and delegated administration (Sync Phase 9,
  `docs/SYNC-P9-REGIONAL-MUTATION.md`): `dwm-system-management` gains
  `regional-choices`/`regional-preview` read-only preflight commands, a
  confirmed `timezone-set`/`ntp-set`/`locale-set` mutation path
  (`RegionalMutation`) that never fabricates a terminal state -- a sent
  change whose reply is lost is reported `interrupted`, never guessed
  success or failure -- and `accounts-open`/`password-open`/
  `printers-open`/`sources-open` delegated tool launching, each a fixed,
  root-owned, isolated `posix_spawn`. Since a regional/delegated operation
  has no PackageKit transaction to attach to, it gets its own crash-durable
  journal-owner lease (a dedicated `flock` on the active record, independent
  of the directory admission lock) and its own inotify-based watch.
  `watch-regional time|locale`, `watch-accounts`, and `watch-units printers`
  generalize Sync Phase 4's update monitor into a live-watch family covering
  four more domains. `accounts-open` and `sources-open` ship permanent
  `unsupported` on Arch -- neither `lxqt-admin-user` nor `dnfdragora` is
  packaged for it, and `system-config-printer` (`printers-open`) is the only
  one of the four with a real target; edit `/etc/pacman.conf` directly for
  repositories. `SystemRegionalPreflightProtocol.js`/
  `SystemRegionalPreflightModel.qml` (new) are the QML-side parser and
  process lifecycle for the read-only preflight commands, ported unchanged
  from upstream. This closes out Sync Phase 9 and, with it, the whole
  nine-phase system-management port -- Settings UI wiring for all of this
  (pickers, toggles, launch buttons) is left for later, same as it was for
  every reader Sync Phase 8 added.
- Add the Sync Phase 9 Settings UI (`sync-p9-settings-ui`, PR #33): a new
  `config/quickshell/settings/SystemRegionalControls.qml` (timezone/locale
  pickers, NTP toggle, delegated-launch buttons, a confirmation card) mounted
  in `SystemSettingsPane.qml`; `SystemOperationModel.startRegional()`/
  `startDelegated()` and `SystemManagementModel`'s `prepareRegional()`/
  `confirmRegional()`/`discardRegional()`/`launchDelegated()` family driving
  a private `SystemRegionalPreflightModel` instance; and `shell.qml` IPC
  probes for regional preview/confirm and delegated launch. This is the
  Settings UI half Sync Phase 9's own entry above left for later --
  timezone/locale/NTP changes and delegated administration (accounts,
  password, printers, sources) are now reachable from Settings, not only the
  CLI. `launchDelegated()` dispatches without its own confirmation step;
  Sync Sprint 1 (`docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`) converges this
  surface onto upstream's structure, which adds one.
- Add the update surface to Settings and Control Center (UPDATE-003,
  `docs/P6-UPDATE-SURFACE.md`): a new `config/quickshell/system/UpdateModel.qml`
  root model over `lyona-update`/`lyona-version`, and a Settings -> System pane
  showing the installed-version card (turning red and naming which of
  system/user/binary disagree when the install is damaged), current update
  status, a confirmed **Update now** action with phase-by-phase progress
  (downloading, verifying, building, installing, verifying, restarting), a
  stable/preview channel selector, and a backups list with per-backup
  rollback. Control Center gets a one-line installed-version row plus a
  conditional **Update available** row when behind — no apply action there by
  design, since a multi-minute privileged operation does not belong behind a
  one-click row. `lyona-update` gained `set-channel` (persists the channel
  selection through the same seed-never-overwrite `update.conf` convention)
  and a `$XDG_STATE_HOME/lyona/update.status` file, written at every phase of
  `apply`/`rollback`, that lets a fresh model instance report the outcome of
  an update that completed across its own Quickshell restart — without it,
  every successful update would look like a crash to the UI. `rollback` now
  also restarts Quickshell itself when a desktop session is present (falling
  back to a plain "log in now" message from a bare TTY, where it always
  worked), instead of leaving the running shell out of sync with what was
  just restored. New `docs/src/updating.md` walks through checking, applying,
  channels, and rollback, prominently including the bare-TTY recovery path;
  mirrored in `README.md`'s Troubleshooting section.

- Add install provenance (UPDATE-001, `docs/P6-UPDATE-PROVENANCE.md`):
  `make install-system` and `make install-user` now each write a stamped
  record last, only on success — `/etc/lyona-release` (system) and
  `$XDG_STATE_HOME/lyona/install.state` (user) — and the new `lyona-version`
  helper reads them back through the same safety idiom used elsewhere
  (`status`, `status --json`, `print`). A record that is missing reads as
  `defaults`; one that is symlinked, wrong-owner, oversized, or writable by
  group/other reads as `unavailable` and is never read through or rewritten.
  `consistent` is `yes` only when the system record, the user record, and the
  running `dwm -v` binary all agree, catching a half-applied install rather
  than reporting a version nobody can act on. An ISO install now carries its
  real build commit onto the target instead of recording `unknown`
  (`archiso/airootfs/root/lyona-postinstall.sh` passes `LYONA_SOURCE=iso`/
  `LYONA_COMMIT` through explicitly, since `su -` resets the environment),
  and `install.sh`'s completion banner reports the version that was actually
  stamped. Nothing else about the install path changed; this is the
  foundation the rest of Phase 6's update path (`lyona-update`) builds on.

- Add `lyona-update` (UPDATE-002, `docs/P6-UPDATE-HELPER.md`): a `check` /
  `apply` / `rollback` / `backups` helper that lets an installed machine move
  to a newer release and back again, on top of UPDATE-001's provenance
  record. `check` compares the installed version against a `stable` or
  `preview` GitHub release (calendar-version ordering, with a short-lived
  cache so a panel indicator does not hammer the API) and reports `current`,
  `behind`, `ahead`, `downgrade-offered`, `unknown`, or `offline` — never an
  error for an unreachable network. `apply` downloads and SHA-256-verifies a
  release tarball *before* unpacking it, builds unprivileged, backs up the
  live install, then runs one confirmed privileged step
  (`scripts/lyona-update-root`, installed via
  `config/polkit/com.lyona.update.policy`) before verifying the result and
  restamping provenance last — a build failure or a declined privileged step
  costs nothing but time, never a half-applied system. `rollback` is the
  missing half of `scripts/dev-sync-install.sh`'s existing backup machinery
  (now reusable as a library via a `DEV_SYNC_INSTALL_LIB_ONLY` sourcing
  guard that leaves its own direct-invocation behavior unchanged): it
  refuses on any checksum or environment mismatch, and is designed to work
  from a bare TTY with no desktop running by falling back from `pkexec` to
  `sudo` when no agent is reachable — not yet exercised from an actual bare
  TTY; that scenario is pending the disposable-VM verification pass in
  `docs/P6-UPDATE-HELPER.md`. Channel and backup retention are configured in
  `~/.config/lyona/update.conf`, seeded on first use and never overwritten.
  The privileged step re-verifies the release tarball's checksum immediately
  before use and then extracts, rebuilds, and installs from a scratch
  directory the invoking user never has write access to, rather than running
  a Makefile from a directory that was still writable by that user at the
  moment root acted on it; `rollback`'s restore likewise validates every
  backup archive member's path, type, and mode before extracting — refusing
  anything outside the managed install locations, any non-regular member
  (symlink, hardlink, device, FIFO, socket), and any setuid, setgid, or
  sticky bit — rather than trusting GNU tar's own default root-extraction
  behavior against a directory the invoking user could have replaced.

- Persist workspace, volume, Bluetooth, network, and power panel visibility in
  one versioned user-owned state file shared by every monitor, Control Center,
  and Settings. An absent file migrates from the prior implicit all-on state;
  malformed, incomplete, unsafe, or unsupported state falls back all-on
  without preventing shell startup. Atomic set/reset actions preserve the file
  mode and refuse concurrent or unsafe replacements.

- Theme the GRUB boot menu by default. The `CyberRe` theme (vendored from
  [ChrisTitusTech/bootloader-themes](https://github.com/ChrisTitusTech/bootloader-themes),
  MIT) installs to `/usr/share/grub/themes/CyberRe`, and the installer
  selects it on machines that boot with GRUB. New `lyona-grub-theme` helper
  with `status`, `list`, `apply`, and `remove`.

  Installing the theme files changes nothing about booting. Selecting the
  theme edits `/etc/default/grub`, so it backs the file up first, prints
  every key it rewrites (`GRUB_THEME`, a `GRUB_TERMINAL_OUTPUT` that would
  disable the graphical terminal, and `GRUB_GFXMODE` when unset), comments
  replaced lines out instead of deleting them, and regenerates
  `/boot/grub/grub.cfg`. Which entry boots, the kernel command line, and the
  timeout are untouched.

  Machines that do not boot with GRUB -- including installs from the lyona
  image, which use systemd-boot -- are reported and left alone, and a failed
  theme step does not fail the install. Opt out with `--skip-grub-theme` or
  `DWM_INSTALL_GRUB_THEME=false`; revert an applied theme with
  `lyona-grub-theme remove`.

- Add text scaling, contrast, reduced motion, notification policy, and
  keyboard/pointer accessibility capability records to `dwm-settings-provider
  discover`, so Settings can report accessibility maturity per capability
  instead of a single all-or-nothing accessibility state. Text scale is
  probed live against `dwm-settings-font`; contrast and reduced motion report
  static `partial`/`unsupported` states describing the semantic-theme
  subsystem's current maturity; notification policy probes the D-Bus
  notification owner; keyboard/pointer access reflects XInput discovery
  readiness. Every emitted record is bounded and validated the same way as
  the rest of `dwm-settings-provider`'s helper output.

- Add a persistent high-contrast and reduced-motion policy, applied across
  every managed Quickshell surface. New `dwm-accessibility-settings` helper
  (`status`/`watch`/`set`/`reset`) stores the policy at
  `~/.config/lyona/accessibility.conf`, with the same atomic-publish,
  concurrent-edit-refusal, and symlink/hard-link-refusal safety as the
  existing settings helpers. High contrast widens control borders and pins
  muted text to full-strength text; reduced motion collapses animation
  durations to zero. Both compose over the active theme rather than
  replacing it, so hot-reloading a theme while an override is active still
  repaints the palette and the override survives -- `Theme.qml`'s
  `textMuted` is now a read-only value derived from a separate
  `paletteTextMuted` palette slot for exactly this reason. A missing or
  unreadable policy file falls back to standard contrast and full motion
  without preventing shell startup.

- Add keyboard- and screen-reader-accessible controls for the new high
  contrast and reduced motion policy: a Settings → Appearance "Accessibility"
  section with two toggles, a status card explaining why a control is
  disabled when the provider is read-only, and a reset action. `Settings`
  and the Bluetooth power toggle in the Control Center gained proper
  `Accessible.*` metadata and a shared `requestToggle()`/`requestActivation()`
  guard, so a screen reader's press action can no longer bypass the same
  enabled/busy check the keyboard and mouse paths already enforce.
  `dwm-settings-provider`'s `accessibility-contrast` and
  `accessibility-reduced-motion` capability records now reflect whether the
  policy can actually be changed right now (backed by a real atomic-exchange
  readiness probe against the configuration filesystem) instead of the
  static placeholders Phase 4 shipped.

- Add XKB accessibility controls -- sticky keys, slow keys, bounce keys, and
  mouse keys -- to Settings → Input, backed by `xkbset` through the existing
  `dwm-settings-input` provider. The new "Keyboard accessibility" group uses
  the same bounded preview-then-keep-or-revert flow, and reset, as every
  other input setting. Reflects live in `dwm-settings-provider`'s
  `accessibility-input` capability record, which now distinguishes "xkbset
  is missing," "xkbset is installed but unresponsive," and "fully available"
  instead of a single static state. `xkbset` has no official Arch package
  and is AUR-only; it is listed as an optional dependency that installs
  automatically only when already resolvable, and every code path degrades
  cleanly to an explicit unsupported state when it is absent.

- Add a managed notification policy: Do Not Disturb and a configurable popup
  duration (4/6/10 seconds), in a new Settings → Appearance → Notifications
  section. The existing D-Bus notification owner is never touched -- the
  policy gates which popups *display*, not which notifications are
  *received*, so history keeps recording everything even while Do Not
  Disturb is on. Critical-urgency notifications always show regardless of
  the policy. The policy fails closed: an unreadable or malformed policy
  file suppresses all non-critical popups rather than defaulting to
  "show everything." `dwm-settings-provider`'s `accessibility-notifications`
  capability now inspects the real D-Bus owner process (via
  `/proc/<pid>/exe` and its Quickshell config selectors) to confirm it is
  actually the managed Lyona shell before reporting `available`, rather
  than just checking that some owner exists.

- Replace the Displays pane's single mode-cycling button with dependent
  resolution and refresh-rate dropdowns, and replace immediate mode changes
  with an explicit **Apply changes** step: a 15-second countdown, **Keep
  changes** to confirm, or **Revert**/timeout/closing Settings to restore the
  captured layout automatically. `ShellButton` gains a `primary` visual state
  for the Apply/Keep/Use-at-next-login actions. Saved layouts are relabeled
  from implementation-oriented wording ("Profile", "Install persistent",
  "Rollback system") to "Layout name", "Use at next login", and "Restore
  login backup". `AppearanceModel`'s theme-mutation readiness probe now
  queues and re-checks itself instead of racing a concurrent action or
  refresh, so a refresh that lands while a readiness check or mutation is
  already running no longer reports a stale `mutationReady` value.

### Security

- `install-mybash`'s Starship fallback no longer pipes a remote script
  straight into `sudo sh` on a transient `pacman` failure: it now downloads
  `https://starship.rs/install.sh` to a temp file, verifies it against a
  pinned SHA-256, and runs it as the invoking user (the installer itself only
  escalates internally if `/usr/local/bin` is not already writable). The fzf
  fallback now clones a pinned release tag and installs with `--bin`, which
  never needs `sudo`, instead of an unpinned clone plus `sudo ~/.fzf/install`.
  The zoxide curl fallback is dropped entirely in favor of the official Arch
  package, since Lyona targets Arch only.
- `xscreensaver-setup.sh` now writes `lock: True` instead of `lock: False`,
  and `dwm-lock` gained a guarded fallback branch (only taken when the
  daemon is actually running) so a screen that blanks via xscreensaver is
  also actually locked, instead of dismissible with any keypress.
- `lyona-cachyos` now verifies the CachyOS signing key's fingerprint against
  a pinned value before `pacman-key --lsign-key` trusts it, and deletes any
  key that doesn't match rather than signing it. Previously it trusted
  whatever a keyserver returned for the key ID with no independent check.
- `install.sh`'s `yay-bin` AUR bootstrap now clones a specific reviewed
  commit instead of an unpinned moving ref, and no longer passes
  `--noconfirm` to `makepkg -si`, restoring the normal PKGBUILD review pause.
- `config.mk` now builds `dwm` with `-D_FORTIFY_SOURCE=2`,
  `-fstack-protector-strong`, `-fPIE`/`-pie`, `-Wl,-z,relro,-z,now`, and
  `-Wformat -Wformat-security`. Fixed one real issue `-Wformat-security`
  surfaced: `getparentprocess()` never checked `fscanf`'s return value.
- `webapp-create` rejects a name or URL containing a newline before writing
  the generated `.desktop` file, closing a `.desktop`-key-injection path, and
  restricts icon downloads to HTTPS with a 10 MiB cap.
- Added a dedicated polkit `.policy` action
  (`config/polkit/com.lyona.settings-display.policy`) for
  `dwm-settings-display`'s `pkexec` call, replacing the generic
  `org.freedesktop.policykit.exec` prompt with a scoped message and icon.

### Changed

- Reduce hosted CI to one Arch build and desktop smoke job
  (`tests/test-desktop-smoke-xvfb.sh`, `check-desktop-smoke-xvfb`): build
  dwm, then start the real managed Quickshell shell in a private Xvfb+dbus
  session and check its panel, the launcher's Super+R/Escape keys, and an
  application launch. Skip documentation-only pushes. The full Xvfb/Settings
  suite (`scripts/run-tests` / `make check`) stays a local check rather than
  a hosted CI job; local validation and independent review remain the merge
  gate. The previous full desktop suite, `clang-build`, and `quickshell-qml`
  hosted jobs are removed; `workflow_dispatch` now runs the same smoke job.
- Increase the Settings window to 1180x760 and tighten its navigation rows,
  pane margins, capability cards, and display controls so more options remain
  visible without reducing the configured text scale. Clamp the enlarged
  window to the active screen on smaller outputs.

### Fixed

- Fix `scripts/webapp-launch`, which never worked for a user-scoped browser
  install: unquoted brace expansion ran before tilde expansion, so
  `~/.local/share/applications` and `~/.nix-profile/share/applications` were
  never actually searched, only `/usr/share/applications`. The browser
  resolution was also unquoted (word-split a path containing a space) and
  parsed `Exec=` with a `sed` pattern that mishandled quoted or
  backslash-escaped values. Rewritten with proper quoting, spec-correct
  `Exec=` parsing, and URL validation. A bare `Super+A` ChatGPT launch now
  prefers an installed desktop app and falls back to the web app only when
  asked to, without risking recursion back through the launcher.
- Fix `dwm-settings-input`'s device scan silently reporting zero devices when
  `xinput --list --short` failed outright, instead of surfacing the failure.
  It now checks the command's exit status before parsing its output and
  exits with `die` on failure.
- Fix a race in `dwm-settings-appearance`'s inventory scanner: a named
  coprocess's PID and file-descriptor bookkeeping could be unset by bash
  before the caller read them, if the scan finished first. Replaced with
  process substitution, which captures its PID synchronously and keeps it
  valid regardless of whether the process has since exited. The scan also no
  longer inherits the parent shell's stdin.
- Document the command menu's `menu open|close|toggle|summon` IPC surface,
  which shipped undocumented since the fork (`tests/test-quickshell-command-menu.sh`
  asserted the documentation but nothing had ever satisfied it, so
  `make check` failed on a from-scratch checkout).

## [2026.08.0-beta.1] - 2026-08-28

First beta of the Arch Linux line. See
`docs/RELEASE-NOTES-2026.08.0-beta.1.md` for artifacts and qualification
status.

### Changed

- Port the entire distribution target from Fedora to Arch Linux: the
  installer, dependency map, and diagnostics now use `pacman` and Arch
  package names; the Fedora Kickstart/RPM Fusion/COPR image path is replaced
  by a best-effort `archiso`-based install medium
  (`scripts/build-lyona-arch-iso.sh`); an AUR helper (`yay`) is installed
  as a standing convenience tool. Project branding moves to
  `technicks89`/`technicks89.com`. Arch Linux is now the sole supported
  platform.

- Rename the project from `dwm-titus` to `lyona`, to avoid confusion with
  the original Fedora-based `dwm-titus` project this was forked from.
  Renames the compiled-in XDG config/data subdirectory
  (`~/.config/lyona`, `~/.local/share/lyona`), install paths, the archiso
  install medium and its `lyona-install`/`lyona-postinstall.sh` scripts,
  and all documentation. The `dwm` window manager itself and its
  `dwm-*` tool family (`dwm-status`, `dwm-settings-*`, etc.) are unaffected
  -- only the project's own branding changes. No migration path is provided
  from an existing `dwm-titus`-named install; reinstall onto the new paths
  instead.

- Enable the `multilib` repository on the ISO. The archiso `pacman.conf` ships
  it uncommented and the generated archinstall configuration requests it, so
  the installed system has 32-bit packages available without a manual
  `pacman.conf` edit. `install.sh` now treats an already-enabled `multilib` as
  approval, so the ISO's full profile installs the Arch gaming packages it
  advertises instead of skipping them.

- Switch the shipped default theme from Nord to Tokyo Night and drop the
  stale `include ./nord.conf` line from `kitty.conf`, which overrode the
  generated `active-theme.conf` and pinned kitty to the Nord palette
  regardless of the selected theme.

- Apply a display-scale change to the running session instead of only to
  applications started afterwards. `dwm-settings-display dpi-set` still persists
  `Xft.dpi` and merges it into the running resource database, and now also
  publishes the value over XSETTINGS, sets the X server's reported DPI, and
  writes a runtime record the managed shell watches. dwm rescales its border
  width and snap distance when the resource database changes, and the Quickshell
  panel, popups, Control Center, launcher, and Settings window scale their
  metrics from the active DPI. A 96 DPI session renders exactly as before.
  Rescaling applications that are *already open* needs `xsettingsd`, which joins
  the X11 dependency set along with `xorg-xrdb` -- a hard requirement of the DPI
  actions that was missing from the dependency map and failed silently. Without
  `xsettingsd` a scale change still reaches the desktop immediately and reaches
  each application as it restarts. The scale is set from Displays in Settings.

### Fixed

- Keep floating windows above the tiling layout. Restacking placed every visible
  tiled client directly beneath the bar, which is the top of the window stack, so
  any floating window that was not the selected one was buried the moment focus
  moved to a tiled client. Windows that a rule, a transient hint, or a fixed size
  makes floating now stay above the tiled clients, and below the always-on-top,
  panel, override, and fullscreen layers as before. Tiled clients also restack
  correctly on a monitor that has not adopted a panel, where the previous sibling
  chain resolved to no window and the request was discarded without a diagnostic.

- Float windows matching the `RAIL` window rule. The rule set an unrecognised
  `float` key rather than `isfloating`, so it was parsed and then ignored.

- Prefer an installed ChatGPT desktop application for Super+A and hide its duplicate ChatGPT web entry from the managed application launcher, while retaining the web app as the fallback when no native desktop entry exists.

[Unreleased]: https://github.com/technicks89/Lyona/compare/v2026.08.0-beta.1...HEAD
[2026.08.0-beta.1]: https://github.com/technicks89/Lyona/releases/tag/v2026.08.0-beta.1
