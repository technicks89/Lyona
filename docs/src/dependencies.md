# Dependencies and Package Profiles

lyona supports Arch Linux only. Every package it installs comes from one map,
`scripts/dwm-packages.sh`, so the installer, the install ISO, CI and this page
cannot disagree about a name. `tests/test-arch-packages.sh` fails if a package in
the groups below is missing from this page.

List any group yourself:

```bash
source scripts/dwm-packages.sh
dwm_packages arch required
```

Group names that are not listed print nothing.

## Installer profiles

`install.sh --profile` (or `DWM_INSTALL_PROFILE`) takes three values, described in
[Installation](./install.md#automated-installer):

| Profile | What it installs |
| --- | --- |
| `core` | `required`, plus Alacritty. |
| `recommended` | `core`, plus the `recommended` group. |
| `full` (the default) | `recommended`, plus the `optional` and `gaming` groups. |

The groups are made of smaller groups:

| Group | Made of |
| --- | --- |
| `required` | build + x11 + runtime-required |
| `recommended` | desktop + browser + media + system-management + screenshot-optional + theme + theme-gtk + fonts + shell + rust-toolchain |
| `optional` | theme-optional + desktop-optional + system-management-optional |
| `full` | required + recommended + optional + gaming |

The `optional` and `gaming` additions in `full` are conveniences. The desktop starts
without Picom, a wallpaper, Thunar or a preferred terminal, and dwm does not depend
on any of them.

## Groups

Each group below lists its packages exactly as the map prints them.

### `build`

Compilers and the X11 development libraries that build dwm.

`gcc` `make` `pkgconf` `base-devel` `libx11` `libxft` `libxinerama` `libxrender` `imlib2` `libxcb` `xcb-util` `freetype2` `fontconfig`

### `x11`

The Xorg server, `xinit`, and the X tools the session and Settings call (`xrandr`, `xrdb`, `xset`, `xinput`, `setxkbmap`), plus `xsettingsd`, which broadcasts theme, cursor and DPI to running toolkits.

`xorg-server` `xorg-xinit` `xorg-xrandr` `xorg-xrdb` `xorg-xset` `xorg-xsetroot` `xorg-xinput` `xorg-setxkbmap` `xsettingsd`

### `runtime-required`

What a running session needs: D-Bus, `xdotool` and `xprop` (the Quickshell state bridge), clipboard access, `git`, and the usual process and archive tools.

`dbus` `curl` `git` `procps-ng` `psmisc` `unzip` `util-linux` `xclip` `xdotool` `xorg-xprop` `xdg-utils`

### `desktop`

The managed shell and the desktop around it: Quickshell, Picom, Feh, Dex, the polkit agent, audio (PipeWire, WirePlumber, `pavucontrol`), brightness, notifications, Bluetooth, power, Flatpak, the GTK desktop portal, the login keyring, and the signature check of lyona's own updates.

`quickshell` `picom` `python` `feh` `dex` `mate-polkit` `alsa-utils` `brightnessctl` `inotify-tools` `jq` `libpulse` `pipewire` `pavucontrol` `pipewire-pulse` `wireplumber` `libnotify` `light-locker` `xf86-input-libinput` `bluez` `bluez-utils` `blueman` `playerctl` `upower` `power-profiles-daemon` `flatpak` `xdg-desktop-portal-gtk` `pciutils` `gum` `cosign` `gnome-keyring` `pacman-contrib`

`cosign` checks the Sigstore signature of each lyona release before `lyona-update` installs it (decision D-31). Without it, an update to a signed release is refused.

`gnome-keyring` (the `keyring` group) stores secrets for browsers, NetworkManager and other applications. It includes `pam_gnome_keyring.so`, which Arch's LightDM PAM stack already loads, so a password login unlocks the keyring; there is no separate PAM package. Under `startx` the keyring is unlocked on first use instead. `dwm-diagnostics` and System Health flag it when it is missing.

`pacman-contrib` (the `update-indicator` group) provides `checkupdates`, which the panel's update icon counts pending package updates with. It never takes pacman's lock.

### `browser`

A web browser, for SUPER+B and the links other programs open. On a fresh account, `seed-default-apps.sh` makes it the default for web links and HTML pages only. Firefox also claims image, audio and video types, but those stay with sxiv and Celluloid. The installer skips it when your default `https` handler (`xdg-mime query default x-scheme-handler/https`) is another browser that's already installed.

`firefox`

### `media`

Celluloid, mpv and sxiv, which `scripts/seed-default-apps.sh` makes the defaults for audio, video and images on a fresh account.

`celluloid` `mpv` `sxiv` `desktop-file-utils`

### `system-management`

What Settings > System reads: PackageKit and its Python bindings, AccountsService and CUPS.

`python` `python-gobject` `packagekit` `accountsservice` `cups`

### `screenshot-optional`

`maim`, used by the screenshot hotkeys. The installer skips it, and says so, if it is not in the enabled repositories.

`maim`

### `theme`

Icon themes and `dconf`.

`dconf` `adwaita-icon-theme` `papirus-icon-theme`

### `theme-gtk`

The Arch GTK theme packages the installer installs when available; lyona also generates a GTK theme from every palette of its own.

`adw-gtk-theme` `deepin-gtk-theme`

### `fonts`

Noto fonts and emoji, and MesloLGS Nerd Font, the terminal, bar and shell font
(the `font-meslo` profile).

`noto-fonts-emoji` `noto-fonts` `ttf-meslo-nerd`

### `shell`

The shell add-ons the `mybash` configuration uses: Starship, zoxide, fzf, Fastfetch and friends.

`starship` `zoxide` `fzf` `fastfetch` `bat` `tree` `trash-cli` `bash-completion`

### `rust-toolchain`

`rustup`, whose `cargo` builds Topgrade (`scripts/install-topgrade`). Topgrade is AUR-only on Arch, so its newest crates.io release is built with cargo instead. `rustup` conflicts with Arch's `rust` and `cargo` packages. When another Rust toolchain is installed (Arch's `rust`, another package providing it, or a `cargo` from rustup.rs), the installer leaves `rustup` out and uses that toolchain's `cargo`. `check-deps.sh` notes this beside its package suggestions.

`cargo-update` provides `cargo install-update`, which Topgrade's Cargo step runs to update what `cargo install` installed, Topgrade included. Without it, Topgrade skips that step. It depends on a `cargo`, which `rustup` or Arch's `rust` provides. Beside a `cargo` from rustup.rs, which no package provides, the installer leaves it out, since pacman would add Arch's `rust` next to it: run `cargo install cargo-update` there instead.

`rustup` `cargo-update`

### `desktop-optional`

Thunar with SMB browsing and archive support, thumbnails, NetworkManager, `rsync` and `autorandr`. Every package is in the official repositories.

`thunar` `gvfs` `gvfs-smb` `tumbler` `thunar-archive-plugin` `file-roller` `xdg-user-dirs` `networkmanager` `rsync` `autorandr`

### `theme-optional`

`qt6ct` and `qt5ct`. With either installed, applying a theme points it at the palette lyona generates so Qt applications follow it.

`qt6ct` `qt5ct`

### `system-management-optional`

The printer configuration tool and `arch-audit`.

`system-config-printer` `arch-audit`

### `gaming`

Steam, Gamescope, GameMode and MangoHud, including the 32-bit builds. Needs the `multilib` repository.

`steam` `gamescope` `gamemode` `lib32-gamemode` `mangohud` `lib32-mangohud`

### `terminal`

Alacritty and Kitty.

`alacritty` `kitty`

### `terminal-primary`

Alacritty, the default terminal.

`alacritty`

### `lightdm`

The LightDM display manager and its greeter.

`lightdm` `lightdm-slick-greeter`

### `iso`

What the live install medium itself runs, on top of archiso's `releng`
profile: the whole package list of the install image. The desktop is not on
it, as the new system downloads every package it installs (#229).

- `plymouth` draws the boot splash;
- `gum` draws the wizard, and `jq` writes its credentials file;
- `curl` checks the network, looks up the timezone and sets up the CachyOS repositories;
- `openssl` hashes the password, and `pciutils` (`lspci`) finds the GPU.

`plymouth` `gum` `jq` `curl` `openssl` `pciutils`

### `qml-development`

QML tooling for developing the shell: `qt6-declarative` (`qmllint`, `qmltestrunner`).

`qt6-declarative`

### `qml-validation`

What CI needs to validate the QML: Quickshell and `qt6-declarative`.

`quickshell` `qt6-declarative`

## Not installed by any profile

Continuous-integration groups (`ci-smoke`, `ci-tools`, `ci-full`) exist for the
project's own test jobs and are not part of an install.

## Repositories and the AUR

Every package above is in the official Arch repositories. Lyona limits the AUR to
where no official package can do the job (`docs/AUR-PACKAGES.md`, enforced by
`make check-aur-policy`). Today that is three places:

- the `yay` helper `install.sh` installs for you;
- on the live medium, an older NVIDIA card's legacy driver, built from a pinned AUR
  PKGBUILD when the CachyOS repository cannot supply it;
- Settings -> System -> **Update packages**, which runs your own `yay -Syu` when `yay`
  is installed. 

Steam and its libraries need the `multilib` repository, which the installer enables only after
separate approval.
