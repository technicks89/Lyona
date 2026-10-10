<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./assets/logo/lyona-logo-horizontal-dark.png" />
    <img src="./assets/logo/lyona-logo-horizontal-light.png" alt="lyona logo" width="320" />
  </picture>
  <p><strong>An Arch Linux X11 desktop built for keyboard-driven work</strong></p>
  <p>
    <a href="https://dwm.technicks89.com">Documentation</a> |
    <a href="https://github.com/technicks89/Lyona/releases">Releases</a> |
    <a href="./CHANGELOG.md">Changelog</a> |
    <a href="./CONTRIBUTING.md">Contributing</a>
  </p>
</div>

![The Lyona desktop with its Quickshell panel](assets/screenshots/lyona-qs-4x.webp)

This is a fork of [dwm-titus](https://github.com/ChrisTitusTech/dwm-titus). It is designed to run on Arch Linux rather than Fedora. 
Lyona is not a 1-for-1 of dwm-titus
Claude is used to help storyboard, build sprints, fix code where needed, and build documentation.
CodeRabbit is also used to check code

Lyona is a complete, lightweight X11 desktop with sensible defaults,
guided installation, and powerful customization. It is designed for people who
want a responsive keyboard-first workflow without having to assemble every
part themselves.

**Lyona is an Arch Linux-only desktop.** Arch Linux is the sole
supported platform for installation, runtime behavior, package resolution,
testing, and release qualification. Use either the Arch installer image or
the existing-system installer on Arch Linux.

## What You Get

| Experience | What it includes |
| --- | --- |
| **A focused desktop** | Automatic window tiling, nine workspaces, fast keyboard navigation, a window overview with live previews of every window (while Picom, the compositor, runs), multi-monitor support, and flexible fullscreen modes. |
| **Everyday essentials** | A polished panel, application launcher, system tray, Control Center, Settings, notifications, screenshots, audio, brightness, and power controls. |
| **Easy discovery** | An interactive keybind viewer, guided display setup, built-in diagnostics, and clear unsupported-feature reporting. |
| **Personal configuration** | Live-reloading hotkeys, themes, and window rules, with local configuration preserved across upgrades. |
| **Panel customization** | Show or hide individual panel widgets (workspace, volume, Bluetooth, network, power) from Settings, with the choice persisted across every monitor and a fresh session. |
| **Two installation paths** | A ready-to-install Arch image or an installer for an existing Arch system. |

> Lyona is an X11 desktop. A Wayland-native session is not currently part
> of the project scope.

## Recent Changes

The newest release's notes summarize what changed and what is still being
qualified: [2026.10.0-beta.6](./docs/RELEASE-NOTES-2026.10.0-beta.6.md).
[CHANGELOG.md](./CHANGELOG.md) has the complete list.

## Install

Choose the path that matches your system:

| Installation | Best for | What it does |
| --- | --- | --- |
| [Arch ISO](#arch-iso) | A fresh, dedicated installation | Boots a live Arch image with this checkout preloaded for a guided install. |
| [Existing system](#existing-system) | An Arch installation you already use | Installs dependencies, the desktop session, and the selected feature set while preserving local configuration. |

For complete requirements and installation details, see the
[Installation Guide](https://dwm.technicks89.com/install.html).

### Arch ISO

Pre-release images are published on the
[Releases](https://github.com/technicks89/Lyona/releases) page, each with a
`lyona-VERSION-SHA256SUMS` file. Check the download before writing it; the
file also lists the source archive, which `--ignore-missing` skips when you
downloaded only the image:

```bash
sha256sum -c --ignore-missing lyona-VERSION-SHA256SUMS
```

From `2026.10.0-beta.2` on, releases are also signed; the
[Installation Guide](https://dwm.technicks89.com/install.html) shows how to
check the signature.

To build the installer image yourself from this checkout (requires the
`archiso` package, on an Arch host):

```bash
sudo scripts/build-lyona-arch-iso.sh
```

The image is named for the release it was built from, `VERSION` in
`config.mk`: `out/lyona-VERSION-x86_64.iso`. A booted medium reports its exact
build in `/etc/lyona-iso-release`.

Write the ISO to a USB drive and boot it, with UEFI or a legacy BIOS. The `lyona-install`
wizard launches automatically. It asks, in menus: the keyboard layout, the disk
to erase, btrfs or ext4 with optional LUKS encryption, your user and password,
the hostname, the timezone (detected online only if you agree, then confirmed), and, on an NVIDIA
GPU, which driver. Nothing is written until you confirm the summary. It then
drives `archinstall` unattended and finishes installing Lyona. ISO installs get the `multilib`
and [CachyOS](https://cachyos.org) repositories and the `linux-cachyos`
kernel without being asked; it is the only kernel installed. If the CachyOS
repositories cannot be reached, the stock Arch kernel is installed instead;
should they work again by the end of the install, `linux-cachyos` is added as
the default and the stock kernel stays beside it. See
the
[Installation Guide](https://dwm.technicks89.com/install.html) for details.

### Existing System

```bash
git clone https://github.com/technicks89/Lyona.git
cd Lyona

./install.sh --dry-run --non-interactive --profile recommended
./install.sh --profile recommended
```

The dry run shows the dependency and installation plan before anything changes.
The installer requires Arch Linux, preserves existing personal configuration,
and installs the managed desktop components. It accepts only Arch's
`/etc/os-release` identity and rejects every other operating-system identity
before making changes.

| Profile | Includes |
| --- | --- |
| `core` | The X11 session, required dependencies, and one terminal emulator. |
| `recommended` | The complete everyday desktop, including Alacritty, Quickshell, Firefox, the Thunar file manager, NetworkManager (enabled only when no other network manager is in use), GNOME Keyring, AppImages in the launcher (Gear Lever with `--with-gearlever`), Topgrade (from the AUR's pinned `topgrade-bin`), theming, screenshots, audio, and brightness tools. |
| `full` | The recommended desktop plus wallpaper, display-manager, and supported Arch gaming integrations (Steam, Gamescope, GameMode, MangoHud via `multilib`). |

On x86_64, `--enable-cachyos-repos` adds the [CachyOS](https://cachyos.org)
repositories for this CPU's ISA level, and `--cachyos-kernel` also installs
`linux-cachyos` and adds a boot entry for it. Both are opt-in, ask before
touching `pacman.conf`, and back it up first; see the
[Installation Guide](https://dwm.technicks89.com/install.html) for what they
change.

`maim` is an optional dependency used only by the screenshot hotkeys. If it is
unavailable, installation continues and reports that the screenshot hotkeys
remain disabled; invoking one makes `dwm-screenshot` exit with
`dwm-screenshot: maim is not installed`. `xclip` and `xdotool` remain required
runtime dependencies for the X11 desktop and its other managed helpers.

## First Login

**Super** is the Windows key on most keyboards.

| Action | Keybind |
| --- | --- |
| Open the application launcher | <kbd>Super</kbd> + <kbd>R</kbd> |
| Open Alacritty terminal | <kbd>Super</kbd> + <kbd>X</kbd> |
| Open Control Center | <kbd>Super</kbd> + <kbd>F1</kbd> |
| Show the interactive keybind viewer | <kbd>Super</kbd> + <kbd>/</kbd> |
| Close the focused window | <kbd>Super</kbd> + <kbd>Q</kbd> |
| Switch workspace | <kbd>Super</kbd> + <kbd>1-9</kbd> |
| Open the power menu | <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>Q</kbd> |

With a display manager, select the **lyona** session when logging in. From a TTY,
start the session with:

```bash
startx
```

## Customize Your Desktop

Most personal settings live under:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/lyona/
```

Hotkeys, themes, and window rules reload when their TOML files are saved.
Advanced compile-time preferences live in the user-owned `config.h`, which the
installer and future upgrades preserve.

The installer also provides `dwm-settings-display` and its root-owned
`libexec/lyona/dwm-settings-display-root` persistence helper. Live display
discovery and previews require `xrandr`; hotplug watching requires `udevadm`;
only persistent Xorg install and rollback require `pkexec`. Named profiles live
under the `display-profiles/` directory in the XDG path above.
Run `dwm-display-setup detect`, then `dwm-display-setup`, for a guided wizard
that detects outputs and configures modes, positions, rotation, and the primary
display with a reversible preview. Persistent generation selects compatible
TearFree or NVIDIA Full Composition Pipeline behavior automatically; pass
`--force-full-composition-pipeline off` to disable the NVIDIA default.
The adjacent `dwm-settings-input` provider uses `xinput`, `setxkbmap` for
keyboard settings, and `udevadm` for stable device identity and hotplug events.
Kept values are stored in `input-settings.conf` in the same XDG directory;
`DWM_INPUT_SETTINGS_FILE` can select another file.

Settings also reports accessibility maturity per capability — text scale,
contrast, reduced motion, notification policy, and keyboard/pointer access —
instead of a single all-or-nothing accessibility state, so it's clear which
of these are already usable and which are still read-only reporting on your
system.

See the [Configuration Guide](https://dwm.technicks89.com/configuration.html)
and [Theming Guide](https://dwm.technicks89.com/theming.html) for examples and
safe customization paths.

## Documentation

- [Installation](https://dwm.technicks89.com/install.html)
- [Getting Started](https://dwm.technicks89.com/getting-started.html)
- [Keybindings](https://dwm.technicks89.com/keybinds.html)
- [Configuration](https://dwm.technicks89.com/configuration.html)
- [Theming](https://dwm.technicks89.com/theming.html)
- [Control Center](https://dwm.technicks89.com/control-center.html)
- [Settings](https://dwm.technicks89.com/settings.html)
- [Updating and Rollback](https://dwm.technicks89.com/updating.html)
- [How Lyona Works](https://dwm.technicks89.com/patches.html)
- [Troubleshooting](https://dwm.technicks89.com/troubleshooting.html)

The technical guide explains the project architecture, what dwm is, and how
the maintained enhancements fit together. You do not need to understand or
apply dwm patches to install and use the desktop.

## Troubleshooting

Start with the built-in diagnostic report:

```bash
dwm-diagnostics
```

You can also open **Control Center -> System Health** for a graphical overview.
If the session does not start, run `startx` from a TTY to see its error output.
The [Troubleshooting Guide](https://dwm.technicks89.com/troubleshooting.html)
covers common session, panel, terminal, theme, display, and NVIDIA issues.

### An update broke the session

If a `lyona-update` apply leaves you without a working desktop, log in at a
TTY (<kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F2</kbd> through <kbd>F6</kbd>) and
roll back — this does not need Quickshell, D-Bus, or a running polkit agent:

```bash
lyona-update rollback --list   # see what is available
lyona-update rollback          # restore the newest backup
startx                         # or log in normally afterward
```

See [Updating and Rollback](https://dwm.technicks89.com/updating.html) for
the full walkthrough.

If the problem remains, [open an issue](https://github.com/technicks89/Lyona/issues)
and include the relevant diagnostic output. Review it first and remove any
private system information.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for the
development workflow and validation requirements, and report security issues
using [SECURITY.md](SECURITY.md).

The main repository check uses a managed workspace under `$HOME/tmp` and
removes it when the run finishes:

```bash
scripts/run-tests
```

Project requirements and active work are tracked in [SPEC.md](SPEC.md),
[ROADMAP.md](docs/roadmap/ROADMAP.md), and [TASKS.md](docs/roadmap/TASKS.md).
