# AGENTS.md

## Purpose

This repository is an Arch Linux-only X11 desktop environment built around a
heavily patched fork of suckless dwm and a managed Quickshell shell. The
product is a complete Arch Linux desktop installed from a lyona Arch
installer image or onto an existing Arch Linux installation. Arch Linux is
the sole supported distribution.

Read `SPEC.md` before making product, platform, installer, dependency, or
packaging changes. Treat `SPEC.md` as the source of truth for project scope and
acceptance criteria.

## Priorities

1. Preserve dwm stability and existing user workflows.
2. Keep the C window-manager core small, understandable, and dependency-light.
3. Build a cohesive Arch Linux desktop without moving desktop policy into the C
   event loop.
4. Preserve the Arch install, image, and session contract.
5. Keep installation and settings changes safe, repeatable, reversible, and
   explicit.
6. Prefer focused changes that can be reviewed and tested independently.

## Arch Support Contract

The sole supported platform is Arch Linux. The archiso-based lyona install
medium is the current documented image base, with separate standard and
NVIDIA variants. The existing-system installer also supports Arch Linux.
Every other operating-system identity must fail clearly instead of entering
an untested package or installation path.

## Repository Map

- `dwm.c`, `drw.c`, `util.c`, `tomlparser.c`: window-manager sources.
- `config.def.h`: version-controlled default compile-time configuration.
- `config.h`: local build configuration. Do not overwrite user changes.
- `config.mk`: compiler, include, library, and installation settings.
- `Makefile`: build, install, uninstall, and release targets.
- `config/`: application configuration and default TOML runtime settings.
- `scripts/`: session startup, dependency checks, desktop helpers, and
  operational scripts.
- `install.sh`: supported existing-system installer for Arch Linux.
- `archiso/`, `scripts/build-lyona-arch-iso.sh`: Arch install-medium
  profile and builder (best-effort; see `docs/RELEASING.md`).
- `dwm.desktop`: display-manager X session entry.
- `AGENTS.md`: durable engineering and agent-execution rules.
- `SPEC.md`: product scope, interfaces, and acceptance criteria.
- `ROADMAP.md`: ordered desktop-environment outcomes.
- `TASKS.md`: implementation work for the active roadmap phase only.
- `docs/`: user, contributor, and release documentation.

## Planning Workflow

- Use `SPEC.md` for durable product requirements and compatibility contracts.
- Use `ROADMAP.md` for ordered phase objectives and exit criteria.
- Use `TASKS.md` only for detailed work in the active phase. Replace its task
  set when a phase completes instead of accumulating historical checklists.
- Record completed user-visible behavior in `CHANGELOG.md` and releases.
- Do not mark a task or phase complete without its required validation or a
  precise statement of what could not be tested.
- Treat phase boundaries as review and rollback points. Do not begin the next
  phase in a change that was scoped only to complete the current one.

## Arch Image Rules

- Base released images on the archiso profile documented in `SPEC.md` and
  `docs/RELEASING.md`, layered onto the system `releng` profile.
- Preserve separate standard and NVIDIA image variants. Proprietary NVIDIA
  changes belong only to the explicitly selected NVIDIA image.
- Keep `archiso/packages.x86_64` synced with the shared dependency map (see
  `tests/test-arch-iso-builder.sh`).
- Run `make check-archiso` for archiso or ISO-builder changes, then validate a
  real or virtual install before claiming the image boots or reaches a usable
  desktop.
- Record the archiso build-host version, resulting image checksum,
  architecture, firmware mode, image variant, and untested hardware in
  release evidence.
- This image path is best-effort and has not been boot-tested on real
  hardware or in a VM — do not claim it works until it has been.

## Desktop Settings Rules

- Keep the Settings frontend and all QML unprivileged.
- Read state through stable service APIs, D-Bus, signals, subscriptions, or
  bounded helpers. Do not parse human-oriented output when a machine interface
  exists.
- Separate read-only state, user-session changes, privileged system changes,
  delegated tools, and unsupported capabilities.
- Privileged helpers must be installed root-owned and non-writable, expose only
  allowlisted operations, validate every argument, and require explicit user
  intent through polkit or an equally narrow authorization path.
- Repository or user-writable helper copies must never be elevated.
- Risky changes require preview, confirmation, rollback, or recovery behavior
  appropriate to their impact. Authorization denial must not hide readable
  state.
- Unsupported hardware capabilities must be hidden or explained without
  breaking the rest of Settings.

## Arch Platform Rules

- Detect Arch Linux through `/etc/os-release` and reject every other identity
  before package installation or system changes.
- Keep Arch package capability names in the shared dependency map
  (`scripts/dwm-packages.sh`). Do not scatter package-name lists across
  multiple scripts.
- Use `pkg-config` for X11 and library discovery where available. Avoid legacy
  hardcoded paths such as `/usr/X11R6`.
- Respect `CC`, `CFLAGS`, `CPPFLAGS`, `LDFLAGS`, `PREFIX`, `DESTDIR`,
  `XDG_CONFIG_HOME`, and the invoking user's home directory.
- Arch package names are not versioned or `-devel`-suffixed the way Fedora's
  were; prefer plain `pacman -Si <name>` checks over guessing at split
  `-devel`/`-libs` naming conventions from other distributions.
- Support both display-manager sessions and `startx`.
- Treat Xorg as required. Wayland-native support is outside the current scope.
- Keep optional desktop components optional. The absence of Picom, a wallpaper,
  or a preferred terminal must not crash dwm.
- Use ASCII punctuation in source, scripts, and new documentation unless a
  file's established format requires otherwise.

## Configuration and Compatibility

- Preserve `config.def.h` as the default template.
- Never replace an existing `config.h`, user TOML file, `.xinitrc`, or
  application configuration without explicit user consent or a backup.
- Runtime TOML files live under
  `${XDG_CONFIG_HOME:-$HOME/.config}/lyona/`.
- Preserve hot reload behavior for `hotkeys.toml`, `themes.toml`, and
  `window-rules.toml`.
- `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/` is managed exclusively by
  lyona. Unlike user-owned dwm TOML files, install/update flows may replace
  this directory from tracked `config/quickshell/` to prevent stale shell code.
- Relaunch the managed Quickshell instance through
  `dwm-quickshell-controlcenter action restart-quickshell` or the normal
  autostart path. Do not manually start it with a repo-local `--path`, because
  hotkeys target `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml` and
  Quickshell treats different config paths as different IPC instances.
- Quickshell integration must be event-driven whenever the underlying state has
  a signal, subscription, watch, IPC, or service API. Prefer `xprop -spy`,
  D-Bus/service notifications, process stdout streams, or Quickshell service
  APIs over QML polling timers. Polling is allowed only for inherently sampled
  values such as a clock or CPU load, or when a documented fallback has no
  event source.
- Quickshell must not be an idle resource hog. Avoid resident hidden launcher
  models, overlapping `Process` launches from timers, and duplicate shell
  providers such as running DMS alongside the lyona managed shell. On X11,
  avoid per-screen `Variants { model: Quickshell.screens }` panels unless a
  live CPU sample proves they idle cleanly; prefer a single `PanelWindow` for
  the managed shell. After Quickshell changes, validate `quickshell --no-duplicate`
  in a real or nested X11 session and confirm the Quickshell process is near
  idle when the launcher is closed.
- For Quickshell QML linting, stock `qmllint` must be given explicit Qt and
  Quickshell QML import roots, such as `/usr/lib/qt6/qml`, and a lint-only
  `qs.core/qmldir` module map when checking
  files that import this repository's `qs.core` helpers. `QMLLS_BUILD_DIRS`
  and `QML_IMPORT_PATH` should mirror those roots for language-server tooling.
  Do not treat plain `qmllint` import failures as runtime failures until the
  configured import paths have been verified.
- Keep existing keybindings, window rules, EWMH behavior, multi-monitor
  behavior, and autostart behavior unless the task explicitly changes them.
- When changing defaults, update the relevant documentation and migration
  notes in the same change.

## Shell and Installer Standards

- Use Bash only when Bash features are needed; otherwise use POSIX `sh`.
- For Bash scripts, use `set -euo pipefail` unless a documented reason prevents
  it. For POSIX scripts, use `set -eu`.
- Quote variable expansions, use `command -v`, and avoid parsing human-oriented
  command output when a stable machine interface exists.
- Privilege escalation must be limited to package installation and system-wide
  file installation. Do not run the full installer as root.
- Installation must be idempotent. Re-running it must not duplicate services,
  corrupt configuration, or reset user choices.
- Package installation and service enablement must be visible to the user.
  Do not silently alter bootloader, display-manager, firewall, or other
  security policy settings.
- Network downloads must be optional, clearly reported, and failure-tolerant
  unless the downloaded artifact is explicitly required.
- Run ShellCheck and shfmt on changed shell scripts when available.

## Build and Code Standards

- Keep the existing C99 style and compile with warnings enabled.
- Avoid adding a new library dependency unless it materially improves a
  required feature. Required dependencies must be available on supported
  Arch releases.
- Check allocation, file, Xlib/XCB, parser, and process-launch failures.
- Do not introduce blocking work into the X event loop.
- Keep Linux-specific functionality, such as inotify, explicit and documented.
- Do not commit generated objects, binaries, release archives, or local
  configuration changes unless the task specifically requires release assets.

## Required Validation

Run the smallest applicable set first, then the full relevant set through the
managed test workspace:

```sh
scripts/run-tests make clean all
scripts/run-tests
```

For shell changes:

```sh
shellcheck install.sh scripts/*.sh tests/*.sh
shfmt -d install.sh scripts/*.sh tests/*.sh
```

For Quickshell QML changes, run `qmllint` with the explicit Qt/Quickshell QML
module roots documented in `SPEC.md`, and validate the managed shell in a real
or nested X11 session before declaring runtime behavior verified.

For installer or packaging changes, validate in a clean container or virtual
machine using the supported Arch Linux release.

At minimum, verify dependency resolution, a clean build, staged installation
with `DESTDIR`, installed file paths, and script syntax. A real X11 session or
nested X server is required before declaring runtime behavior fully validated.

Use `${DWM_TEST_TMP_ROOT:-$HOME/tmp}` for test workspaces and clear the exact
run directory after success, failure, or interruption. If a required Arch
path cannot be tested, state exactly what was not tested.

For Arch image changes, follow the complete validation contract in
[SPEC.md Section 9.4](SPEC.md#94-arch-image-validation). Static validation
alone does not prove package resolution, postinstall behavior, first boot, or
hardware support.

## Change Discipline

- Inspect `git status` and relevant files before editing.
- Preserve unrelated user changes.
- Keep commits and patches narrowly scoped.
- Update `SPEC.md` only when requirements intentionally change.
- Update README and user-facing docs when commands, dependencies, defaults, or
  supported Arch versions and architectures change.
- Do not perform destructive Git or filesystem operations without explicit
  authorization.
- Never expose credentials, tokens, private keys, or secret file contents.
