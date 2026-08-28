# Arch Installation

> **lyona is Arch Linux-only.** Arch Linux with Xorg is required for
> every supported installation, package, test, and release path.

## Install

### 1. Dependencies

The supported dependency path is the installer because it resolves Arch
package names from the shared map:

```bash
./install.sh --dry-run --non-interactive --profile core
./install.sh --profile full
```

Use `core` for the required build/X11/session packages and Alacritty,
`recommended` for the complete desktop layer, or `full` for optional extras
such as file-manager integration, keyring login integration, wallpapers, and
display-manager setup. On x86_64 Arch, `full` can also install Steam,
Gamescope, GameMode, and MangoHud after repository approval.
The installer separately asks before enabling the `multilib` repository for
Steam, Gamescope, GameMode, and MangoHud. Declining skips the gaming subset
without affecting other full-profile extras.

### 2. Clone and Build

```bash
git clone https://github.com/technicks89/dwm-titus.git lyona
cd lyona
cp config.def.h config.h
./scripts/dev-sync-install.sh
```

For later source-checkout updates, run the same command so the binary,
installed helpers, managed Quickshell configuration, and data copy stay at one
revision. Run `./scripts/dev-sync-install.sh --check` after any requested
session restart to verify the active runtime.

### Automated Installer

```bash
./install.sh
```

The script requires `ID=arch` before handling dependency installation, font
copying, display-manager integration, or config placement. Every other
operating-system identity is rejected before changes are made.
Existing user configuration and `.xinitrc` files are preserved. Upgrades remove
the known legacy `dwm-graphical-session.service` and
`wm-graphical-session.service` early-start configuration so XDG applications
start only after the X11 display environment is available; customized user
units are disabled from early startup but otherwise preserved.

System files are installed with `sudo`, while configuration and data under the
user's XDG directories are installed as that user.

Every profile and Arch image defaults to Alacritty without Herdr. With the
explicit `--install-herdr` option, the repository downloads the official
`https://herdr.dev/install.sh` into an isolated staging directory and verifies
repository-pinned SHA-256 checksums for both that installer and its resulting
Herdr binary before copying it into `~/.local/bin`. A checksum mismatch or
network failure leaves Alacritty usable and reports the Herdr failure. When the
`codex` or `claude` command is already available, the helper also runs Herdr's
matching `integration install` command so native Codex and Claude Code sessions
can be restored. Integration failures are reported separately from binary
installation failures.

When matching vendor XDG entries exist for Picom, the polkit agent, or Light
Locker, the installer copies each entry to the user autostart directory and
adds only the dwm session exclusion. Original commands and vendor session
guards remain intact, no entry is created when the vendor entry is absent, and
existing user entries are preserved.

Installer package profiles are selected with `DWM_INSTALL_PROFILE`:

- `core`: required build packages, X11/session runtime, and Alacritty. Herdr is
  skipped unless `--install-herdr` is provided.
- `recommended`: `core` plus the recommended desktop layer such as Quickshell,
  Picom, Feh, Dex, fonts, theming, screenshot, audio, Bluetooth control and
  tray tools, brightness tools, Flatpak, and the GTK desktop portal. It also
  adds Flathub for the target user, installs Gear Lever as the default AppImage
  manager, and installs the available Arch GTK theme packages. A matching GTK
  theme is generated for every palette in `config/themes.toml`, so GTK
  applications follow the active theme without a downloaded theme pack.
  It also installs the [mybash](https://github.com/technicks89/mybash) shell
  configuration: a Starship prompt, Fastfetch, `fzf` and `zoxide`, cloned into
  `~/.local/share/mybash` and linked from `~/.bashrc`,
  `~/.config/starship.toml`, `~/.config/fastfetch/config.jsonc`, and
  `~/.local/bin/starship-theme`. An existing `~/.bashrc` is kept as
  `~/.bashrc.bak`. The clone is replaced on every run, so edit the files it
  links to rather than the clone itself.
- `full`: `recommended` plus optional extras such as Thunar with SMB-share
  browsing, network tray utilities, keyring login integration,
  wallpapers, and display-manager setup. x86_64 Arch full installs also
  include Steam, Gamescope, and 64-bit and 32-bit GameMode and MangoHud support
  after separate repository approval.
  The installer enables the `multilib` repository for Steam, Gamescope,
  GameMode, and MangoHud, then adds the invoking user to the `gamemode`
  group; log out and back in before using its privileged tuning helpers.

The default is `full` to preserve the historical automated installer behavior.
If `maim` is unavailable in the enabled Arch repositories, the installer
skips that add-on instead of failing the desktop install and reports that the
screenshot hotkeys are unavailable.

For a minimal install:

```bash
DWM_INSTALL_PROFILE=core ./install.sh
```

The same profile can be selected with a flag:

```bash
./install.sh --profile core
```

Interactive runs print the resolved package plan before prompting. For CI,
packaging checks, or scripted validation, use the non-interactive flags:

```bash
./install.sh --dry-run --non-interactive --profile core
./install.sh --non-interactive --yes --profile recommended
./install.sh --non-interactive --yes --profile full --enable-arch-gaming-repos
./install.sh --non-interactive --yes --profile full --cachyos-kernel
```

Without `--enable-arch-gaming-repos`, unattended Arch full installs skip
Steam, Gamescope, GameMode, and MangoHud rather than changing repository trust.
An already-enabled `multilib` counts as approval, since nothing in
`pacman.conf` has to change -- this is what installs from the lyona ISO get,
because the ISO ships `multilib` enabled.

### CachyOS repositories and kernel

Installs from the lyona ISO get this automatically and are not asked about
it. The repositories are added to the live medium *before* `archinstall` runs,
so `pacstrap` fetches the optimized packages directly instead of installing
Arch builds and replacing them afterwards -- the base system is downloaded
once, not twice. The installed system inherits the live medium's `pacman.conf`
along with the CachyOS mirrorlists and keyring, and the postinstall step then
installs `linux-cachyos` and `linux-cachyos-lts`. The stock Arch kernel
remains installed and remains the default boot entry -- the CachyOS kernels
are added to the boot menu for you to select. If the CachyOS mirror cannot be
reached, the install continues on the stock Arch repositories instead of
failing.

On an existing system, the installer can do the same, but both steps are
opt-in and are never enabled by default:

```bash
./install.sh --profile full --enable-cachyos-repos
./install.sh --profile full --cachyos-kernel
```

`--cachyos-kernel` implies `--enable-cachyos-repos`. Interactive runs ask for
both separately; `DWM_INSTALL_CACHYOS_REPOS=true` and
`DWM_INSTALL_CACHYOS_KERNEL=true` are the environment equivalents.

Adding the repositories imports and locally signs the CachyOS signing key,
installs the CachyOS keyring and mirrorlists, replaces `pacman` with the
CachyOS build that understands the ISA-specific mirrorlists, adds the
repository set matching this CPU (`znver4`, `x86-64-v4`, `x86-64-v3`, or the
plain `cachyos` repository) above `[core]`, and upgrades the system to the
optimized packages. `pacman.conf` is backed up first and restored if any step
fails.

The kernel step installs `linux-cachyos` and makes it bootable: GRUB configurations are regenerated, and systemd-boot installs
get a copy of the existing loader entry pointing at the new kernel image. Any
other bootloader is reported so the entry can be added by hand. The existing
kernel is left installed and bootable.

Kernel headers are only needed to build out-of-tree modules, so they are not
installed by default. Pass `--with-headers` to `lyona-cachyos install-kernel`
to include them; they are also included automatically when DKMS is already
present, which is what the NVIDIA driver path relies on.

The same steps are available on their own afterwards:

```bash
lyona-cachyos status
lyona-cachyos add-repos              # --no-upgrade to skip the system upgrade
lyona-cachyos install-kernel         # --with-headers to include kernel headers
```

Herdr is skipped for every profile unless `--install-herdr` or
`DWM_INSTALL_HERDR=true` is provided. Its published Linux binaries support
x86_64 and aarch64. Installation alone does not change the terminal default;
set `DWM_HERDR=1` and run `dwm-terminal` to enter the optional workspace.
Herdr can also be installed or repaired separately:

```bash
install-herdr
install-herdr --force
```

Upgrades preserve an existing `hotkeys.toml`. If an earlier installer seeded
its `terminal` variable to `dwm-terminal`, set it to `alacritty` to adopt the
current direct-terminal default. The installer does not overwrite that
user-owned choice.

An AUR helper (`yay`) is installed automatically for you as a standing
convenience tool, independent of the package profiles above — none of the
required, recommended, or optional packages need it, since everything the
installer selects is available directly through official `pacman` repos
(`core`/`extra`/`multilib`).

### GRUB boot menu theme

The installer ships the `CyberRe` GRUB theme and selects it by default on
machines that boot with GRUB, so the boot menu matches the rest of the
desktop instead of the stock text list.

Installing the theme files (`make install-system`) changes nothing about
booting — they are just data under `/usr/share/grub/themes/CyberRe`.
Selecting the theme is a separate step, because it edits the bootloader:

- `/etc/default/grub` is copied to
  `/etc/default/grub.lyona-backup-<timestamp>` before the first edit.
- `GRUB_THEME` is pointed at the installed theme.
- `GRUB_TERMINAL_OUTPUT` is commented out if present. GRUB draws themes only
  on `gfxterm`, so a `console` setting would leave the theme installed and
  invisible.
- `GRUB_GFXMODE` is set to `auto` if it is not already set, since the
  640x480 fallback letterboxes the theme's 1920x1080 background.
- `grub-mkconfig` regenerates `/boot/grub/grub.cfg`.

Every one of those is printed as it happens. Replaced lines are commented out
rather than deleted, so the previous values stay readable in the file next to
the backup.

Machines that do not boot with GRUB — including the lyona ISO's own installs,
which use systemd-boot — are reported and left completely alone. A theme step
that fails does not fail the install.

Skip the bootloader edit with `--skip-grub-theme` (or
`DWM_INSTALL_GRUB_THEME=false`); the theme files are still installed, so it
can be selected later.

Manage it afterwards with:

```bash
lyona-grub-theme status    # detected bootloader and selected theme
lyona-grub-theme list      # installed themes
lyona-grub-theme apply     # select CyberRe (or apply <name>)
lyona-grub-theme remove    # back to the default GRUB appearance
```

The theme is vendored from
[ChrisTitusTech/bootloader-themes](https://github.com/ChrisTitusTech/bootloader-themes)
(MIT) so it is available during an offline install.

## Starting dwm

**Display manager** (SDDM, GDM, LightDM): log out and select **dwm** from the session list.

When the interactive installer runs inside an active X11 session, it offers
the `dwm-display-setup` wizard after installation. The wizard previews the
chosen resolution and multi-monitor layout, then installs a backed-up Xorg
fragment. Installations run from a TTY or in non-interactive mode defer this
step; after the first X11 login, run:

```bash
dwm-display-setup
```

The installed Settings display provider is machine-oriented. Its actions are:

```text
dwm-settings-display discover
dwm-settings-display watch
dwm-settings-display save NAME SPEC...
dwm-settings-display preview TOKEN SECONDS SPEC...
dwm-settings-display preview-profile TOKEN SECONDS NAME
dwm-settings-display keep TOKEN [NAME]
dwm-settings-display revert TOKEN
dwm-settings-display preview-status [TOKEN]
dwm-settings-display install-profile NAME
dwm-settings-display rollback-system
```

Discovery and live previews require `xrandr`, and the hotplug watch requires
`udevadm`. Persistent install and rollback additionally require `pkexec` plus
the root-owned helper installed at `${PREFIX}/libexec/lyona/`. Profiles are
stored under
`${XDG_CONFIG_HOME:-$HOME/.config}/lyona/display-profiles/`. No move is
needed for profiles created by `dwm-display-profile`, which uses the same
directory. If `DWM_DISPLAY_PROFILE_DIR` previously pointed elsewhere, either
keep that environment override or move those `.conf` files into the default
directory before using Settings.

The input provider exposes the corresponding session actions:

```text
dwm-settings-input discover
dwm-settings-input watch
dwm-settings-input watch-apply
dwm-settings-input apply-saved
dwm-settings-input preview TOKEN SECONDS DEVICE SETTING VALUE
dwm-settings-input keep TOKEN
dwm-settings-input revert TOKEN
dwm-settings-input preview-status [TOKEN]
dwm-settings-input reset DEVICE SETTING
```

All input actions require `xinput`; keyboard layout and modifier operations
also require `setxkbmap`; stable hardware identity and hotplug watching use
`udevadm`, and the session watcher uses `flock` from `util-linux` to prevent
duplicate replay workers. Kept values default to
`${XDG_CONFIG_HOME:-$HOME/.config}/lyona/input-settings.conf`. Set
`DWM_INPUT_SETTINGS_FILE` to use a different file. The normal session startup
invokes `apply-saved` idempotently and runs `watch-apply` to debounce input
hotplug events before replaying saved values for returning devices.

**startx:**
```bash
startx
```

The provided `.xinitrc` disables screen blanking, starts the configured Quickshell panel, and runs dwm.

## Minimal Session Profile

The minimal supported profile is useful for lean Arch systems, recovery
sessions, and minimal Arch qualification. It keeps only:

- an X11 server and either a display-manager session or `startx`
- D-Bus session support
- `dwm`
- Alacritty as the default terminal, with `dwm-terminal` available to delegated
  tools that require fallback selection
- required X11 helpers used by core startup and display commands, such as
  `xrandr`, `xset`, and `xsetroot`

Quickshell, Picom, Feh, Dex, a polkit agent, screenshot tools, wallpapers, tray
utilities, and audio or brightness helpers are optional in this profile.
Missing optional components should appear as degraded features in
`dwm-diagnostics`, not as session-fatal failures.

For `startx`, a minimal `.xinitrc` can be:

```sh
#!/bin/sh
xset s off
xset -dpms
xsetroot -cursor_name left_ptr
exec dbus-run-session dwm
```

If the login path already creates a user D-Bus session, use `exec dwm`
instead of wrapping it with `dbus-run-session`.

After installation, verify the profile with:

```bash
dwm-diagnostics
dwm-terminal --print-command
```

`dwm-diagnostics` must report zero required failures before treating the
minimal profile as ready. Optional degraded features can remain unresolved.
The default binding opens Alacritty directly. A plain `dwm-terminal` also opens
the selected emulator directly unless `DWM_HERDR=1` explicitly enables Herdr.
Commands such as `dwm-terminal -e sh -c 'command'` always bypass Herdr.
