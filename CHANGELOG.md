# Changelog

All notable project changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses calendar
versions (`YYYY.MM`, or `YYYY.MM.PATCH` for a second release in the same
month) from `config.mk`. A pre-release appends `-alpha.N`, `-beta.N` or
`-rc.N`.

## [Unreleased]

### Changed

- Floating a tiled window now visibly changes it (Sync Sprint 5 S5-03, decision
  D-9, ported from upstream `#331` `2e77c11` and `#333` `841d3cd`).
  `togglefloating` used to float a window at its current tile size, so
  `Super+Space` seemed to do nothing. An explicit toggle (a key or button
  binding) now pops a tiled window out at 85 percent of its tile, centered and
  clamped to the monitor's work area through a new `shrinkfloating()`, as far as
  the window's size hints allow: a minimum size larger than the work area wins,
  and the window then starts at the work area's top-left corner and extends past
  it. Toggling back retiles it. Switching a
  monitor to the floating layout, from tiling or monocle, shrinks each visible
  tiled window the same way, once: choosing the floating layout again does not
  shrink them again, and `Super+T` retiles. Windows already floated
  individually, fixed-size windows, and fullscreen windows (other than fake
  fullscreen) are left alone, and mouse drags, which call `togglefloating` with
  no argument, keep their geometry. `tests/test-xvfb-runtime.sh` covers the
  toggle cycles, both layout transitions, individually floated and fixed-size
  windows and windows whose minimum size exceeds the work area; it gained a
  `Super+L` floating-layout key in its own hotkeys and `border`, `min-size` and
  `fixed` modes in its X client.

- Settings panes stay hidden until their data has loaded (Sync Sprint 5
  S5-01, `docs/SYNC-SPRINT-5-SETTINGS-LOADING-FLATHUB-FLOATING.md`, ported from
  upstream `#335` `709bcd0` and `4b0d438`; completes Lyona's `#315` work from
  Sprint 3). A pane used to fade in as soon as its component loaded, so cards
  still appeared and reflowed inside a visible pane while its first reads
  finished. `DeferredSettingsPane.qml` (now upstream's file) takes a
  `dataLoading` input from `SettingsWindow.qml` and keeps the pane invisible
  and disabled, behind a fixed "Loading settings..." message, until its
  component is ready and `dataLoading` is false; it then presents once, and
  later refreshes never hide controls again. Every model behind a pane reports
  its finite initial reads as a read-only `initialLoading` (never a resident
  watch subscription), and `SettingsModel` adds `displayActionBusy` and
  `inputActionBusy` so a preview-recovery read holds the Display and Input
  panes. Each queued-refresh flag (`snapshotPending`, `refreshPending`,
  `capabilityRefreshPending`, and the display, input, appearance, font,
  toolkit and Picom ones) now clears only after the process it queued has
  started, and no longer inside `onRunningChanged`, so there is no frame in
  which a refresh is about to run but nothing reports it. Lyona adaptations:
  the Appearance pane also waits on the toolkit provider and Picom (Lyona has
  no personalization provider), and upstream's `desktopUpdateModel` term is
  dropped because that git-`main` updater is declined (D-8). (Lyona's own update
  card is gated separately: see the System pane fix below.) The responsiveness harness now delays the
  display and input preview-recovery reads, the accessibility, panel and
  System-management reads and the notification policy, and asserts each pane
  stays hidden with an unchanged viewport until its data arrives, that no pane
  presents while one of its models is still loading, and that a queued flag is
  never cleared while nothing is running; the new
  `make check-quickshell-settings-loading` pins the wiring in the source.

- Stop depending on AUR-based packages, and audit the repository for any
  (`docs/AUR-PACKAGES.md`). The one package Lyona needed from the AUR,
  `xkbset` (sticky, slow, bounce and mouse keys and the AccessX shortcuts in
  Settings), is replaced by the in-tree `scripts/dwm-xkbset`: a Python helper
  over libX11's XKB calls, using `ctypes` like `dwm-cursor-reload`, so it adds
  no package. It speaks the subset of `xkbset` that Settings used, so
  `dwm-settings-input` and `dwm-settings-provider` only changed the command
  name and their messages; a checkout that has not been installed finds it
  beside the script. `xkbset` is dropped from the `desktop-optional` profile
  and from `check-deps.sh`. The AUR helper (`yay`) that `install.sh`
  bootstraps stays, by decision; no package Lyona installs uses it. All 113
  packages in the profiles and the live ISO resolve in `core`, `extra` or
  `multilib`. Two new checks: `make check-xkbset` runs the helper against a
  real X server and compares its masks with the system `XKB.h`, and
  `make check-no-aur` fails if an AUR helper installs a package, if anything
  but `install.sh` reaches the AUR, or if a profile names a package outside
  the official repositories. As a side effect the Settings xvfb suite no
  longer skips on hosts without `xkbset`.

- Qualify that missing optional components stay capability-scoped, and coalesce
  capability refreshes (Sync Sprint 3 S3-09, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  ported from upstream `#188`/`c8f574b` and `#191`/`4d776bc`, pre-survey gaps).
  A new `make check-phase5-optional-components` target and a combined
  optional-loss scenario in the Settings xvfb suite remove the wallpaper
  folder, Feh, cursor/icon/GTK assets, the Qt backend and Picom at once and
  check that only those capabilities degrade while the font and toolkit
  providers, terminal integrations, inventory watch and theme controls keep
  reporting what they did when healthy, then that everything recovers. The
  Appearance model now exposes wallpaper mutation and reset state and detail,
  and `shell.qml` gains read-only probes for them. Capability discovery
  requested while a provider run is in flight is queued as one follow-up
  run, and `capabilityById()` reports "Capability discovery is still
  refreshing" instead of a stale answer; the accessibility text-scale
  grouping from `#191` stays diverged by decision. The wallpaper preview
  watchdog now allows up to about one second (100 tries at 10 ms, was 20) to
  confirm its process identity, so a loaded machine no longer fails a preview
  that had started correctly.
  Lyona adaptations: upstream's personalization test is not ported because
  Lyona's toolkit has no delegate records; instead
  `tests/test-dwm-settings-toolkit.sh` checks that a missing `qt5ct`/`qt6ct`
  stays scoped to Qt, run against a PATH without them so it holds whether or
  not the host has them installed. The scenario probes `toolkit*` and the
  managed-font provider where upstream probed personalization, and the
  fixture now installs `dwm-settings-toolkit`, which it previously omitted.
  Fixture names follow Lyona's (`Lyona-nord`, not `Nordic`).

- Stop automatic theme-preview status retries once their bounded failure
  budget is exhausted (Sync Sprint 3 S3-09, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  ported from upstream `#183`/`e91d018`, a pre-survey gap): after more than
  three zero-remaining or unparseable `preview-status` reads Appearance stops
  polling and reports that rollback status needs a manual refresh. Opening
  Appearance or pressing Refresh still performs one explicit retry, and every
  definitive result (none, expired, failed, a positive remaining time, or a
  finished keep/revert/abandon) re-arms automatic observation. Applied
  unchanged.

- Keep the panel sharp under popups, and make shell surfaces usable at large
  text (Sync Sprint 3 S3-07 and S3-08, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  ported from upstream `#324`/`c44dae4` and the surface fixes of `#327`/`a5b829d`).
  Popups now start below the panel so a compositor can no longer blur the bar
  through the transparent click-away surface, and a popup taller or wider than
  the screen scrolls inside a clamped viewport instead of running off-screen.
  The Wi-Fi password dialog grows with its content, wraps its hint text, and
  scrolls when it would exceed the screen. Notification stacks, System Health,
  the Controls and Bluetooth windows and the panel icon glyphs size from the
  text scale; launcher, Wi-Fi and Bluetooth rows grow with their text instead
  of clipping it, the notification stack is clamped to the panel width and
  scrolls in its own viewport, and Health summary tiles wrap. Font sizes go through the new `Theme.scaledFontSize()` and the
  shell text scale accepts 0.75–2.0 (was 0.8–1.5). Status and rollback
  readiness for the wallpaper now list files by name and metadata only and
  never start an image decoder; the decode check moves to apply/preview.
  Lyona adaptations (decision D-7, amended 2026-09-20): geometry stays on
  `Theme.dp()` — upstream's `scaledSize()` is not ported, and the fixed
  pixel sizes it touched are wrapped in `dp()` instead. Upstream's
  desktop-typography port (`desktopFont*`, `applySharedTypography()`) is not
  taken because it needs a desktop font and text-size provider Lyona doesn't
  have; the managed shell font and its controls stay as they are. Upstream
  `68a0d1f` is not taken either: Lyona's default-wallpaper selection already
  decodes only a sample. `devicePixelRatio` was confirmed to be 1.0 at 144 DPI
  under Lyona's `QT_ENABLE_HIGHDPI_SCALING=0` launch, so no native-scale
  compensation is needed.
  `tests/qml/SettingsResponsiveness.inc` now renders these surfaces at 200
  percent text and checks that text stays inside its row, popups and the
  Wi-Fi prompt stay on screen and scroll, and the last notification's dismiss
  control is reachable.

- Compact the Control Center and Settings detail pane (Sync Sprint 3 S3-04,
  `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`, ported from upstream
  `c3e9a18` "refactor(quickshell): compact control surfaces", open since the
  first survey): remove the Control Center overview's redundant "Launch"/
  "Desktop"/"Utilities" section headers and the Power page's duplicate
  status text lines (their information now lives in each row's own
  `detail`, which shows the remaining duration instead of a bare On/Off),
  tighten row heights via a new `compactRowHeight` token, margins, and
  spacing throughout, and shrink the Settings detail pane's header and
  capability cards to match.
  Lyona adaptations: `Theme.compactSpacing` already existed, so no new
  token was needed; every new pixel constant (`compactRowHeight`, the
  `PresetButton` height) is wrapped in `Theme.dp()`, matching this sprint's
  established convention; duration formatting uses Lyona's own
  `Theme.formatDuration()` (not upstream's local `root.formatDuration()`,
  which Lyona hoisted into `Theme.qml` earlier); the Auto Lock row keeps
  Lyona's own "Unknown" state for an unavailable lock backend alongside
  upstream's new duration-when-enabled behavior. Two `xdotool` click
  coordinates in `tests/test-quickshell-health-xvfb.sh` needed updating for
  the now-shorter rows; rather than porting upstream's own new coordinates
  (tuned to its own layout), the correct values for Lyona's real rendering
  were read directly off a live xvfb run instrumented with a temporary
  `mapToGlobal()` probe, then verified end to end against the genuine
  compacted UI.

### Added

- `scripts/ci-local.sh` runs the "Full suite (manual)" workflow's job in a local
  Docker container (see `CONTRIBUTING.md`): the same base image, package set
  and unprivileged runner, on a copy of the working tree, so a CI-only failure
  can be found and fixed without a push. `--each` runs every target of the
  `check` recipe separately and lists all failures in one pass, where `make
  check` stops at the first. Running it found and reproduced the failure below.

- Desktop update experience (Sync Sprint 4 S4-06,
  `docs/SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`, decision D-8: upstream's
  mechanism for `#318`-`#323` is declined because `lyona-update`'s signed
  release tarballs already cover it, and only its user-facing ideas are ported).
  Progress is now visible outside Settings and survives the Quickshell restart
  an apply causes: a **progress popup** under the panel shows the current step
  with a **View log** button, and a **panel indicator** next to the battery
  brings the popup back after **Hide**. When the shell restarts mid-update both
  reappear by themselves, still in progress or showing how it ended. Only news is
  shown: a finished update does not reappear at a login ten minutes later, and a
  status left "in progress" by a crash more than an hour ago does not spin
  forever. A successful update dismisses itself after 20 seconds; a failed one
  stays until dismissed. `lyona-update` now sends a desktop **notification**
  when an apply or rollback ends (critical, and naming the log, for a failure),
  from the same place it writes the terminal status, and only after Quickshell
  has been restarted so the notification reaches the new shell rather than the
  one being replaced. Declining the confirmation prompt is not announced as a
  failure. **Update log:** the plan assumed `lyona-update` already wrote a log;
  it did not (the model only held the output in memory, which the restart
  destroys), so each apply or rollback now writes `update.log` with its full
  output, readable only by its owner and replaced on the next run, while a dry
  run keeps the previous log. The model reads at most the last 64 KiB, cut at a
  line boundary, and **Settings > System** has a matching **View update log**.
  Nothing new was needed for "one authorization per update": apply asks once
  (its two privileged call sites are release versus checkout mode) and rollback
  once, and a step that ran and failed is not retried through a second prompt;
  that is now pinned by a test. Issue `#311`'s acceptance was re-verified against
  `tests/test-lyona-update.sh`: up to date reports `current`, outdated reports
  `behind` and offers it, an unreachable network reports `offline`, and
  deferring leaves the install record, backups and `update.conf` unchanged,
  which had no test until now.
  Lyona adaptations: the popup is centered under the panel like the notification
  stack (so it needs no new dwm window rule) instead of a window of its own, the
  new tests never run a real `notify-send`, and the mechanism-side upstream
  commits are recorded as covered in `docs/UPSTREAM-SYNC.md`.
  Verified by `tests/test-lyona-update.sh` (log, notifications, defer,
  authorization count) and the new `tests/test-quickshell-update-progress-xvfb.sh`,
  which runs an isolated copy of the shell against real status and log files and
  was mutation-checked four ways.


- Icon themes and first-login theme convergence (Sync Sprint 4 S4-03,
  `docs/SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`, ported from upstream
  `#301`/`69240ea`; `#328`/`d4c6d89` recorded as not needed): the `theme`
  package profile now includes `adwaita-icon-theme` and `papirus-icon-theme`
  next to `dconf` (all in official `extra`, and on the live ISO, which now
  also carries `dconf` for first-login theming), so GTK applications have
  icons on a fresh install. `make install-user` now runs `scripts/theme-apply.sh`
  before recording the install, so first login already has the selected theme
  applied instead of waiting for a manual theme change. A failure there is a
  warning rather than an aborted install. The ISO package list is now the union
  of the `required`, `desktop`, `theme`, `media` and `iso` profiles.
  Upstream `#328` fixed `xsettingsd` inheriting an installer's lock descriptors
  through `dwm-xsettings`. Lyona has no `dwm-xsettings`, `theme-apply.sh` never
  starts `xsettingsd` (it edits its configuration and sends `SIGHUP`;
  `autostart.sh` starts it at login and already closes the descriptors it
  owns), and no install path holds a lock, so the plan's Python launcher wrapper
  was not ported. That was checked, not assumed: the real script was run under
  a held lock with real `gsettings` and `xfconf-query` on a private D-Bus
  session, the lock was free afterwards and no process held it. The new
  `tests/test-theme-apply-install-lock.sh` (in `check-appearance`) pins this and
  fails if `theme-apply.sh` ever launches the daemon with an inherited lock.

- Media and image defaults on fresh installs (Sync Sprint 4 S4-02,
  `docs/SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`, ported from upstream issue
  `#308` and the fixes `#317` and the MIME hunk of `c679937`): the recommended and
  full install profiles now install Celluloid, mpv, and sxiv (all in official
  `extra`, and on the live ISO too), and a new `scripts/seed-default-apps.sh`
  makes Celluloid the handler for audio and video, sxiv the handler for images,
  and, when Thunar is installed, Thunar the handler for folders on a fresh
  account. It runs before Gear
  Lever, which writes its own AppImage MIME preference file, and does nothing
  when a `mimeapps.list`, a desktop-specific `*-mimeapps.list`, or a legacy
  `defaults.list` already exists. Every handler is validated before anything is
  written, the file is published atomically, and a preference written while the
  script runs is kept rather than replaced. Settings > Defaults now lists menu-hidden
  handlers such as sxiv (its desktop entry sets `NoDisplay=true`), which used to
  be excluded, while still excluding disabled entries and missing executables and
  keeping menu-visibility filtering for the browser, file-manager and terminal
  roles. GIF, BMP and TIFF join the supported image types.
  Lyona adaptations: upstream's browser seeding is dropped (Lyona does not ship
  Brave), the seed runs inside the recommended branch of `install.sh` just before
  Gear Lever instead of moving the Gear Lever block, and the ISO package list is
  now the union of the `required`, `desktop`, `media` and `iso` profiles. `python`
  and the four new packages were checked against the official repositories with
  `make check-no-aur`. The `.desktop` IDs were confirmed from the shipped Arch
  packages (`sxiv.desktop` sets `NoDisplay=true`; Celluloid is
  `io.github.celluloid_player.Celluloid.desktop`). Not yet verified: the
  acceptance in the sprint doc that a fresh ISO install (standard and NVIDIA) and an
  existing-system `install.sh` both open `.mkv` in Celluloid and `.png` in sxiv
  from Thunar, and still do after logout and reboot, which needs real installs.

- The application launcher hides desktop entries scoped to other desktops (#104,
  ported in part from upstream PR #340). `scripts/dwm-quickshell-launcher` now
  reads `OnlyShowIn` and `NotShowIn` and compares them with the tokens of
  `XDG_CURRENT_DESKTOP` (a Lyona session exports `X-DWM` and `dwm`; unset means
  the same), so other environments' preference panels, such as the XFCE panel
  settings that Thunar pulls in, no longer appear. Any one matching token is
  enough, the comparison is case sensitive, an empty `OnlyShowIn` shows the
  entry nowhere, and GLib-compatible ordered token handling checks
  `OnlyShowIn` before `NotShowIn` for each token (falling back to the existing
  behavior when no token matches). A key inside an action group never scopes
  the whole entry. Opening a panel popup now also closes the launcher, the
  notification history and the Control Center utility window instead of
  leaving them open behind it. The rest of upstream's PR (screen-sized
  click-away windows, square corners, 1 px focus borders) was declined and
  Lyona keeps its behaviour. New cases in `tests/test-quickshell-launcher.sh`
  and `tests/test-quickshell-command-menu.sh`.

- Configuration-backed Picom controls (Sync Sprint 4 S4-01,
  `docs/SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`, ported from upstream
  `#312`/`#313`/`#314`, closing upstream issue `#309`): **Settings > Appearance >
  Compositor** now has foreground and background opacity sliders, a backend
  selector (Automatic, XRender, GLX, experimental EGL) and start/stop, driven by
  the Picom configuration file instead of process polling, so the controls no
  longer appear and disappear. The new `scripts/dwm-settings-picom` (Python,
  JSON protocol 1) edits `picom.conf` while preserving comments, unrelated
  settings and included files, validates before publishing, keeps the ten most
  recent backups and rolls back a failed activation. Automatic picks GLX for an
  accelerated Intel/AMD renderer and XRender otherwise (NVIDIA adds
  `--xrender-sync-fence`), retrying XRender once if automatic GLX fails to start.
  Autostart, the Control Center's Restart Picom and Toggle Compositor, and
  `theme-apply.sh` all go through the helper, so the backend no longer differs
  between login and a manual restart (the Control Center used to start Picom
  without `--backend`); theme changes reapply opacity without storing it in
  themes. The old process watcher and its `dwm-settings-appearance
  watch-compositor` command are gone, and the compositor inventory and
  integration now report "controls use its configuration file". `python` is now
  listed in the `desktop` profile and the live ISO because login starts the
  compositor through the helper.
  Lyona adaptations: state, backup and include paths use `lyona`, not
  `dwm-titus`; every new pixel constant in the pane uses `Theme` tokens.
  **Race fixed beyond upstream:** the helper's `picom --diagnostics` status probe
  claims the compositor selection for a moment, so a Settings refresh landing
  during `start` made Picom refuse with "Another composite manager is already
  running". `launch()` now waits up to two seconds for that owner to release
  the selection and retries up to three times, while a real second compositor
  (which keeps the selection) still fails immediately. The Picom runtime test
  failed in four of six runs before this and passes six of six after, and three
  new unit tests cover the retry, the real-second-compositor case and the bound.
  Not yet verified: the NVIDIA image (`auto` should resolve to XRender with
  `--xrender-sync-fence`, and `picom --diagnostics` must work without a running
  compositor on the proprietary driver) needs a check on real hardware, to be
  recorded in `docs/evidence/`.

- Polish the Power menu, Settings, cursor updates, tray, and Quick Actions
  (Sync Sprint 3 S3-06, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`, ported
  from upstream `#307`/`56ec27b`, closing issues `#302`–`#306`, plus the
  focused-screen hunk from `44800ba`): Power menu labels simplify ("Log Out"
  → "Logout") and unavailable actions stay selectable so choosing one can
  explain why, instead of just disappearing from tab order. Settings opens
  fullscreen on the focused screen like System Health — reversing this same
  Unreleased section's earlier 1180x760-clamped window size. Appearance now
  scrolls vertically without diagonal drift or overscroll bounce. The system
  tray hides Blueman's redundant icon while keeping the Bluetooth widget
  itself. Quick Actions gains Self-Heal, running a user-configured script in
  a terminal with its progress and any authorization prompts visible; with
  no script configured it explains that rather than silently doing nothing
  (decision D-6: upstream parity, no default script ships, not auto-wired to
  `dwm-system-health`'s own repair flow — filed in `ROADMAP.md` Future
  Evaluation). Cursor theme/size changes now take effect immediately: a new
  `scripts/dwm-cursor-reload` (ctypes against libX11/libXcursor/libXfixes,
  no new Python dependency) replaces named cursors already held by existing
  X11 clients, and the choice is published through xsettingsd for GTK
  applications, without requiring a reboot or re-login.
  Lyona adaptations: Lyona has no `dwm-xsettings`, so cursor publication was
  built on top of `scripts/dwm-settings-display`'s existing DPI xsettingsd
  writer instead of a separate daemon-lifecycle helper — its atomic,
  symlink-safe write-and-reload logic is now a small shared, sourced
  function (`scripts/dwm-xsettings-config.sh`) so both DPI and cursor keys
  can edit the same `xsettingsd.conf` without clobbering each other, verified
  directly: writing a cursor key preserves an existing `Xft/DPI` line and
  vice versa. `scripts/theme-apply.sh` calls the new
  `scripts/dwm-cursor-reload` after applying a theme; since Lyona's
  theme-apply.sh has no upstream `STRICT_PERSONALIZATION`/`XSETTINGS_HELPER`
  concept, a failed live cursor refresh logs a warning rather than failing
  the whole apply, matching this script's existing tolerant style for other
  best-effort desktop-integration steps (gsettings, xfconf-query). Verified
  live against this sandbox's real X11 session: `dwm-cursor-reload` updates
  73–122 named cursors across runs with no errors, and the full X11
  cursor-replacement/rollback round trip (`tests/test-cursor-reload.py`,
  ported minus the `dwm-xsettings`-specific XSETTINGS-publication half,
  which doesn't apply) passes end to end under `xvfb-run`, matching the
  ported `check-cursor-reload` Makefile target. Caught and fixed along the
  way: `tests/test-dwm-settings-theme.sh`'s real `theme-apply.sh` calls were
  unintentionally reaching this sandbox's real DISPLAY, since the tests
  never explicitly isolated it, which would have live-mutated real cursor
  state on every run wherever DISPLAY happens to be set — the whole file now
  defaults `DWM_APPEARANCE_CURSOR_HELPER` to a no-op, matching a similar
  isolation fix upstream made independently in `tests/test-install-preservation.sh`
  (also ported).
- Reduce Settings startup work and readiness (Sync Sprint 3 S3-05,
  `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`, ported from upstream `#291`
  (Settings half of `d359a4f`), `#294`/`080b39e`, and Lyona's own fix for
  open issue `#315`): every Settings pane is now lazily loaded through a new
  `DeferredSettingsPane.qml` (`Loader { active: visited }`) that stays
  instantiated once visited, so switching sections preserves drafts, scroll
  positions, and each pane's own operation model instead of recreating it;
  `SettingsModel.qml` skips re-activating an already-selected section (three
  call sites) and opens with a new, narrower `refreshCapabilities()` instead
  of a full `refresh()`, since `activateSection()` already refreshes the
  newly-selected section on its own. `InputSettingsPane.qml`'s label column
  now wraps instead of pushing controls off-screen for long labels.
  `scripts/seed-autostart-overrides.sh` now strips stray `X-DWM`/`dwm`
  tokens out of a vendor entry's `OnlyShowIn` (which otherwise silently wins
  over `NotShowIn` and defeats the exclusion after a user-service restart
  reseeds it) and refuses to scope an entry that has both keys, rather than
  producing an ambiguous result.
  For open issue `#315` (no upstream fix; Lyona's own implementation):
  `DeferredSettingsPane` reserves the pane's layout space and shows a
  "Loading…" placeholder while its `Loader` is still async-instantiating,
  then fades the real content in (`Theme.reducedMotion`-aware), instead of
  popping in and reflowing the window on first visit.
  Lyona adaptations: `refreshCapabilities()` and its `capabilityRefreshPending`
  debounce didn't exist in Lyona yet (upstream had already split them out of
  `refresh()` before Sprint 3's own scope) — added them as the minimal
  dependency this port actually needs, without porting the unrelated
  `capabilityById()` staleness guard that came bundled with them upstream,
  since nothing in this diff touches that function. New
  `tests/test-quickshell-settings-responsiveness-xvfb.sh` (with
  `tests/fixtures/settings-responsiveness.py` and
  `tests/qml/SettingsResponsiveness.inc`) verified passing end to end against
  the real `quickshell` runtime. Upstream's `#295`/`8df119c` (a race fix for
  a "restart quickshell, verify notification policy persisted" test) was
  **not ported**: that test scenario doesn't exist in Lyona, which already
  tests notification-policy persistence a different, race-free way (through
  `ipc`-polled `policyState` assertions in
  `tests/test-quickshell-large-surfaces-xvfb.sh`, tracing back to Lyona's own
  history rather than upstream's `#204`) — there is nothing for the fix to
  apply to. `.github/PULL_REQUEST_TEMPLATE.md`, `AGENTS.md`, `CONTRIBUTING.md`,
  `TASKS.md`, and `docs/PRE-P7-MAINTENANCE.md` changes were not ported
  (review-process wording and Lyona's own separately-maintained planning
  docs).
- Hide the Docked/Undocked automatic-layout controls when no system battery
  is present (Sync Sprint 3 S3-03, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  upstream issue `#310`, still open upstream — no upstream code exists, this
  is Lyona's own implementation): `scripts/dwm-settings-display-profiles`
  gains `system_battery_present()`, reading
  `/sys/class/power_supply/*/{type,scope}` and treating only `type=Battery`
  with a `scope` other than `Device` (or no `scope` file, for older ACPI
  drivers) as a real system battery — peripheral HID batteries (mice,
  keyboards) report `scope=Device` and are excluded, matching the issue's
  acceptance criteria exactly. `status()` reports the new `battery` field and
  returns early (empty profiles) when it's false. Settings' new
  `automaticDisplaysRelevant` property binds the whole "Automatic layouts"
  section's visibility to that field. Verified against this sandbox's real
  `/sys/class/power_supply`, which holds exactly the peripheral case the
  issue calls out (a `hidpp_battery_18` wireless-mouse battery,
  `scope=Device`): `system_battery_present()` correctly excludes it and
  reports `battery: false`.
- Add explicit Docked and Undocked automatic display layouts to Settings
  (Sync Sprint 3 S3-02, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`, ported
  from upstream `#290`/`6b7548b`): a new unprivileged
  `scripts/dwm-settings-display-profiles` (Python) edits autorandr's `mobile`
  (Undocked) and `docked` profiles without ever applying a layout — autorandr
  itself applies it at login/hotplug. Settings gains saved-layout previews,
  detected/currently-applied status, draft editing (Edit saved/Create draft),
  and confirmed saves with backups, alongside the existing manual "Saved
  layouts" (named, privileged Use-at-next-login) controls, which this does
  not touch. Confirmed saves merge `set,crtc` into autorandr's
  `skip-options` so session-specific CRTC assignments and output properties
  can't invalidate layout matches.
  Lyona adaptations: `autorandr` added to the `arch:desktop-optional`
  package group (`scripts/dwm-packages.sh`) so a missing package degrades
  the automatic-layouts UI rather than failing installs — verified on this
  sandbox, where `autorandr` is genuinely absent, that `status()` reports
  `available: false` with the adapted message instead of erroring; the
  install message itself reads "Install the optional autorandr package
  (pacman -S autorandr)...", not upstream's Fedora wording; backups move
  from upstream's `~/.config/dwm-titus/display-profile-backups/` to
  `~/.config/lyona/display-profile-backups/`, matching the existing
  `~/.config/lyona/display-profiles` convention; the Python helper is
  registered in `INSTALL_COMMANDS` only (not `check-shell`/`check-format`),
  matching the existing `dwm-system-management` exception, with its own new
  `check-display-profiles` Makefile target rather than folding into
  `check-settings` as upstream does. `scripts/autostart.sh` runs no
  competing profile-apply at login, so no autostart change was needed.
- Replace the Displays pane's raw X/Y position inputs with relative
  placement (Sync Sprint 3 S3-01, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  ported from upstream `#289`/`55dbd76`, plus `6b7548b`'s driver-quirk fix to
  `discover()` pulled in early since it affects placement too): a new pure
  `config/quickshell/settings/DisplayLayout.js` computes placement math and a
  numbered, proportionally-scaled layout preview from monitor geometry; each
  output card now has a "position relative to" selector and Left of/Right
  of/Above/Below buttons instead of numeric X/Y fields.
  `scripts/dwm-settings-display discover()` emits new `mode-size` records
  parsed from `xrandr --verbose`, since RandR mode labels are driver-arbitrary
  strings that can't reliably be parsed for pixel dimensions.
  Lyona adaptations: the upstream diff was ported into Lyona's existing
  `DisplaySettingsPane.qml` and `SettingsModel.qml` rather than taking
  upstream's files, since Lyona's pane already carries the resolution
  countdown, `ShellButton` primary/pending states, and DPI-decoupling
  workflow from an earlier sync phase; every new pixel constant in the
  preview tile is wrapped in `Theme.dp()`. Verified against this sandbox's
  real dual-monitor hardware (`DisplayPort-0` 2560x1440 normal/primary,
  `DisplayPort-1` 1920x1080 rotated right at x=2560): `discover()` emits
  correct `mode-size` records for both real outputs.
- Close `ROADMAP.md` Phase 6 (System Management) (Sync Sprint 2 S2-07,
  `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, upstream closed its own Phase 6
  with docs-only commits whose Fedora-44-evidence prose isn't ported; used as
  a qualification checklist instead): measured, not assumed, idle CPU with
  all seven `watch-*` domains (updates, time, locale, accounts, printers,
  storage/`watch-mounts`, security/`watch-units`) subscribed — a new
  CPU-sampling stage in
  `tests/test-quickshell-system-management-xvfb.sh`, Phase 5's own
  closed-shell methodology applied to this pane's live subscriptions, read
  0.00% and 0.50% across two runs. Added a new "System information, storage,
  and security" record-source reference and a "Settings Information Card and
  Health Navigation" section to `docs/P6-SYSTEM-MANAGEMENT.md`. `ROADMAP.md`
  Phase 6 is now `Status: Complete (2026-09-19)` with a Completion Evidence
  section recording D-5's permanent firewall-manager generalization and the
  sprint's carried-forward limitations (no PackageKitGlib bindings or
  multi-monitor hardware in this sandbox; `xkbset` still unavailable, carried
  from Phase 5). `docs/UPSTREAM-SYNC.md`'s status table now reflects Sprint 1
  and Sprint 2 as done. `TASKS.md` replaced with a first-pass Phase 7 (Arch
  Image and Release Qualification) task breakdown, grounded in
  `docs/RELEASING.md`'s own already-documented gap ("has not been
  boot-tested end-to-end on real hardware or in a VM") rather than invented
  from nothing; genuinely open questions (legacy BIOS scope, specific
  hardware/VM targets, NVIDIA hardware availability) are flagged inline for
  the user to resolve rather than guessed, per their own explicit direction
  when asked how to scope it.
- Add the System Settings information card and Health navigation for the
  minor-2 records S2-05 wired in (Sync Sprint 2 S2-06,
  `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported from upstream `#287`,
  commits `cc96efd`/`0c9d07c`; `39ce924` targets a harness Lyona never
  ported, nothing to port): new
  `config/quickshell/settings/SystemInformationControls.qml` renders system
  information, a virtualized (240px, bounded to 256 rows) storage overview,
  privacy/security status, and diagnostics/recovery guidance in the System
  pane. The fixed "Open System Health" button calls the now-wired
  `SystemManagementModel.openHealth()`, which opens the existing
  `dwm-system-health` full-screen window and closes Settings;
  `shell.qml` resolves the target screen through a three-way fallback (the
  Settings window's own current screen, then a requested screen, then the
  active panel's screen) so Health always opens where Settings actually was,
  including after the window moved between screens.
  Lyona adaptations: the security list carries D-5's 7 identifiers
  (`firewalld`/`ufw`/`nftables` as three distinct rows, not upstream's single
  "Firewall service" row); action-availability checks read `.status`, not
  upstream's `.availability` (matches `parseSnapshot()`'s actual field name —
  the same mismatch already found and fixed for `canNtp` back in S1-08);
  recovery guidance names Arch/Lyona tooling (`pacman -Qkk`, `arch-chroot`
  from the Lyona installation media, `lyona-update rollback`) in place of
  upstream's Fedora-specific `dnf`/`rpm -Va`/Anaconda rescue references, with
  a grep gate now built into `tests/test-quickshell-system-management.sh` so
  none can silently reappear.
  Also ported upstream's `tests/qml/SystemInformationUi.qml` and
  `tests/qml/SystemHealthNavigation.qml` harnesses, each as Lyona's own
  standalone `tests/test-quickshell-{information-ui,health-navigation}-xvfb.sh`
  + `Makefile` target (following `tests/test-quickshell-update-ui-xvfb.sh`'s
  established isolated-shell.qml pattern, `cp -a`-ing the real
  `config/quickshell` directories into a scratch dir rather than upstream's
  single-giant-xvfb-file convention) — the health-navigation one
  programmatically extracts `shell.qml`'s actual `targetScreen:` expression
  via a small Python template step, so it can never silently drift out of
  sync with the real production binding. Verified: both new xvfb suites pass
  3/3 consecutive runs (the information view across all three of upstream's
  own evidence window sizes); the full `tests/test-quickshell-system-management-xvfb.sh`
  integration suite and full-tree qmllint (still the same 15-warning
  baseline) both stayed clean after wiring the new card into the live pane.
- Wire the information/storage/security readers from S2-01 through S2-04
  into the system-management snapshot protocol as minor `2`, both on the
  Python provider and the Quickshell consumer (Sync Sprint 2 S2-05,
  `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported from upstream `#285`/
  `#286`, commits `7954c54`/`177e3c3`/`b19fb90`/`3232932`/`4aee614`):
  `InformationSnapshotSources`/`build_information_snapshot()` assemble the
  new records; `snapshot`/`snapshot-core`/`snapshot-without-storage` are now
  three distinct fixed CLI commands — a required (recovery-only) read always
  asks for `snapshot-core` (native rows only, no information block, so it
  never opens the filesystem inventory's unmonitored initialization gap or
  falsely marks storage/security as freshly re-verified when it didn't
  actually probe them); an optional read asks for `snapshot-without-storage`
  until the `storage` domain's own `watch-mounts` subscription is ready,
  then `snapshot`. New
  `config/quickshell/systemmanagement/SystemInformationProtocol.js` mirrors
  the Python side's ownership/validity rules for the QML parser
  (`SystemManagementModel.qml`) without duplicating either list. Two new
  discovery domains, `storage` and `security`, join the existing four in
  `SystemProviderDiscovery.qml`, which also gained upstream's per-launch
  isolated monitor (a `generation`/`serial`-stamped identity and callback
  set created fresh per `Process` launch via `Component.createObject()`), so
  a stale timer, parser line, or exit signal from a retired monitor can
  never be mistaken for a replacement one's, even within one pane cycle.
  `openHealth()`/`healthModel`/`targetScreen`/`onHealthOpened` wire the
  `health-open` action through to the existing `dwm-system-health` view,
  closing Settings on open.
  Lyona adaptation (D-5): `INFORMATION_SECURITY_IDS`/`securityIds()` carry 7
  identifiers (selinux, secure-boot, firewalld, ufw, nftables,
  root-encryption, screen-lock), not upstream's 5 — `InformationSnapshotSources.security()`
  dispatches firewall identifiers through the existing `read_firewall_status(kind)`
  from S2-02; every state-count assertion (Python and QML) is 21, not
  upstream's 19.
  **Real bug found and fixed during verification** (not a mechanical port
  issue — a genuine correctness gap this session's own live xvfb testing
  caught): a required (recovery-only) snapshot read can silently "steal" the
  exact execution slot that a *different*, settling discovery domain's own
  pending-cycle signal had just triggered, because a queued
  `root.requiredPending` flag upgrades the very call that signal produced.
  Since required reads intentionally skip discovery-token draining, that
  domain's cycle was left stuck in `settling-pending` forever with nothing
  left to re-trigger it — reproduced live via a delegated `printers-open`
  dispatch that never recovered even after 100 seconds of retries. Fixed in
  `SystemManagementModel.qml`'s `requestSnapshot()`: when a call proceeds as
  required and other domains still have work pending, it now queues
  `root.snapshotPending = true` so the existing `onRunningChanged` retry
  logic follows up with a real optional drain once the required read
  finishes.
  Also fixed a pre-existing, unrelated dead/wasteful code path found in the
  same function while making this required edit: `main()`'s `try: backend =
  PackageKitBackend(); lines = build_snapshot(backend)` discarded that
  second call's result unconditionally a few lines later; removed.
  New `tests/qml/tst_system_information_protocol.qml` (16 tests, matching
  `tst_system_regional_preflight_protocol.qml`'s established pattern for
  testing a pure `.pragma library` protocol file directly) — a Lyona-specific
  addition per the sprint document's own suggestion, since upstream never had
  a dedicated test file for this library. Did not port upstream's separate
  `tests/qml/SystemNativeDiscovery.qml`/`SystemProviderGeneration.qml`
  integration-level harness (`b19fb90`, `3232932`) or the matching
  `ComposedFixtureSnapshotTests` Python class (`4aee614`) and their
  supporting fixtures — Lyona never ported that harness family for the
  original four discovery domains either, and the generation/serial monitor
  isolation it targets is already exercised end-to-end (including the
  starvation-bug fix above) by the existing, much larger
  `tests/test-quickshell-system-management-xvfb.sh`, which this change
  extends with new minor-2 content, six-domain-readiness, and
  `openHealth()`/Settings-closing assertions instead.
  Verified live on this sandbox: `snapshot`/`snapshot-core`/
  `snapshot-without-storage` all produce correct real output (real OS/
  hardware/security/filesystem data at minor 2, correctly empty/partial
  information at minor 1 and mid-storage-startup); the full ported
  `InformationSnapshotTests` (10 tests) and new `tst_system_information_protocol.qml`
  (16 tests) pass; the xvfb integration suite passed 5/5 consecutive runs
  including the new S2-05 assertions; the full `tests/test-system-management.py`
  suite (684 tests) matches the established baseline (only the 16 pre-existing,
  unrelated PackageKitGlib-unavailable failures in this sandbox).
- Add a bounded mount change monitor to `dwm-system-management` (Sync Sprint
  2 S2-04, `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported from upstream
  `#284`, commits `5b246a0`/`dbbfde1`/`994011f`/`088069b`/`6ac6f5a`):
  `watch-mounts` supervises one fixed `findmnt --poll` child, arming
  parent-death cleanup (`prctl(PR_SET_PDEATHSIG)`) and re-checking the
  original parent PID to close the startup race before `execv`. Readiness is
  observed only from the live, unreaped child's own `/proc/PID/fd` — the
  exact `mountinfo` descriptor opened without `O_CLOEXEC` — never a merely
  temporary parsing descriptor, and never before a one-second deadline
  expires. A pidfd and a signal-wakeup pipe alongside the child's output mean
  no idle polling timer runs once ready. The helper requires write-only pipe
  output (as Quickshell supplies): a socket can half-close without an event,
  and a read/write FIFO retains its own reader, so both are rejected before
  starting a child, and losing the pipe's reader is itself a bounded event,
  not an idle spin. `parse_filesystem_information()` now rejects (rather
  than silently discarding into "partial") a filesystem inventory beyond its
  256-record limit, since silently dropping is not the same information as
  what a client asked for. Lyona adaptation: replaced upstream's one
  Fedora-specific comment about `CLOEXEC` parsing-descriptor timing with
  neutral wording, since Lyona never targets Fedora; confirmed `findmnt`
  (util-linux) is already tracked in `arch:runtime-required`. Verified on
  this sandbox with a real unprivileged mount namespace (`unshare -rm`):
  `watch-mounts` correctly reports `mount-monitor-ready` then
  `mount-change\tmount`/`mount-change\tumount` for actual `mount -t tmpfs`/
  `umount` calls. The full ported `MountMonitorTests` suite (15 tests,
  including real subprocess signal-cleanup, orphan-reaping, and an
  `LD_PRELOAD`-based real-`findmnt` timing test) passes 3/3 consecutive
  runs. Does not yet wire `watch-mounts` into the snapshot protocol or
  `SystemProviderDiscovery.qml`'s domain list — that's S2-05.
- Reuse the shared power helper's automatic screen-lock evidence in
  `dwm-system-management` through a bounded internal information reader
  (Sync Sprint 2 S2-03, `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported
  from upstream `#282`, commits `92c4543`/`76d0739`/`2fe6f7d`):
  `read_screen_lock()`/`parse_screen_lock()` consume
  `dwm-quickshell-controlcenter power-lock-snapshot`, a new lock-only
  snapshot that reuses `power_status()` without querying UPower, profiles,
  suspend, or lid policy. Hardened the shared probe per upstream: the xset
  screen-saver timeout and gsettings lock-after/lock-on-suspend values are
  now bounds- and type-validated, reporting `partial` (not stale configured
  fallback values) on malformed evidence, tracked through a new
  `lock_malformed` status row. Locker readiness now matches the user's
  effective UID and current `DISPLAY` through bounded procps environment
  matching, so a locker on another display or missing display evidence
  cannot establish readiness. Lyona adaptation: Lyona autostarts
  `dwm-lock-watch` (a reactive watcher for logind's `Lock` signal,
  independent of X11-idle timeouts) alongside `light-locker`; a new
  `configured_lock_running()` recognizes either mechanism as "running"
  evidence when `power_lock_managed=1`, while `start_configured_light_locker`/
  `stop_configured_light_locker` keep using the light-locker-only,
  DISPLAY-scoped check since they only ever manage that daemon's own
  lifecycle. `dwm-watchdog.sh`'s shared `run_bounded()` gained an optional
  `bounded_foreground` flag so a nested X11/GSettings probe stays inside the
  information reader's own timeout-owned process group instead of escaping
  it. `PowerModel.qml`/`PowerSettingsPane.qml`/`ControlCenterWindow.qml` now
  show "Unknown" instead of a stale enabled/disabled/timeout value when the
  lock record isn't `available`. Verified against this sandbox's real
  session: `power-lock-snapshot` and `read_screen_lock()` both correctly
  report `available`/`enabled` from the real X11/gsettings/light-locker
  state; `tests/test-quickshell-power-backend.sh` (including a new
  Lyona-specific managed-lock case exercising real `dwm-lock-watch`
  evidence via `pgrep --pid`) and `tests/test-quickshell-controlcenter.sh`
  pass 3/3 consecutive runs; the full `tests/test-system-management.py`
  suite (659 tests, +8 new `ScreenLockTests`) passes with only the
  pre-existing, unrelated PackageKitGlib-unavailable failures.
  `tests/test-quickshell-settings-xvfb.sh`'s new lock-record fixture cases
  were ported but could not be executed in this sandbox, which lacks the
  suite's required `xkbset` binary (a pre-existing, unrelated gap).
- Add bounded security status readers to `dwm-system-management` (Sync
  Sprint 2 S2-02, `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported from
  upstream `#280`/`#281`): `read_selinux_status()` (runtime enforcement
  first, config fallback only when the runtime interface is absent),
  `read_secure_boot_status()` (the fixed EFI `SecureBoot` variable, never
  inferring "disabled" from mere absence or a denied read),
  `read_root_encryption()` (resolves LUKS/dm-crypt ancestry above `/` from
  bounded `lsblk --json`, requiring a complete, unambiguous block-device
  graph before claiming either answer). Lyona adaptation (D-5, decided
  2026-09-16): upstream's `FirewalldRead` only ever asks about
  `firewalld.service`, but a default Arch/CachyOS install runs no firewall
  at all -- generalized into `FirewallUnitRead`/`read_firewall_status(kind)`
  over `firewalld`, `ufw`, and `nftables`, the same real, distinct systemd
  units either package ships, so the eventual Settings card shows honest
  per-manager status instead of only ever reporting on firewalld. Verified
  against this sandbox's own real system: SELinux correctly `unsupported`,
  Secure Boot correctly read as disabled from the real EFI variable,
  firewalld/ufw correctly `unsupported` (not installed) while nftables
  correctly reads as installed-but-disabled, and root encryption correctly
  resolves to `unencrypted` from this machine's real block-device topology.
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
  when `VERSION_ID` itself was not available, verified against both a
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
- Open Settings full screen on the active screen, like System Health (Sync
  Sprint 3 S3-06 `#302`, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  upstream `#307`/`56ec27b`), and tighten its navigation rows, pane margins,
  capability cards, and display controls so more options remain visible
  without reducing the configured text scale. This supersedes the earlier
  1180x760-with-clamping window size from this same Unreleased section.

### Fixed

- A Settings pane can no longer be hidden forever by a read that never finishes
  (#76). Since the loading gate (S5-01) a pane stays hidden and disabled until
  every read it waits on has finished, with no upper bound, so one hung helper
  left it on "Loading settings..." for as long as it hung (the System pane can
  wait about 12 s on its own when a discovery watch is slow).
  `DeferredSettingsPane` now has a `loadingTimeoutMs` cap (5 s): when it passes
  with the pane selected and its component ready, the pane is presented with
  what it has. The fast path is unchanged. New stages in the responsiveness
  harness create a pane whose reads never finish and check that it is hidden
  until its cap and usable after; removing the cap fails them.

- `tests/test-quickshell-system-management-xvfb.sh` no longer races the
  discovery subscriptions. It asserted the native provider and state statuses
  (`available`) before waiting for each discovery domain to connect, so on a
  slower host they read `partial` and it failed in the full-suite CI image; it
  now waits for every domain first. Its D-3 check also asked
  `prepareDelegate(accounts-open)` once, straight after the timezone dispatch,
  and got the shared operation model's "busy" message when that was still
  settling; it now asks again until the D-3 reason appears, still requiring
  every attempt to be refused with nothing pending. It failed 4 of 4 runs in
  the CI container before and passed 5 of 5 after.
- `tests/test-quickshell-design-system.sh` checks the CI layout as it is now.
  It still expected the hosted `c-cpp.yml` job to name the `qml-validation`
  package profile twice, which stopped being true when that job became the
  desktop smoke test (it installs `ci-smoke`) and QML validation moved to
  `full-suite.yml`, so `make check` failed there. It now requires each workflow
  to take its packages from the right profile and to hard-code neither
  `quickshell` nor `qt6-declarative`.
- The Settings > System pane now waits for the update card's own reads (#77).
  Entering the section re-runs `updateModel.refresh()` and `refreshBackups()`,
  but the pane only waited on the system-management model, so the installed
  version and the "Available: ..." row could still change after the pane had
  presented. `UpdateModel` has a read-only `initialLoading` for its local
  reads (`versionProcess`, `backupsProcess`; not the network check) and the
  System pane's `dataLoading` includes it. This also corrects the Sprint 5
  entry above, which said those reads only happen at shell start. The
  responsiveness harness delays the version read past the System snapshot and
  checks the pane stays hidden until it finishes.

- Settings > Bluetooth device rows no longer clip their address line at large
  text sizes. The row had a fixed height (`Theme.dp(68)`) while its two text
  lines scale with the font, so at 200 percent text with Noto Sans (a line
  height of about 1.36, against about 1.2 for the FreeSans fallback) the second
  line ran a few pixels past the row. The row now grows with its content, never
  below the old height. The responsiveness harness had passed only where the
  host's font is short, and failed in the full suite's CI image; its fixture now
  pins every `UiText` to Noto Sans's line height so a local run answers the same
  way as CI.
- `tests/test-seed-default-apps.sh` no longer depends on the host lacking a real
  Celluloid. Its "handler whose program is not installed" case only removed a
  stub from its own `PATH`, so on a machine with Celluloid installed (the full
  suite's CI image) the real one satisfied the check and the case failed with
  "a handler whose program is not installed was accepted". It now runs that case
  with a `PATH` of only the tools the script needs plus stub programs, after a
  control run proving the setup is sufficient.
- `scripts/ci-local.sh` fails loudly and cleans up after itself (#78). A failing
  `git ls-files` used to be hidden by a process substitution, so tar copied only
  `.git` and the run tested an empty tree; the file list is now written to a
  file, checked, and any files tar could not copy are reported. The build
  context and file list are removed by the EXIT trap even when `docker build`
  fails; the container has a unique name, `--init`, a `lyona-ci` label and
  `--rm`, and lives at most four hours, and the trap removes only a container
  this run started (a reused PID used to make it delete an older `--keep`
  container). Logs go in a `mktemp -d` directory instead of a predictable
  `/tmp` path, host-side reads skip symlinks a test left behind, and the usage
  text and CONTRIBUTING say the tool runs the tree's own code, for trusted
  branches only. It also works from a linked git worktree now: `.git` there is
  a one-line pointer file, so the container got no repository and every
  target that reads git history failed (`check-release-helper`: "not a git
  repository"); the shared repository is shipped as `.git` with the worktree's
  own HEAD and index.

- A tiled selected window no longer covers floating windows and popups
  (`dwm.c` `raiseselectedclient()`, from the "updating floating windows" work
  of 2026-08-29). Every restack raised the selected client above the floating
  clients it had just raised, and above popups an application had raised itself,
  even when the selected client was tiled. It now raises the selected client only
  where `restack()` itself does: when it is floating or the layout is floating,
  which is what that change needed so a selected window is not left under the
  floats. Found because `make check-xvfb-runtime` had failed since that commit
  (an override window raised by an application was buried after a layout
  change); the test now passes end to end, and gained checks that a floating
  window stays above a selected tiled one and that the selected window comes to
  the front in the floating layout.
- The System update UI test fixture (`tests/fixtures/system-update-ui-provider.py`)
  now answers the storage (`watch-mounts`) and security (`watch-units security`)
  watches that Sync Sprint 2 added. It rejected them as invalid arguments, so
  `make check-quickshell-update-ui-xvfb` had failed since the Sprint 2 merge even
  though every QML assertion passed.
- The full-suite workflow and `scripts/ci-local.sh` pick the installable packages
  with one `pacman -Slq` query instead of one `pacman -Si` per package (#79).
  For the 114 packages in the list the loop took 22 s in the CI image and the
  single call under a second, and both select the same 111 (the three multilib
  gaming packages are absent from the container's repositories either way). The
  workflow step was run as the workflow's shell runs it and the generated
  Dockerfile was built with a list of real, bogus and multilib names.

- The Gear Lever installer now verifies the Flathub remote before it installs
  (Sync Sprint 5 S5-02, ported from upstream `#334` `dd64bbf`, issue `#332`).
  It refused a `flathub` remote with the wrong URL already, but accepted one
  with signature verification disabled or one that was disabled, and did not
  check a remote it had just added. A new `scripts/dwm-flatpak-setup
  --user|--system` checks the official URL, `no-gpg-verify` and `disabled`
  (reading disabled remotes too), adds the official remote when there is none
  and verifies it again, and `scripts/install-gearlever` calls it right before
  `flatpak install`. Lyona adaptation: an app that is already installed exits
  before the helper, so a remote problem never makes an installed app report a
  setup failure. The tests script the `flatpak remotes` output in upstream's
  column format; that format was then checked against real Flatpak 1.18.2 in
  the CI image (it prints `disabled,no-gpg-verify` comma-joined, as parsed), and
  the helper refused an unsigned, a disabled and a wrong-URL `flathub` remote
  and added then verified the official one (#80).
- `check-deps.sh` now recognises every terminal `dwm-terminal` can launch
  (Sync Sprint 4 S4-05, ported in part from upstream `#255`/`902a138`). Its
  fallback list stopped at Alacritty, Kitty and st, so a machine whose only
  terminal was `warp-terminal` or `xterm` was reported as having none, though
  `dwm-terminal` and `dwm-diagnostics` accept both. When no terminal is found the
  hint recommends only terminals in the official repositories (Alacritty, Kitty,
  xterm); `st` and `warp-terminal` are AUR-only, so they are detected but not
  suggested, unlike upstream's wording. The `dwmterm` integration itself is
  declined: it is packaged in neither the official repositories nor the AUR
  (re-checked 2026-09-20), and promoting it to the first probe would make
  `dwm-terminal` miss on every launch. The default stays `alacritty`.

- `scripts/install-gearlever` now finds `dwm-flatpak-setup` with `CDPATH=''`,
  like the repo's other scripts. With `CDPATH` exported and a matching
  directory on it, `cd` printed a path, the helper lookup returned two lines and
  the helper was not found (exit 127), which `install.sh` only reports as a
  warning (#80). New case in `tests/test-install-gearlever.sh`.

- Fix two installer and session start-up problems (Sync Sprint 4 S4-04,
  `docs/SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`, ported from upstream
  `#283`/`378f06e` and the autostart hunk of `44800ba`). `dev-sync-install.sh`
  no longer demands a dwm restart after a reinstall that leaves the running
  binary's bytes unchanged: reinstalling unlinks the running executable, and
  the old check treated that unlinked (`(deleted)`) file as a mismatch before
  ever comparing bytes, though `/proc/PID/exe` still exposes the inode.
  It now compares the bytes even when the file is deleted. Separately,
  `autostart.sh` runs `systemctl --user daemon-reload` before starting
  `wm-graphical-session.service` every time, instead of only after a failed
  start, so autostart exclusions an installer seeded after the user manager
  began apply on the very first login. The new dev-sync test uses a private
  child process running a deleted copy of a binary, never the host window
  manager, and registers its cleanup through `lib.sh`'s stack in place of
  upstream's hand-written trap. Both new assertions were confirmed to fail on
  the previous code. Upstream's `test-fedora-packages.sh` hunk is not
  applicable.

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
- Super+M (fullscreen) no longer shrinks windows when it returns to the floating
  layout (#83). `fullscreen()` switches to monocle and back with the layout
  switch, and since the floating-toggle change (S5-03) that switch shrinks
  every visible tiled window by 15% when it enters the floating layout, so a
  round trip from the floating layout came back at 85% of the monocle size.
  `setlayout()` now takes its shrink from a `shrink` flag: the key and button
  entry point still shrinks, `fullscreen()` does not. New case in
  `tests/test-xvfb-runtime.sh` (it fails on the previous build, and checks that
  an explicit switch still shrinks).

- Fix `dwm-settings-input`'s device scan silently reporting zero devices when
  `xinput --list --short` failed outright, instead of surfacing the failure.
  It now checks the command's exit status before parsing its output and
  exits with `die` on failure.
- `make check-xvfb-runtime` now turns its test's "skipped" exit status (77:
  Xvfb/xdotool missing) into success like the other Xvfb targets do.
  `make check-quickshell-settings-loading` does the same when python3 is
  unavailable, like the other dependency-dependent checks, instead of failing
  a plain `make check` on such a host (#82). A real failure still fails.

- Fix a race in `dwm-settings-appearance`'s inventory scanner: a named
  coprocess's PID and file-descriptor bookkeeping could be unset by bash
  before the caller read them, if the scan finished first. Replaced with
  process substitution, which captures its PID synchronously and keeps it
  valid regardless of whether the process has since exited. The scan also no
  longer inherits the parent shell's stdin.
- dwm no longer exits when an X client asks for an extreme aspect ratio
  (`applysizehints()`, an issue that predates Sprint 5). With a tiny maximum
  aspect and no minimum size the aspect clamp rounded a side to 0, the
  zero-sized `XConfigureWindow` came back as BadValue, and `xerror()` treated it
  as fatal, so any X client could end the session (#81). The result is now
  floored at 1x1. New `extreme-aspect` client mode and case in
  `tests/test-xvfb-runtime.sh`, which fails on the unpatched build.

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
