# Changelog

All notable project changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses calendar
versions (`YYYY.MM`, or `YYYY.MM.PATCH` for a second release in the same
month) from `config.mk`. A pre-release appends `-alpha.N`, `-beta.N` or
`-rc.N`.

## [Unreleased]

### Added

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
