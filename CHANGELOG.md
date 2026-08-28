# Changelog

All notable project changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses calendar
versions (`YYYY.MM`, or `YYYY.MM.PATCH` for a second release in the same
month) from `config.mk`. A pre-release appends `-alpha.N`, `-beta.N` or
`-rc.N`.

## [Unreleased]

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
  `technicks89`/`lyonasoft.com`. Arch Linux is now the sole supported
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
