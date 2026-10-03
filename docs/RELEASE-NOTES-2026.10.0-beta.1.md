# lyona 2026.10.0-beta.1

Second beta of the Arch Linux line. This is a **pre-release**: the ISO
workflow publishes every release with `--prerelease`, and a beta is never
promoted to Latest.

It collects everything since `2026.08.0-beta.1`: Sync Phases 6 to 9 and Sync
Sprints 1 to 15 (`docs/UPSTREAM-SYNC.md`). The headline items are below.
`CHANGELOG.md` has the complete list.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-2026.10.0-beta.1.tar.gz` |
| Installer image | `lyona-2026.10.0-beta.1-x86_64.iso` |
| Checksums | `lyona-2026.10.0-beta.1-SHA256SUMS` |

- **The source archive** is now a reproducible archive of the repository,
  which `lyona-update` builds and installs (Sync Sprint 12 S12-19). The
  previous beta's asset was a runtime bundle that no release update could
  build.
- **The installer image** carries `iso_label=LYONA_2026_10_0_BETA1`. The
  filename and `/etc/lyona-iso-release` keep the full version. Quote that file
  when reporting a problem with an image.
- **The SHA-256 sums** are written at publish time by `scripts/lyona-release`,
  from the artifacts it uploads. Do not copy them from a local build.

## What is in this beta

### Updates

- **`lyona-update`** checks for, applies and rolls back releases.
  - **Verification:** it checks each download's SHA-256, builds without
    privileges, installs through one confirmed privileged step, and records
    install provenance.
  - **Settings and the Control Center** show and run it, and a progress
    window survives the shell restarting.
  - **Your build options:** your `config.h` is used for updates (decision
    D-18).
- **An updates-available icon in the panel** counts pending system packages
  and Flatpak apps, plus a new lyona release. A click opens Settings > System.
  - **Packages** are counted with `checkupdates`, which never takes pacman's
    lock.
  - **When it checks:** a few minutes after login, every 6 hours by default,
    and on reconnecting.
- **Settings > System can update in your terminal:**
  - **packages:** `yay -Syu` when yay is installed (so AUR-built packages
    update too), otherwise `sudo pacman -Syu`;
  - **Flatpak apps:** the system and user installations, each on its own;
  - **confirmation:** you see each tool's plan and confirm it yourself.
- **Topgrade:** `recommended` and `full` installs build the newest release
  from crates.io with cargo, from rustup, or a Rust toolchain you already
  have.

### System management in Settings

- **Time and region:** timezone, locale and network time can be changed,
  each with a preview and a confirmation, through a crash-safe operation
  journal.
- **Information and health:**
  - an information card covering the system, hardware, storage, mounts,
    security status (firewalld, ufw and nftables) and root encryption;
  - System Health navigation;
  - a missing GNOME Keyring is flagged.
- **Delegated administration:** confirmed hand-offs to the right tool, such
  as printers.

### Displays, appearance and accessibility

- **Displays:**
  - relative monitor placement with a numbered preview;
  - Docked and Undocked automatic layouts, hidden when there is no battery;
  - DPMS and the screen lock are now on by default (see Upgrading).
- **Appearance:**
  - Picom controls in Settings, including a corner-radius slider;
  - icon themes;
  - a theme switch reaches already-running GTK 3 apps;
  - Qt palettes for `qt5ct` and `qt6ct`, and a GTK 2 theme.
- **Accessibility:**
  - text scaling;
  - high contrast and reduced motion;
  - readable text on hover in every theme;
  - XKB sticky, slow, bounce and mouse keys, from an in-tree helper rather
    than the AUR-only `xkbset`;
  - a managed notification policy with Do Not Disturb.

### The shell

- **A cross-tag window overview:** one card per window, grouped by tag. It
  works by keyboard and mouse, with type-to-filter, close-from-card and
  multi-monitor labels.
- **Calendar and weather widgets:** weather is off until you turn it on and
  set a location (Open-Meteo, no key).
- **Panel and Control Center:**
  - a layout switcher in the Control Center;
  - a smaller Control Center;
  - square popups;
  - clicking the empty bar closes open popups.
- **Text from other programs** (window titles, notifications, network
  names) is always shown as plain text, never as markup.
- **Less idle work:** the always-on watchers stopped polling, and none of
  them is left running after the shell exits.

### Installer and image

- **One image for every GPU.** The installer detects an NVIDIA card and
  recommends the right proprietary driver:
  - `nvidia-open` on Turing and newer;
  - the legacy 580xx (Maxwell to Volta) or 470xx (Kepler) driver, from the
    CachyOS repository or a pinned AUR PKGBUILD (Sync Sprint 14);
  - nouveau stays the alternative, and older cards keep it.
- **The login keyring:** a `recommended` install includes GNOME Keyring, so a
  display-manager login unlocks it.
- **Defaults on a fresh install:**
  - media and image defaults (Celluloid, mpv, sxiv);
  - a themed GRUB menu;
  - the mybash shell configuration.

### Security and hardening

- **The privileged update helper:**
  - it no longer builds or installs anything from the user's home as root;
  - it builds and installs one root-owned, re-verified copy of the release.
- **Pinned and verified downloads:**
  - the CachyOS signing key is checked against a pinned fingerprint;
  - the `yay-bin` bootstrap is pinned to a reviewed commit;
  - the mybash Starship fallback no longer pipes a remote script.
- **Build hardening:** dwm is built with `-D_FORTIFY_SOURCE=2`.
- **Narrower interfaces:**
  - smaller IPC targets;
  - stricter input checks in several helpers.

### Policy

- **The AUR is now limited to where it is needed** (decision D-27), not
  forbidden.
- **The listed uses:**
  - the `yay` helper;
  - the legacy NVIDIA drivers;
  - the `yay -Syu` that Settings runs for you.
- **The guard:** each use is in `docs/AUR-PACKAGES.md`, and
  `make check-aur-policy` fails on any other.

## Installing from the image

1. Write `lyona-2026.10.0-beta.1-x86_64.iso` to a USB stick and boot it.
2. Run `lyona-install`. It asks for:
   - the keyboard layout;
   - the disk, and the filesystem (optionally encrypted with LUKS);
   - the user, and the hostname;
   - the NVIDIA driver, when a card is detected.

   It then runs an unattended `archinstall`, followed by the lyona postinstall.
   - **Manual fallback** (BIOS, or custom partitioning): run `archinstall`
     yourself, then `/root/lyona-postinstall.sh`.
3. The postinstall runs `install.sh --profile full` as the new user. It then
   builds Topgrade, once the install's temporary passwordless `sudo` is gone,
   and reboots into the installed system.

## Upgrading from 2026.08.0-beta.1

- **How to update:** from a checkout, `git pull` and then `./install.sh`. The
  previous beta's own `lyona-update` has not been tested against this
  release, so do not rely on it for this one update.
- **Screens blank and lock when idle by default now** (decision D-13). A
  choice already saved in `~/.config/lyona/power.conf` is kept.
- **GNOME Keyring:** if a `recommended` install lacks it, run
  `sudo pacman -S --needed gnome-keyring`, then log out and back in.
- **Topgrade:** run `sudo pacman -S --needed rustup` (skip this if another Rust
  toolchain is installed), then `install-topgrade`.
- **Floating the update terminal:** an existing `window-rules.toml` is not
  changed. Add `{ class="lyona-update-float", isfloating=1 },` to float the
  terminal Settings opens.

## Qualification status

**The installer image has not been boot-tested on real hardware or in a VM.**
Before treating it as qualified, boot it in a KVM virtual machine, complete the
install above, and confirm LightDM, dwm and the managed Quickshell shell come
up. Record:
- the ISO checksum;
- the firmware mode and architecture;
- the package-resolution result;
- the first-boot result.

Verified on the build host (Arch, CachyOS repositories) before this release:
- **The full suite** (`scripts/run-tests`) passed at this release's version.
  That covers:
  - every unit and contract test;
  - the Xvfb runtime tests of the shell, dwm and Settings;
  - `make release-check` (a reproducible source archive that builds);
  - `make check-archiso` (the image profile and version stamping);
  - `make check-aur-policy`.
- **Read-only checks against the real system:**
  - `checkupdates` counted the pending packages;
  - the NetworkManager signal subscription;
  - the keyring diagnostic;
  - LightDM's PAM configuration.
- **A real Topgrade build:** from crates.io, in an isolated home.

## Known limitations

- **Live-session checks not yet run** (Sync Sprint 15 S15-05,
  `docs/evidence/s15-05-updates-and-keyring.md`):
  - a keyring unlock at a real LightDM login;
  - a real reconnect triggering an update check;
  - real `yay -Syu`, `pacman -Syu` and Flatpak runs in the terminal, tiled
    and floating;
  - an install from the image that builds Topgrade.
- **The legacy NVIDIA path is untested on real hardware** (Sync Sprint 14
  S14-04, `docs/evidence/s14-04-legacy-nvidia.md`). It has been exercised only
  against a stub chroot.
- **Flatpak update discovery** assumes `flatpak remote-ls --updates` prints
  one row per update and no header when not attached to a terminal. It has
  not been run against a real Flatpak.
- **Sign-off checks from earlier sprints** that need real hardware or a live
  session are still open; `docs/SYNC-SPRINT-10-COMPLETION-AUDIT.md` lists
  them.
- **Signing:** releases are not signed (decision D-14). A matching SHA-256
  proves the download is intact, not that it is genuine.

## Reporting problems

- **An image:** include `/etc/lyona-iso-release` from the medium.
- **An installed session:** include the output of `dwm-diagnostics`.
- **An update:** include `~/.local/state/lyona/update.log`.
