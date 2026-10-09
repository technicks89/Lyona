# Arch Installation

> **lyona is Arch Linux-only.** Arch Linux with Xorg is required for
> every supported installation, package, test, and release path.

## Install from the image

For a new, dedicated machine, with UEFI or a legacy BIOS. It installs GRUB,
with the CyberRe boot menu theme.

1. **Download** the newest image, `lyona-VERSION-x86_64.iso`, and its
   `lyona-VERSION-SHA256SUMS` from the
   [Releases](https://github.com/technicks89/Lyona/releases) page. Images are
   pre-releases while lyona is in beta. Check the download, in the folder that
   holds both:

   ```bash
   sha256sum -c lyona-VERSION-SHA256SUMS --ignore-missing
   ```

   The file also lists the source archive; `--ignore-missing` skips it when
   you did not download it.

   Releases from `2026.10.0-beta.2` on are signed. With `cosign`, and the
   release's `lyona-VERSION.sigstore.json` beside the image, check that it was
   built by lyona's own release workflow:

   ```bash
   cosign verify-blob-attestation --bundle lyona-VERSION.sigstore.json \
       --type https://slsa.dev/provenance/v1 \
       --certificate-oidc-issuer https://token.actions.githubusercontent.com \
       --certificate-identity https://github.com/technicks89/Lyona/.github/workflows/build-iso.yml@refs/heads/main \
       lyona-VERSION-x86_64.iso
   ```

   Logged in to the GitHub CLI, `gh attestation verify
   lyona-VERSION-x86_64.iso --repo technicks89/Lyona` checks the same.

   Or build one yourself (see [Releasing](https://github.com/technicks89/Lyona/blob/main/docs/RELEASING.md)).
2. **Write it to a USB stick**, which erases the stick. Replace `/dev/sdX` with
   the stick, as `lsblk` shows it:

   ```bash
   sudo dd if=lyona-VERSION-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

3. **Boot it.** The `lyona-install` wizard starts on its own. It checks the
   network first. With no wired connection and a Wi-Fi card, it offers to
   connect to Wi-Fi. It lists the networks it finds, with signal strength and
   security, plus **Other (hidden network)**, and asks for the passphrase.
   Open and WPA personal networks are supported, but enterprise (802.1X) and
   WEP networks aren't. The new system keeps the connection, so its first boot
   is online. If a Wi-Fi chip has no driver on the image (some Broadcom chips
   in older Macs need `broadcom-wl`), the wizard says so; install over a cable
   or USB tethering instead. Then it asks:
   - the keyboard layout, from a list you can type in to search (for example
     "German" or `fr`). It applies at once, so the passwords you type next use
     it, as they will at the disk-encryption prompt and the login screen;
   - the disk to install to, which it erases;
   - the filesystem: btrfs (the default) or ext4, either optionally encrypted
     with LUKS, which then asks for the encryption password;
   - your user name and password, and the hostname. Your user administers the
     machine with `sudo`; root has no password and cannot log in. A system
     that will not boot is repaired from the live medium (`arch-chroot`), as
     systemd's emergency shell needs root's password;
   - the timezone, detected from your connection for you to confirm or change;
   - the package mirrors: those in your timezone's country, or worldwide for a
     zone with no country such as `UTC`. Choose another country, or worldwide,
     when you are installing somewhere else. The fastest of them, measured from
     your machine, are ranked before anything is downloaded, and the new system
     keeps the list. When too few mirrors are in the country, worldwide ones are
     added; when they cannot be ranked (no network, or it takes more than 30
     seconds), the medium's own list is used;
   - on an NVIDIA GPU, the driver: the proprietary driver, recommended when it
     supports the card (a legacy branch for an older card), or the open-source
     nouveau.

   In the timezone and country lists, Esc goes back to the question before
   them (with no detected timezone, it asks whether to choose one or cancel). It shows a summary, mirrors included, where **Change an answer...**
   asks any one question again (a new keyboard layout asks for the passwords
   again too), and nothing is written until you choose **Wipe DISK and
   install**. Cancelling at any point changes nothing; run `lyona-install` to
   start again.
4. **It installs on its own:** Arch with `archinstall`, then lyona's full
   profile as your user, the CachyOS repositories and the `linux-cachyos`
   kernel (normally the only kernel; see "CachyOS repositories and kernel"
   below), and Topgrade. A progress bar shows
   each step. If something did not go as chosen (a driver that could not be
   installed, for example), the last screen lists it and waits for Enter;
   otherwise it reboots after 15 seconds. Leave the USB stick in until then; if
   the installer starts again instead of lyona, remove it and restart.
   The full log is `/var/log/lyona-postinstall.log` on the new system. It
   gives each step's start and duration, and ends with a table of where the
   install's time went, archinstall included.

If a step fails, a menu offers to retry it, show the log, or drop to a shell,
and says what state the machine is in. If `archinstall` fails, **Retry** runs
it again with your answers; the disk may already be erased by then.

**Without the wizard** (partitioning of your own): run `archinstall`
yourself from the live medium, then `/root/lyona-postinstall.sh` to install
lyona onto it.

## Install on an existing Arch system

### 1. Clone

Everything below runs from the checkout:

```bash
git clone https://github.com/technicks89/Lyona.git lyona
cd lyona
```

### 2. Run the installer

The installer installs the packages, builds dwm, installs it and sets up your
account, all from the checkout. See its plan first, then install:

```bash
./install.sh --dry-run
./install.sh
```

It installs the `full` profile unless you choose another with `--profile`:
`core` for the required build/X11/session packages and Alacritty,
`recommended` for the complete desktop layer, or `full` for optional extras
such as wallpapers and display-manager setup. On x86_64 Arch, `full` can also
install Steam, Gamescope, GameMode, and MangoHud after repository approval.
See [Dependencies and Package Profiles](./dependencies.md) for exactly which
packages each profile installs.
The installer separately asks before enabling the `multilib` repository for
Steam, Gamescope, GameMode, and MangoHud. Declining skips the gaming subset
without affecting other full-profile extras.

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

**Time synchronization** is on by default, in every profile. When no
other time service keeps the clock, the installer enables and starts
`systemd-timesyncd`, which comes with `systemd`, so nothing is downloaded for
it; the summary says so first. If `chronyd`, `ntpd` or `openntpd` is enabled or
running, it is kept and `systemd-timesyncd` is not enabled beside it, and a
masked `systemd-timesyncd` is left masked. Running the installer again changes
nothing. An image install has it from `archinstall` already. Once lyona has
seen it on, it records that in `/var/lib/lyona/time-sync`, so if you turn it
off later, in Settings or with `timedatectl set-ntp false`, running the
installer again leaves it off and says so. An existing install gets it
the next time the installer runs.

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
  tray tools, brightness tools, Flatpak, the GTK desktop portal, GNOME
  Keyring, which a display-manager login unlocks, the Thunar file manager
  (Super+E), and NetworkManager. NetworkManager is enabled only when no other
  network manager (systemd-networkd, iwd, ConnMan, dhcpcd or netctl) is in use,
  and starts at the next boot. It also
  installs Celluloid, mpv, and sxiv, and gives a fresh account Celluloid for
  audio and video and sxiv for images through `scripts/seed-default-apps.sh`,
  which also makes Thunar the folder handler when Thunar is installed. An
  existing MIME preference file is never replaced; change these in Settings >
  Defaults when updating an existing account. It makes `lyona-appimage` the
  AppImage handler unless another is set (see below), and installs the
  available Arch GTK theme packages. A matching GTK
  theme is generated for every palette in `config/themes.toml`, so GTK
  applications follow the active theme without a downloaded theme pack.
  It also installs the [mybash](https://github.com/technicks89/mybash) shell
  configuration: a Starship prompt, Fastfetch, `fzf` and `zoxide`, cloned into
  `~/.local/share/mybash` and linked from `~/.bashrc`,
  `~/.config/starship.toml`, `~/.config/fastfetch/config.jsonc`, and
  `~/.local/bin/starship-theme`. Any of those files that was there before is
  kept beside it, as for example `~/.bashrc.bak.20261003-142501`; re-running
  the installer leaves links that are already in place alone. Those links
  point into the checkout, so editing `~/.bashrc` edits the checkout: running
  the installer again updates a checkout without changes to the reviewed
  mybash version in place, and leaves one with your edits as it is.
  Offline, the existing checkout is kept.
  - **Topgrade.** It also installs [Topgrade](https://github.com/topgrade-rs/topgrade),
    which updates everything with one `topgrade` command. Topgrade is only in
    the AUR on Arch, so the installer builds the AUR's `topgrade-bin` package,
    which repackages upstream's release binary, with `makepkg` and installs it
    with `pacman`. It takes seconds and needs no Rust toolchain.
  - **What is trusted:** the PKGBUILD is pinned to a reviewed AUR commit, and
    every file it downloads has a checksum. `makepkg` runs as you, never as
    root; only the built package is installed with `sudo pacman -U`. See
    `docs/AUR-PACKAGES.md`.
  - **When:** it is installed last, after every other step that needs
    `sudo`. The `sudo` timestamp is closed first, so `sudo` asks for your
    password again to install the built package. If it fails, the install
    carries on.
  - **If it cannot be built** (the AUR or GitHub unreachable, say), the
    install says so and carries on; run `install-topgrade` later to try again.
  - **Updates:** `pacman -Syu` does not update AUR packages. Topgrade updates
    itself, through `yay`, each time it runs.
  - **Skipping it:** pass `--skip-topgrade` (or set `DWM_INSTALL_TOPGRADE=false`).
  - **Later, or on an existing install:** run `install-topgrade` (or
    `scripts/install-topgrade` from the checkout). It does nothing when a
    Topgrade package is already installed; `install-topgrade --force`
    reinstalls it, and `--dry-run` shows what it would do.
  - **Upgrading from a cargo-built Topgrade:** an older lyona built Topgrade
    with cargo into `~/.cargo/bin`, which comes before the package on `PATH`.
    `install-topgrade` offers to remove it when run in a terminal, and
    otherwise says how: `cargo uninstall topgrade`. Nothing removes it
    silently. lyona no longer installs `rustup` or `cargo-update`; if you have
    no other use for them, remove them with `sudo pacman -Rns rustup
    cargo-update`.
- `full`: `recommended` plus optional extras such as wallpapers, display-manager
  setup, `rsync` and `autorandr`. x86_64 Arch full installs also
  include Steam, Gamescope, and 64-bit and 32-bit GameMode and MangoHud support
  after separate repository approval.
  The installer enables the `multilib` repository for Steam, Gamescope,
  GameMode, and MangoHud, and installs them, with this machine's Vulkan
  drivers, in the same transaction as everything else. It then adds the
  invoking user to the `gamemode` group; log out and back in before using its
  privileged tuning helpers.

The default is `full` to preserve the historical automated installer behavior.

The installer installs every package of the chosen profile in one `pacman -Syu
--needed` transaction, so **it also upgrades the system**, as installing on an
out-of-date Arch system should, never leaving a partial upgrade. Packages already
installed are left alone, so re-running it is safe. The gaming packages are in
the same transaction: `multilib` is enabled first, once you approve it, and the
transaction syncs it with the other repositories.

- **A package missing from the repositories:** an optional one (`maim`, a GTK
  theme, `qt6ct`, Firefox and so on) is left out with a warning, and the
  transaction is retried once without it. Without `maim`, for example, the
  screenshot hotkeys stay disabled.
- **A required one** (the build tools, X11, the session's runtime and the
  desktop itself) stops the install before anything of lyona's is installed.
- **Interactive runs** let `pacman` ask before it installs; `--non-interactive`
  runs it with `--noconfirm`.

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

**dwm build settings.** A new `config.h` uses `config.def.h`'s defaults: the
monitor's refresh rate, font size 12, Super as the modifier, and the usual
layout. To choose them, add `--configure-build`. The installer then asks
before its summary, and asks again when an answer isn't valid. Your answers
become `config.h` only once you accept the summary. Unattended, set
`DWM_REFRESH_RATE`, `DWM_FONT_SIZE`, `DWM_MODKEY` and the other values in
`scripts/configure-build.sh --help`. An existing `config.h` is always kept.

Without `--enable-arch-gaming-repos`, unattended Arch full installs skip
Steam, Gamescope, GameMode, and MangoHud rather than changing repository trust.
An already-enabled `multilib` counts as approval, since nothing in
`pacman.conf` has to change -- this is what installs from the lyona ISO get,
because the ISO ships `multilib` enabled.

### AppImages

Opening an AppImage file, for example from Thunar or your browser's downloads,
asks first: **Add and run**, **Add only** or **Cancel**, with where it was
downloaded from when the browser recorded it. Only run programs you trust.
Closing the question is Cancel, and the file stays where it was. Run from a
terminal, `lyona-appimage open FILE` asks there instead.

Adding moves it to `~/Applications`, makes it executable, and writes a launcher
entry with the name and icon from inside the AppImage. `lyona-appimage` reads
them with `unsquashfs` and never runs the file to do so. **Add and run** then
starts it; opening it again later just starts it, without asking. Take one out
again with `lyona-appimage remove NAME` (`lyona-appimage list` shows them): the
file goes to the trash, and its entry and icon are removed. `fuse2` lets
the classic AppImages run, and both it and `squashfs-tools` come with the
recommended desktop.

Gear Lever is no longer installed by default: it needs about 1.7 GB of Flatpak
runtimes. Add `--with-gearlever` (or set `DWM_INSTALL_GEARLEVER=true`)
to install it from Flathub; it then opens AppImages instead, with in-place
updates and its own window. An existing
Gear Lever is kept, and stays the AppImage handler. If an earlier image install
left Gear Lever pending for the first login, the next `install.sh` run cancels
that unless `--with-gearlever` is given.

### Flatpak prerequisites

The recommended and full profiles install the `flatpak` package. With
`--with-gearlever`, Gear Lever sets up the official Flathub remote for the
target user before it installs anything. The remote is verified, not just present: setup stops with an error
if a `flathub` remote points anywhere but `https://dl.flathub.org/repo`, has
signature verification disabled, or is disabled. If there is no `flathub`
remote it adds the official one and checks it again. Repeated setup keeps
existing apps and remotes, and an app that is already installed never needs the
remote, so it reports as installed even when the remote is not healthy.

After fixing a setup error, retry `scripts/install-gearlever` from the source
checkout. To prepare and verify only the user remote, run
`scripts/dwm-flatpak-setup --user`. If Flatpak is missing, rerun
`./install.sh --profile recommended` first.

### CachyOS repositories and kernel

Installs from the lyona ISO get this automatically and are not asked about
it. The repositories are added to the live medium *before* `archinstall` runs,
so `pacstrap` fetches the optimized packages directly instead of installing
Arch builds and replacing them afterwards -- the base system is downloaded
once, not twice. The installed system inherits the live medium's `pacman.conf`
along with the CachyOS mirrorlists and keyring, and `archinstall` installs
`linux-cachyos` as the only kernel. If the CachyOS mirror cannot be reached,
the install continues on the stock Arch repositories, with the stock Arch
kernel, instead of failing. If the repositories can be reached again later in
the install, `linux-cachyos` is added then and made the default, and the stock
kernel stays beside it, in the boot menu.

To keep installs fast, there is one kernel, apart from that case, and
no fallback initramfs. CPU microcode comes with the base system on real
hardware, and the boot menu is generated once. Where the stock kernel was kept,
it is also a way back: choose it in the boot menu.

**Qt part way through an update.** The CachyOS repositories come before Arch's,
and can publish some Qt modules of a new release before the rest. pacman would
install the mix, and Quickshell would not start. `install.sh` checks the
installed Qt modules after its package transaction: when they are from
different Qt releases, it installs them again from Arch's `extra` repository,
which publishes each release whole, and says so. A later `pacman -Syu` brings
back CachyOS's builds once theirs is newer. The check covers installs only. If
the panel disappears after a system update, a mixed Qt is the likely cause:
update again once CachyOS has finished, usually within a day, or run
`sudo pacman -S extra/qt6-base extra/qt6-declarative` with every other installed
`qt6-*` module of that release.

**If the new system does not boot,** recover it from the install medium. Boot
it, press Ctrl+C at the installer's first question, which cancels it and leaves
a root shell, and find the disk with `lsblk`. The installer made two partitions on it: the first is
`/boot` (the EFI system partition on UEFI, ext4 on legacy BIOS), the second is
the root filesystem. With the disk at `/dev/sda` (an NVMe disk's partitions are
`/dev/nvme0n1p1` and `/dev/nvme0n1p2`):

```sh
cryptsetup open /dev/sda2 root     # only for an encrypted install; then use /dev/mapper/root below
mount /dev/sda2 /mnt               # or: mount /dev/mapper/root /mnt
mount /dev/sda1 /mnt/boot
arch-chroot /mnt
```

**To keep a second kernel or the fallback image for recovery,** add them after
installing. The fallback image is set per kernel, in that kernel's preset under
`/etc/mkinitcpio.d/`: `linux-cachyos.preset`, or `linux.preset` on an install
without the CachyOS repositories. The second kernel here is the CachyOS LTS
one; on an install without CachyOS, use `linux-lts` instead.

```sh
sudo pacman -S linux-cachyos-lts linux-cachyos-lts-headers   # a second kernel (linux-lts linux-lts-headers without CachyOS)
sudo sed -i "s/^PRESETS=.*/PRESETS=('default' 'fallback')/" /etc/mkinitcpio.d/*.preset
sudo mkinitcpio -P                                            # build every kernel's images
sudo grub-mkconfig -o /boot/grub/grub.cfg                     # list them in the boot menu
```

Installs from earlier images keep their `linux-cachyos-lts`, stock kernel and
fallback images; nothing removes them.

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

### Updates reach existing accounts

`install.sh` and `lyona-update` (through `make install-user`) both run
`scripts/lyona-reconcile-user`, so an updated account gets the same per-user
changes as a fresh install of the same profile. Running it again changes
nothing.

- The install profile is recorded in
  `${XDG_STATE_HOME:-$HOME/.local/state}/lyona/install-profile`. An account
  installed before it was recorded counts as `recommended` when Quickshell is
  installed, `core` otherwise.
- `recommended` and `full`: the browser, media and image defaults for an
  account with none yet, and `lyona-appimage` as the AppImage handler unless
  another is set.
- Every profile: a key binding in `~/.config/lyona/hotkeys.toml` that is still
  exactly an earlier release's default is moved to this release's, for example
  the raw Quickshell IPC calls to `lyona-shell` and Super+Shift+Q to the
  logout that asks first. A line you changed is never touched, the previous
  file is kept as `hotkeys.toml.bak.DATE`, and a symlinked file is left alone.
  The old defaults are listed in `scripts/hotkeys-migrations`.

An AUR helper (`yay`) is installed automatically for you as a standing
convenience tool, independent of the package profiles above — none of the
required, recommended, or optional packages need it, since everything the
installer selects is available directly through official `pacman` repos
(`core`/`extra`/`multilib`). Lyona limits the AUR to where it is needed: today,
this `yay` helper, Topgrade's pinned `topgrade-bin`, the live medium's driver
for an older NVIDIA card, and the `yay -Syu` that Settings -> System ->
**Update packages** runs for you (see `docs/AUR-PACKAGES.md`).

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
- `/etc/default/grub.d/90-lyona-menu.cfg` sets `GRUB_DISABLE_BOOTNEXT=true`.
  Since GRUB 2.16, every firmware boot entry (the firmware's boot manager, a
  DVD drive, network boot) otherwise gets its own top-level
  `... (EFI BootNext)` menu entry. This is a drop-in file, so
  `/etc/default/grub` isn't edited for it. If you set
  `GRUB_DISABLE_BOOTNEXT` in `/etc/default/grub`, your setting is kept. If
  you set it after the drop-in was written, the next `apply` removes the
  drop-in. A file at that path that isn't lyona's copy is never replaced.
- `grub-mkconfig` regenerates `/boot/grub/grub.cfg`.

Every one of those is printed as it happens. Replaced lines are commented out
rather than deleted, so the previous values stay readable in the file next to
the backup.

The lyona image's own installs boot with GRUB, so they get the theme. Machines
that do not boot with GRUB are reported and left completely alone. A theme step
that fails does not fail the install.

Skip the bootloader edit with `--skip-grub-theme` (or
`DWM_INSTALL_GRUB_THEME=false`); the theme files are still installed, so it
can be selected later.

Manage it afterwards with:

```bash
lyona-grub-theme status    # detected bootloader and selected theme
lyona-grub-theme list      # installed themes
lyona-grub-theme apply     # select CyberRe (or apply <name>)
lyona-grub-theme remove    # back to the default GRUB appearance and entries
```

The theme is vendored from
[ChrisTitusTech/bootloader-themes](https://github.com/ChrisTitusTech/bootloader-themes)
(MIT) so it is available during an offline install.

## Starting the session

**Display manager** (SDDM, GDM, LightDM): log out and select **lyona** from the session list (its file is `/usr/share/xsessions/dwm.desktop`).

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

The provided `.xinitrc` only runs dwm inside a D-Bus session
(`dbus-run-session`). Everything else, the panel, the wallpaper and the power
settings among it, is dwm's own session startup (`autostart.sh`), the same as
from a display manager.

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
