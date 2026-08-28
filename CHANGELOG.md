# Changelog

All notable project changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses calendar
versions (`YYYY.MM`, or `YYYY.MM.PATCH` for a second release in the same
month) from `config.mk`.

## [Unreleased]

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

[Unreleased]: https://github.com/technicks89/Lyona/compare/v0.1.0...HEAD
