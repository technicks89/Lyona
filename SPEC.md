# lyona Project Specification

## 1. Product Definition

lyona is an Arch Linux-only desktop environment for X11. It combines a small,
maintained fork of suckless dwm with runtime-configurable hotkeys, themes, and
window rules, a managed Quickshell shell and Settings layer, and supporting
desktop services and helpers.

The product is a cohesive Arch Linux desktop installed from a lyona Arch
installer image or onto an existing Arch Linux installation. Other
distributions are outside the supported product and validation contract.

## 2. Goals

- Install a complete, daily-usable Arch Linux desktop from a minimal network
  installer base.
- Provide one cohesive Settings experience for common display, input,
  connectivity, audio, power, appearance, default-application, update, and
  system-information workflows.
- Build and run the complete lyona desktop on supported Arch releases.
- Provide safe, idempotent dependency installation and system integration.
- Preserve the speed, simplicity, and direct configuration model of dwm.
- Provide consistent defaults and complete Settings behavior on Arch Linux.
- Support display-manager login and `startx`.
- Support Arch x86_64. Arch aarch64 remains future scope until its installer
  and desktop runtime complete the release validation contract.
- Keep user configuration under standard XDG paths and preserve it on upgrade.

## 3. Non-Goals

- A Wayland compositor or Wayland-native session.
- Pixel-identical behavior across every theme, driver, display manager, or
  third-party desktop utility.
- Automatic installation of proprietary GPU drivers without an explicit
  per-install opt-in (interactive prompt or `LYONA_NVIDIA_DRIVER=1`).
- Automatic bootloader, Plymouth, firewall, or kernel changes outside a
  dedicated image flow that documents and validates them.
- Turning the Settings frontend into a general-purpose root shell, service
  editor, firewall editor, or partition manager.
- Bundling every optional desktop application.
- Supporting Arch releases after they reach end of life.

## 4. Arch Support Contract

The primary release target is the Arch Linux desktop image:

| Target | Current contract |
| --- | --- |
| Base media | lyona Arch installer image (archiso-based; see `docs/RELEASING.md`) |
| Session | Xorg with dwm and the managed Quickshell shell |
| Variants | One standard image; proprietary NVIDIA driver is a per-install opt-in, not a separate image |
| Initial release architecture | x86_64 |

Arch aarch64 is not currently a supported release target. Architecture-aware
package filtering may remain in shared helpers, but it does not constitute an
aarch64 support claim without native installer and desktop runtime evidence.

The existing-system installer supports Arch Linux and uses `pacman`. It must
report the detected distribution and accept only `ID=arch` before package
installation or system changes. Every other operating-system identity must be
rejected. Arch Linux is the sole supported distribution; derivative distributions
are not included by implication.

## 5. Functional Requirements

### 5.1 Window Manager

The installed session must provide:

- Standard dwm tiling, floating, monocle, tagging, focus, and monitor behavior.
- Per-tag layout state and sizing.
- EWMH desktop and active-window integration for external bars and tools.
- Xinerama multi-monitor support.
- Window swallowing.
- Per-client size factors and stack reordering.
- Real and fake fullscreen behavior.
- Window icons from `_NET_WM_ICON`.
- Configured border suppression and cursor-warp behavior.
- Stable handling of applications that omit optional X properties.

### 5.2 Runtime Configuration

The product must load user configuration from:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/lyona/
```

The supported runtime files are:

- `hotkeys.toml`
- `themes.toml`
- `window-rules.toml`

Changes to these files must reload without restarting dwm when the existing
inotify-based hot reload path is available. Invalid configuration must produce
an actionable error and retain safe defaults or the last valid state.

Compile-time defaults remain in `config.def.h`. An existing `config.h` is user
owned and must not be overwritten during installation or upgrade.

Quickshell configuration is a managed shell-layer artifact owned by lyona.
During installation, `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/` must be
replaced from the tracked `config/quickshell/` directory so the running shell
does not fall behind repository behavior. User-owned dwm TOML files remain
preserved, but users should not place unrelated personal configuration under
the lyona-managed Quickshell directory. Quickshell integrations must use
event-driven updates whenever a state source provides a signal, subscription,
watch mode, IPC stream, or service API. Polling timers are acceptable only for
inherently sampled values, such as a clock or CPU load, or as documented
fallbacks when no event source exists. The managed Quickshell shell must remain
low overhead while idle: hidden launcher UI must not continuously filter or
render application models, timer-triggered helper processes must not overlap,
and only one shell provider should run in the lyona session. On X11, the
managed shell must create one `PanelWindow` for every active screen so each
monitor has a bar. The per-screen Quickshell `Variants` design must share its
state providers and be explicitly profiled to show that it remains near idle.

The managed shell requires Quickshell 0.3.0 or newer, matching the version
published in Arch's official `extra` repository. It provides the
`PopupWindow.grabFocus` API used by the shell; an unpatched upstream 0.2.1 is
not sufficient. Anchored control popups
must close on Escape and on a click outside their visible card under X11.
Visible shell surfaces must be opaque and follow the active theme selected in
the user `themes.toml` file.

### 5.3 Session Startup

The project must support:

- A display-manager session installed as `dwm.desktop`.
- A `startx` flow whose `.xinitrc` launches dwm in a D-Bus session.
- Startup without Picom, a wallpaper, or a polkit agent.
- Detection of common polkit agent locations across `/usr/lib`,
  `/usr/lib64`, and `/usr/libexec` layouts.
- Startup helpers that do not create duplicate long-running processes when the
  session is restarted.

Missing optional components must be logged or skipped without terminating dwm.

The default screenshot-to-clipboard binding must capture through the managed
`dwm-screenshot` helper. On X11, the helper must use `maim` to capture without
the mouse cursor and transfer region captures as raw PNG data to an
`xclip`-owned clipboard selection. It must not depend on a resident screenshot
daemon or a GUI-toolkit clipboard owner. Saved captures use JPEG, and a full
monitor capture targets the monitor under the pointer. The recommended desktop
profile must install `maim` when it is available and keep the core install
usable when it is not. `xclip` remains a required runtime package because
other shell features also use the X11 clipboard.

### 5.4 Quickshell Launcher

The Quickshell shell layer must provide the normal X11-compatible application
launching workflow.

The launcher must:

1. Open, close, and toggle through Quickshell IPC so dwm keybindings can
   control it without depending on Wayland global shortcuts.
2. Index desktop applications from the XDG `.desktop` application directories.
3. Ignore hidden, `NoDisplay=true`, and non-application desktop entries.
4. Provide a search-first UI with keyboard focus on open.
5. Filter by application name, generic name, and comment.
6. Support keyboard navigation, mouse activation, Escape-to-close, and
   close-on-launch behavior.
7. Launch applications through a helper that prefers standard desktop-entry
   launchers when available and preserves a terminal fallback for
   `Terminal=true` entries.
8. Avoid Wayland-only shell, compositor, layer-shell, or global-shortcut APIs.
9. Release application-list resources while closed so the launcher does no
   repeated filtering or rendering work when hidden.

The launcher may follow a modular QML structure with small helper scripts,
IPC-facing open/close/toggle functions, and reusable list/delegate patterns,
but X11/EWMH behavior remains the compatibility boundary for this project.

### 5.5 Installer

The supported installation flow must:

1. Read `/etc/os-release`, require Arch Linux, and reject unsupported systems
   before making changes.
2. Resolve Arch package names from one maintained dependency map.
3. Show required and optional packages before installing them.
4. Install only missing required packages unless the user requests a broader
   desktop setup.
5. Create a missing `config.h` from guided compile-time questions, or detected
   and documented defaults for an unattended installation. Preserve an
   existing `config.h`.
6. Build dwm with the system compiler and detected X11 flags.
7. Install the binary, man page, X session file, scripts, and default
   configuration.
8. Seed missing user configuration while preserving existing files.
9. Set ownership to the invoking user for files in that user's home.
10. Support repeated execution without destructive side effects.
11. Print a summary, skipped optional features, and actionable next steps.
12. Offer interactive Xorg display setup when installation runs inside an
    active X11 session. The setup must support resolution, refresh rate,
    position, rotation, primary-output selection, and compatible TearFree
    drivers; preview changes with rollback; and preserve existing system Xorg
    configuration through an isolated managed fragment and backups. When no
    X11 session is available, print the deferred setup command instead.

The existing-system installer may enable the official `multilib` repository
only for the explicitly requested gaming profile. Interactive runs require a
direct confirmation; non-interactive runs require the explicit
`--enable-arch-gaming-repos` approval flag. Recommended and full profiles may
also add the official Flathub remote for the target user and install Gear
Lever (`it.mijorus.gearlever`) as the default AppImage manager.

Kernel headers are an explicit opt-in (`--with-headers`, or an existing DKMS
installation), since nothing in the project needs them except out-of-tree
module builds.

The existing-system installer may additionally add the CachyOS repositories
through `scripts/lyona-cachyos`, which is x86_64 Arch only and always opt-in:
interactive runs require a direct confirmation, non-interactive runs require
`--enable-cachyos-repos` or `--cachyos-kernel`. It selects the repository set
matching the detected ISA level (`znver4`, `x86-64-v4`, `x86-64-v3`, or the
baseline repository), installs the CachyOS keyring and mirrorlists so every
later package is signature-checked, backs up `pacman.conf` before editing it,
and restores that backup if any step fails. It must not enable any other
third-party repository.

The `linux-cachyos` kernel is a separate opt-in on top of that approval. When
it is installed, the installer must make it bootable through the bootloader
already in use -- regenerating the GRUB configuration or cloning the existing
systemd-boot entry -- and must report an unrecognized bootloader rather than
guessing at its configuration.

The archiso installer image separately enables `multilib` in its own
`pacman.conf`, which archinstall copies onto the installed system, and
requests the same repository through the generated archinstall configuration.
Its inclusion is validated as part of the reviewed archiso profile rather than
inferred from existing-system installer approval.

The archiso installer additionally configures the CachyOS repositories on the
live medium before `archinstall` runs, so the base system is fetched from them
once rather than installed from Arch and replaced afterwards, and installs the
CachyOS kernels (`linux-cachyos` and `linux-cachyos-lts`) on the target
without prompting, using the same `scripts/lyona-cachyos` contract. The
installed system must receive the CachyOS mirrorlists and keyring, because a
`pacman.conf` that includes a missing file does not parse at all. Both steps are non-fatal: an
unreachable CachyOS mirror leaves the install on the stock Arch repositories
rather than failing it. The kernels installed there must not become the
default boot entry, and the stock Arch kernel must remain installed and
bootable. When
more than one kernel is installed, the NVIDIA opt-in must use the DKMS driver
with headers for every installed kernel.

A source-checkout update of an existing live installation must use the complete
supported install path. Updating only the `dwm` executable is not a supported
upgrade because it can leave installed helpers, session scripts, the managed
Quickshell tree, and the user data copy at a different repository revision.
When development is performed on a machine running lyona, the
repository-owned `scripts/dev-sync-install.sh` command must synchronize the
checkout to that machine's local live installation before the work is handed
off or considered complete. The command is idempotent and must enforce this
contract for every developer deployment. Every live update must:

1. Build the checked-out revision successfully before replacing installed
   files.
2. Install the system files and refresh
   `${XDG_DATA_HOME:-$HOME/.local/share}/lyona/` and the managed
   `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/` tree from that same
   revision while preserving the user-owned dwm TOML files.
3. Verify the installed binary and the managed Quickshell, data, and script
   trees against the checkout instead of inferring freshness from a clean Git
   worktree.
4. Restart Quickshell through the managed control path and verify its process,
   IPC endpoints, and tray host when no full session restart is pending. If the
   running dwm executable was replaced, defer Quickshell activation to the
   required session restart so the tray host starts before tray clients, and
   distinguish installed state from active runtime state.
5. After a required session restart, verify that the new dwm executable is
   active and that the graphical-session and XDG autostart lifecycle starts
   tray clients for the new X11 session.

### 5.6 Build System

The build must:

- Use a C99-capable compiler and `make`.
- Honor standard environment overrides including `CC`, `CFLAGS`, `CPPFLAGS`,
  `LDFLAGS`, `PREFIX`, and `DESTDIR`.
- Discover compiler and linker flags with `pkg-config` where available.
- Avoid mandatory `/usr/X11R6`, `/usr/lib`, or `/usr/lib64` assumptions.
- Produce a working `dwm` binary from a clean checkout.
- Support staged, unprivileged installation through `DESTDIR`.

Required native interfaces and libraries currently include:

- Xlib
- Xft and Fontconfig
- Xinerama
- Xrender
- Imlib2
- Xlib-XCB
- XCB and XCB RES
- freetype headers
- standard Linux/POSIX process and filesystem interfaces

### 5.7 Quickshell QML Development Tooling

Quickshell QML files are part of the maintained source tree. Systems used to
edit this project should provide both the stock Qt QML tools and a
Quickshell-aware language server:

- `qmllint` is the baseline syntax/static check for individual QML files.
- `qmlls` is the stock Qt QML language server and remains useful for generic
  Qt/QML projects.
- `qml-language-server` from `cushycush/qml-language-server` is the preferred
  editor language server for this repository because it understands Quickshell
  imports, singletons, types, snippets, and workspace QML components.

Arch provides the Qt tools through `qt6-declarative`. Helper binaries
may live outside the default `PATH`, such as `/usr/lib/qt6/bin`, and
`qmllint` may be named `qmllint-qt6`.

`qmllint` must be run with explicit Qt and Quickshell QML import roots. Without
those roots it can report false import failures for modules such as
`Quickshell`, even when the shell runs correctly. Typical roots are:

| Arch QML import roots |
| --- |
| `/usr/lib64/qt6/qml`, `/usr/lib/qt6/qml` |

Language-server environments should expose the same roots:

```sh
export QMLLS_BUILD_DIRS="/usr/lib64/qt6/qml:/usr/lib/qt6/qml"
export QML_IMPORT_PATH="$PWD/config/quickshell"
```

The repository wrapper resolves `qmllint-qt6`, `qmllint`, and the Arch Qt
binary paths, discovers the explicit Qt import roots, and creates the temporary
`qmldir` module map needed for local `qs.*` imports:

```sh
scripts/quickshell-qmllint --root config/quickshell
```

For Arch x86_64, install the pinned `qml-language-server` v1.7.0 Linux AMD64
asset only after verifying the repository-pinned SHA-256 checksum:

```sh
set -eu
asset=qml-language-server-v1.7.0-linux-amd64.zip
curl -fL --output "$asset" \
  "https://github.com/cushycush/qml-language-server/releases/download/v1.7.0/$asset"
printf '%s  %s\n' \
  ad6e88b0fffbe5ee03fc9f6502c0103aa047c02c4942c547715283443bf4e946 \
  "$asset" | sha256sum --check --strict
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -q "$asset" -d "$tmp"
printf '%s  %s\n' \
  928bd00ddb14f00a66f18473c0a492ae7109ee45c02db8bf3f55966229bb863a \
  "$tmp/qml-language-server-v1.7.0-linux-amd64" | sha256sum --check --strict
install -Dm0755 "$tmp/qml-language-server-v1.7.0-linux-amd64" \
  "${HOME}/.local/bin/qml-language-server"
```

Do not substitute a newer release or a different platform asset without
updating and independently verifying the checksum committed here.

Editor configuration must prefer `qml-language-server` for this repository's
QML files. Zed users should install the QML extension for language registration,
copy `.zed/settings.example.json` to `.zed/settings.json`, and configure its
`qml` language server binary to the absolute local path of
`qml-language-server`; Zed requires an absolute `lsp.qml.binary.path`. The
active `.zed/settings.json` file is intentionally local-only because that path
differs by machine. Other LSP-capable editors should run `qml-language-server`
for `*.qml` files and use the repository root, `shell.qml`, or `.git` as the
workspace root marker.

Plain `qmllint` is not considered a complete Quickshell validation pass because
it does not understand every Quickshell-specific module shape. Runtime
validation still requires loading the managed shell with `quickshell --path`
and exercising the relevant IPC targets.

### 5.8 Dependency Mapping

The maintained Arch dependency map covers these capabilities:

| Capability | Arch package examples |
| --- | --- |
| Compiler and make | `gcc`, `make`, `pkgconf-pkg-config` |
| Xlib development | `libX11-devel` |
| Xft and fonts | `libXft-devel`, `fontconfig-devel`, `freetype-devel` |
| Xinerama | `libXinerama-devel` |
| Xrender | `libXrender-devel` |
| Imlib2 | `imlib2-devel` |
| XCB | `libxcb-devel`, `xcb-util-devel` |

These are capability mappings, not immutable package lists. Availability must
be validated against the supported Arch release.

Runtime dependencies are classified as:

- Core: an X11 server/session, D-Bus session support, one usable terminal
  emulator, and the tools required by configured core keybindings. Alacritty
  is the preferred emulator, with the existing supported-terminal fallback
  chain retained when Alacritty is unavailable.
- Recommended desktop: Alacritty, Quickshell, Picom, Feh, Dex, a polkit agent,
  notification tools, audio controls, screenshot tooling, Nerd/emoji fonts,
  Flatpak with its GTK portal, and Gear Lever from a user-scoped Flathub
  remote.
- Optional: the Herdr terminal workspace, file manager, network tray, theme
  utilities, display-manager greeter customization, wallpapers, and
  hardware-specific helpers.

### 5.9 System Health Dashboard

The Control Center must open System Health as a separate full-screen
Quickshell window on the selected X11 monitor. The dashboard must remain
on-demand: opening or explicitly refreshing it starts a bounded snapshot, and
closing it stops active diagnostics. It must not add idle polling.

The snapshot must provide an overall state and categorized details for:

- Current-boot journal and kernel errors, with `journalctl` preferred and
  privileged `dmesg` used as a fallback.
- Failed system and user services, time synchronization, networking, audio,
  and the lyona desktop session.
- Memory, pressure, load, swap, local filesystem capacity, inode use,
  read-only mounts, and available battery, thermal, and drive-health data.
- Required and optional lyona commands, libraries, configuration, and the
  distribution package database.

The dashboard must begin user-readable checks immediately and request a
privileged read-only scan. It must first use non-interactive `sudo` when the
session already has cached or `NOPASSWD` authorization; otherwise it must use
the running polkit agent and trusted installed helper for graphical
authorization. Denied, cancelled, or unavailable authorization must produce a
clearly incomplete report rather than prevent the dashboard from opening.
Journal evidence must be bounded while retaining the total matching count.

Boot-journal and kernel-error rows with matching entries must provide Copy and
Export actions. Copy uses the X11 clipboard through `xclip`. Export writes the
displayed bounded evidence to a private, non-overwriting timestamped file in
the invoking user's home directory, using `boot$DATE.txt` or
`kernel-errors$DATE.txt` naming.

Repairs require an explicit confirmation. User repairs are limited to known
desktop and audio components plus launching the interactive dependency flow.
Failed user and system services are displayed as individual rows with Start,
Stop, Restart, Disable, and Enable actions. A service action is allowed only
while that exact `.service` unit is in the corresponding failed-unit set;
system actions require polkit authorization. Other privileged repairs are
limited to NetworkManager, Bluetooth, and the detected systemd
time-synchronization provider. Filesystem repair, cleanup, reboot, and
unattended package changes are not allowed.
Only a root-owned, non-writable system installation of the health helper may
itself be executed through `sudo` or `pkexec`; repository and XDG copies must
never be elevated. Without an installed helper, the unprivileged copy may use
non-interactive `sudo` to execute only validated root-owned system commands
needed for a bounded scan or confirmed repair.

### 5.10 Desktop Settings Platform

The managed Quickshell layer must grow into one discoverable Settings
application. The application must use a hybrid integration model:

- Common desktop state and controls are presented through consistent
  Quickshell sections.
- Small project helpers may expose stable, machine-readable state and narrowly
  scoped user-session changes.
- Privileged or high-risk administration is performed only through allowlisted,
  installed helpers or delegated to trusted Arch tools.
- Providers and delegated administration tools target Arch Linux. Missing Arch
  capabilities must expose a clean unavailable or unsupported state rather
  than failing the entire application.

The Settings platform must distinguish:

1. Read-only state available without authorization.
2. User-session changes that affect only the invoking user.
3. Privileged system changes requiring explicit confirmation and narrow
   authorization.
4. Delegated operations opened in a trusted platform tool.
5. Unsupported capabilities with an actionable explanation.

QML must not construct arbitrary privileged commands. Elevated helpers must be
root-owned, non-writable by unprivileged users, validate every argument, expose
only documented operations, and remain safe when authorization is denied or
cancelled. Repository and XDG copies must never be elevated.

Settings providers must prefer event-driven updates and stop unnecessary
watches and processes when their section closes. A failure in one provider
must not prevent other sections from opening. Risky changes must provide
preview, confirmation, rollback, or recovery behavior appropriate to their
impact.

The planned Settings surface covers:

- Displays, monitor profiles, and Xft display scaling.
- Keyboard, pointer, touchpad, and other supported input devices.
- NetworkManager connections, VPN entry points, and Bluetooth devices.
- PipeWire/WirePlumber-compatible audio devices and application streams.
- Power profiles, battery, idle, DPMS, suspend, lid, and lock behavior.
- Default applications, MIME handlers, and user-visible autostart entries.
- Themes, wallpaper, fonts, cursors, toolkit integration, notifications, and
  practical X11 accessibility controls.
- Updates, software-source entry points, regional and time settings, user and
  printer entry points, system information, storage overview, diagnostics, and
  recovery guidance.

Advanced partitioning, unrestricted service control, firewall policy editing,
and similarly high-risk administration remain delegated unless a later
specification defines a narrow safe interface.

### 5.11 Arch Image Contract

Released Arch images are built from an archiso profile (`archiso/`) layered
onto the system `releng` profile, via `scripts/build-lyona-arch-iso.sh`.
The live medium embeds this repository, requires UEFI, and auto-logs into a
root shell that automatically launches `lyona-install`
(`archiso/airootfs/root/lyona-install.sh`) — no command to type. It is a
short wizard styled after linutil's `server-setup.sh` (arrow-key
`select_option` menus, a redrawn banner between steps, the CTT logo): keyboard,
disk, user, hostname, timezone, and an NVIDIA opt-in prompt when applicable,
with no desktop-environment or package picker, that generates an
`archinstall` JSON config and runs it fully unattended (`--silent`) — the
base install (disk partitioning, filesystem, systemd-boot, user account) is
not interactively menu-driven. A `/root/.lyona-install-done` sentinel,
written once the base install succeeds, prevents a later tty1 relogin from
relaunching the wizard and re-wiping the disk. Once `archinstall` completes
to the target root, `lyona-install` automatically runs
`archiso/airootfs/root/lyona-postinstall.sh` to finish the lyona
install. The postinstall script also remains runnable standalone against an
already-completed base install (e.g. a manually-run `archinstall`, for BIOS
systems or custom partitioning, which `lyona-install` cannot serve since
systemd-boot requires UEFI). This differs from Anaconda/Kickstart in degree,
not automation: Arch has no first-party unattended installer service, so
this project generates and drives `archinstall`'s own non-interactive config
format itself rather than relying on an upstream automation contract.

The standard image must not include NVIDIA-only packages or kernel arguments.
Installing the proprietary NVIDIA driver is an explicit per-install opt-in
(the `lyona-install` wizard's prompt, or `LYONA_NVIDIA_DRIVER=1` for
the standalone postinstall script) and may install the documented NVIDIA
driver packages, blacklist Nouveau, and configure NVIDIA DRM modesetting.
Any variant may enable the documented third-party
repositories needed by the selected desktop package set; choosing the
dedicated image is the user's consent to that image policy.

Static archiso profile checks (package-map sync, script syntax) are necessary
but not sufficient. A released image must record its build host, archiso
version, architecture, firmware mode, variant, package-resolution result,
completed base install and postinstall run, first boot, and hardware
limitations. As of this writing the archiso path is best-effort and has not
been boot-tested — see `docs/RELEASING.md`.

## 6. Filesystem and Installation Contract

Default system installation locations:

```text
${PREFIX}/bin/dwm
${PREFIX}/share/man/man1/dwm.1
/usr/share/xsessions/dwm.desktop
```

Default user locations:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/lyona/
${XDG_DATA_HOME:-$HOME/.local/share}/lyona/
```

System paths must be overridable for packaging and staged installs. User data
must not be written during a package build using `DESTDIR`.

User-scoped installation runs as the target user. Any default XDG parent
directory created by the Arch image or installer must be owned by that user
and their primary group. Existing XDG parent permissions must be preserved,
and installation must not recursively change ownership outside project-managed
directories.

Uninstall must remove only files owned by this project. It must preserve user
configuration and unrelated application configuration by default.

## 7. User Experience Requirements

- The default session must remain usable when optional visual components fail.
- Common desktop settings must be discoverable from one Settings application;
  unsupported sections must not make the rest of Settings unusable.
- System changes must show pending state, success, failure, and recovery
  guidance rather than relying on silent background commands.
- Error messages must identify the missing command, library, package
  capability, or file and provide the next action.
- The default terminal binding must launch Alacritty directly.
- A plain `dwm-terminal` launch must open the selected emulator directly unless
  the user explicitly enables the optional Herdr layer with `DWM_HERDR=1`.
  Explicit terminal arguments such as `dwm-terminal -e command` must bypass
  Herdr so delegated commands retain their existing execution contract.
- The `dwm-terminal` helper must prefer Alacritty, select another installed
  supported emulator when needed, and provide a clear configuration path.
- Font aliases must accommodate common Meslo Nerd Font naming differences.
- Multi-monitor setup must expose EWMH tags correctly to Quickshell and EWMH
  inspection tools.
- Each Quickshell panel must show only the tags owned by its monitor, using the
  `_DWM_MONITOR_DESKTOPS` root property to match screen geometry with dwm's
  logical monitor order and current tag.
- Defaults should work at 1080p and remain usable at lower and higher
  resolutions.
- Installation output must be readable in both interactive terminals and logs.

## 8. Security and Safety Requirements

- Do not execute remote scripts through a shell as part of the required
  installation path.
- Do not download or execute unverified binaries.
- Third-party executable installers must run as the target user in an isolated
  staging directory. Both the reviewed installer and resulting binary must
  match repository-pinned checksums before the binary is installed.
- Do not run user configuration or desktop helpers as root.
- Quote paths and arguments that may contain whitespace.
- Prevent command injection through distribution metadata, configuration
  values, filenames, and environment variables.
- Avoid broad recursive ownership or permission changes outside project-owned
  directories.
- Preserve existing user files or create explicit backups before replacement.
- Keep the Quickshell Settings frontend unprivileged.
- Require explicit confirmation for privileged or destructive settings.
- Use polkit or an equivalently narrow authorization mechanism rather than
  broad passwordless sudo access for desktop settings.
- Continue showing readable state when authorization is denied, cancelled, or
  unavailable.

## 9. Validation and Acceptance Criteria

A release is Arch-ready only when all of the following pass. A Arch Linux desktop
image additionally requires the image checks below.

Automated validation must run through `scripts/run-tests`, which creates a
unique workspace under `${DWM_TEST_TMP_ROOT:-$HOME/tmp}` and removes that exact
workspace on success, failure, or interruption.

### 9.1 Static Validation

- Clean C build with warnings enabled.
- Shell syntax checks for every changed shell script.
- ShellCheck and shfmt checks, with documented justified exceptions.
- No generated build artifacts unintentionally included in the change.

### 9.2 Arch Validation

On the supported Arch release:

- Distribution detection accepts Arch Linux and rejects non-Arch systems before
  mutation.
- Required package mapping resolves to installable packages.
- A clean checkout builds successfully.
- `make install DESTDIR=<staging-dir>` installs the expected system files
  without writing to the test user's home.
- The real installer preserves pre-existing user configuration.
- Dependency checks report both missing and satisfied capabilities correctly.

### 9.3 Runtime Validation

In a real or nested X11 session:

- dwm starts and can launch a terminal.
- The default terminal binding opens Alacritty directly even when Herdr is
  installed. With `DWM_HERDR=1`, a plain `dwm-terminal` command opens Herdr
  inside Alacritty; explicit `dwm-terminal -e` commands still bypass Herdr.
- Tiling, floating, tags, focus, and close-window actions work.
- Runtime TOML configuration loads and reloads.
- A display-manager session and `startx` path both launch.
- Missing optional desktop processes do not terminate the session.
- EWMH integration works with Quickshell or an equivalent inspection tool.
- Each active monitor has one managed Quickshell panel.
- With the launcher closed, the managed Quickshell process remains near idle
  in a short CPU sample, and no second Quickshell-based shell provider is
  running in the same session.
- A source-checkout update of a live installation leaves the installed binary,
  commands, managed Quickshell tree, and user data copy at the same revision.
  After any required dwm session restart, the new executable is active and XDG
  autostart tray clients register with the managed Quickshell tray host.
- Multi-monitor behavior is tested where suitable hardware or nested displays
  are available.
- The default screenshot-to-clipboard binding invokes the managed helper, and
  its completed capture is advertised as `image/png` by an `xclip` clipboard
  owner. Active-monitor and saved-region captures produce non-empty JPEG files
  through `maim`.
- Recommended and full installs expose Gear Lever in the application launcher,
  and it opens a visible window in the supported X11 session.

### 9.4 Arch Image Validation

- `archiso/packages.x86_64` stays in sync with the `arch:required`+
  `arch:desktop` package map, and the postinstall script and ISO builder pass
  their structural checks (`make check-archiso`).
- The ISO builder embeds the checkout and postinstall script without dropping
  the upstream `releng` boot behavior.
- The build host's `archiso` package version and the resulting image checksum
  are recorded.
- At least the standard image completes a base Arch install and the
  postinstall script in a VM, reboots, reaches LightDM and a usable dwm
  session, and starts the managed Quickshell shell.
- NVIDIA image behavior is not described as hardware-verified unless tested on
  representative NVIDIA hardware.
- The validation record states firmware mode, architecture, image variant,
  Arch release, and any untested paths.

## 10. Current Gap

The existing desktop provides dwm, a managed Quickshell panel and launcher,
notifications, quick controls, power actions, network and Bluetooth surfaces,
display helpers, a system-health dashboard, and the unified Settings platform.
Settings includes the completed Phase 2 display and input mutation surface,
Phase 3 NetworkManager, BlueZ, PipeWire, and media workflows, and Phase 4 power,
session-action, default-application, MIME, and XDG autostart workflows. The
remaining Settings mutation surface in Section 5.10 begins with Phase 5 themes,
wallpaper, fonts, cursors, toolkit integration, notifications, and practical X11
accessibility controls, sequenced in `ROADMAP.md` and defined in `TASKS.md`.

The installer contains an Arch Linux-only package map and rejects other
systems. The build uses `pkg-config`, supports staged installation with
`DESTDIR`, and avoids writing user configuration during package builds. The
archiso-based image (see `docs/RELEASING.md`) is the current documented image
base, while real image and hardware validation must continue to be recorded
per release.

Arch Linux is the only supported and tested distribution.

## 11. Definition of Done

A roadmap feature is complete when:

- Its behavior meets the active roadmap phase and task acceptance criteria.
- Arch Linux behavior is implemented and runtime validated, or the change is
  explicitly scoped as preparatory work.
- Installation attempts without `ID=arch` fail clearly before making
  changes.
- Relevant automated and manual validation is recorded.
- On a development machine running lyona, the checkout has been
  synchronized to the local live installation with
  `scripts/dev-sync-install.sh`, including the post-relogin check when one is
  required.
- User-facing installation and troubleshooting documentation is updated.
- No existing user configuration is overwritten.
- Known limitations and untested platforms are stated precisely.
