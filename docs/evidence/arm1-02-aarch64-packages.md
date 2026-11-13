# ARM1-02: the dependency map on aarch64

Survey for ARM Sprint 1 item ARM1-02 (issue #2): every package every profile of
`scripts/dwm-packages.sh` resolves to with `ARCH=aarch64`, checked with
`pacman -Si` on an Arch Linux ARM system.

## How it was run

- **Date:** 2026-10-13 (databases synced 04:45 UTC; `extra` last modified
  02:27 UTC that day).
- **System:** Arch Linux ARM in an **emulated** aarch64 virtual machine:
  QEMU 11.1.2 TCG (`-M virt -cpu max`, 6 vCPUs, 6 GB) on an x86_64 host,
  edk2 UEFI firmware with ACPI. Installed from Arch Linux ARM's generic
  tarball `ArchLinuxARM-aarch64-latest.tar.gz` (built 2026-08-05, SHA-256
  `42a4eeaa038994ffd31fa173256ef2f0ef511358eeb41b9ea1f8626391b9b319`; its
  signature verified against the Arch Linux ARM Build System key
  `68B3537F39A313B3E574D06777193F152BDBE6A6`, taken from
  `archlinuxarm-keyring` 20240419-2). `pacman` 7.1.0.r9.g54d9411-2,
  `linux-aarch64` 7.1.6-1, mirror `mirror.archlinuxarm.org`.
- **Names:** 141 distinct packages, from every profile in the map (the
  composite profiles `required`, `recommended`, `optional` and `full` add no
  names of their own), resolved before the changes in this item.
- **Cross-check:** the same names were looked up in the `core`, `extra`,
  `alarm` and `aur` databases downloaded over HTTPS from
  `ca.us.mirror.archlinuxarm.org`, including what packages `provide`. Both
  methods give the same result. Arch Linux ARM does not sign its databases
  (no `.db.sig`), only its packages. One entry in `extra`'s database,
  `findnewest-0.3-4`, was all zero bytes; it is not a package lyona uses.

## Result

131 of 141 found; 10 missing.

| Missing | Profiles | Why | What the map does |
| --- | --- | --- | --- |
| `deepin-gtk-theme` | `theme-gtk` (recommended, full) | Not built by Arch Linux ARM, although it is `arch=any` in Arch | x86_64 only. Nothing in lyona references it; `adw-gtk-theme` stays |
| `libva-intel-driver` | `gpu-intel` (the image's GPU step) | Intel GPUs do not exist on aarch64 | x86_64 only |
| `nvidia-open` | `gpu-nvidia` | No prebuilt kernel module for Arch Linux ARM's kernels | The NVIDIA profiles resolve to nothing off x86_64 (GB10 is ARM Sprint 4's own profile). `nvidia-open-dkms` and `nvidia-utils` exist, but are gated with them |
| `nvidia-580xx-dkms`, `nvidia-580xx-utils`, `nvidia-470xx-dkms`, `nvidia-470xx-utils` | `gpu-nvidia-580xx`, `gpu-nvidia-470xx` | AUR or CachyOS on x86_64 too, never in the repositories | As above |
| `shellcheck` | `ci-tools`, `ci-full` | Not built by Arch Linux ARM (it needs GHC) | x86_64 only; the x86_64 CI job lints (ARM1-05) |
| `archiso` | `ci-tools`, `ci-full` | The ISO builder is x86_64 only | x86_64 only |
| `reflector` | `iso` (the x86_64 medium) | Ranks Arch's mirrors, not Arch Linux ARM's | **Unchanged**: the `iso` profile is the x86_64 medium's; its aarch64 counterpart is ARM Sprint 2's (ARM2-04) |

The gaming profile already resolved to nothing off x86_64; it now uses the
same gate. `multilib` is never enabled on aarch64 (`install.sh` checks
x86_64 before enabling it). Packages outside the map: the Vulkan driver
helper's `lib32-*` names run only on the x86_64 gaming path; `cosign`,
`fuse2` and `picom`, named in messages, all exist on aarch64.

After the change, `check-arch-packages` resolves every profile for
`ARCH=x86_64` and `ARCH=aarch64`: x86_64 is unchanged, and aarch64 drops
exactly the gated names. Only `reflector`, in `iso`, is still missing on
aarch64.

## Every package

Versions are those in Arch Linux ARM on the survey date. Profiles are the
leaf profiles naming the package.

| Package | Profiles | Result on aarch64 |
| --- | --- | --- |
| `accountsservice` | ci-full, system-management | `extra/26.27.3-1` |
| `adwaita-icon-theme` | ci-full, theme | `extra/51.0-1` |
| `adw-gtk-theme` | ci-full, theme-gtk | `extra/6.5-1` |
| `alacritty` | terminal, terminal-primary | `extra/0.17.0-1` |
| `alsa-utils` | ci-full, desktop | `extra/1.2.16-1` |
| `arch-audit` | ci-full, system-management-optional | `extra/0.2.0-5` |
| `archiso` | ci-tools, ci-full | **missing** |
| `autorandr` | ci-full, desktop-optional | `extra/1.15-1` |
| `base-devel` | build, aur-build, ci-smoke, ci-full | `core/1-2` |
| `bash` | mybash-bootstrap | `core/5.3.20-1` |
| `bash-completion` | ci-full, mybash-bootstrap, shell | `extra/2.18.0-1` |
| `bat` | ci-full, mybash-bootstrap, shell | `extra/0.26.1-3` |
| `blueman` | ci-full, desktop | `extra/2.4.6-2` |
| `bluez` | ci-full, desktop | `extra/5.87-2` |
| `bluez-utils` | ci-full, desktop | `extra/5.87-2` |
| `brightnessctl` | ci-full, desktop | `extra/0.5.1-3` |
| `celluloid` | ci-full, media | `extra/0.30-2` |
| `cosign` | ci-full, desktop | `extra/3.1.3-1` |
| `cups` | ci-full, system-management | `extra/2:2.4.20-1` |
| `curl` | runtime-required, ci-smoke, ci-full, iso | `core/8.22.0-1` |
| `dbus` | runtime-required, ci-smoke, ci-tools, ci-full | `core/1.16.2-1` |
| `dconf` | ci-full, theme | `extra/51.0-1` |
| `deepin-gtk-theme` | ci-full, theme-gtk | **missing** |
| `desktop-file-utils` | ci-full, media | `extra/0.28-1` |
| `dex` | ci-full, desktop | `extra/0.10.1-1` |
| `fastfetch` | ci-full, shell | `extra/2.69.0-1` |
| `feh` | ci-full, desktop | `extra/3.13.1-1` |
| `file-roller` | ci-full, desktop, file-manager | `extra/44.7-1` |
| `firefox` | ci-full, browser | `extra/157.0.1-1` |
| `flatpak` | ci-full, desktop | `extra/1:1.18.4-1` |
| `fontconfig` | build, ci-smoke, ci-full, mybash-bootstrap | `extra/2:2.18.3-2` |
| `freetype2` | build, ci-smoke, ci-full | `extra/2.14.3-1` |
| `fuse2` | ci-full, desktop, appimage | `extra/2.9.9-6` |
| `fzf` | ci-full, mybash-bootstrap, shell | `extra/0.74.5-1` |
| `gcc` | build, ci-smoke, ci-full | `core/16.1.1+r12+g301eb08fa2c5-1` |
| `git` | runtime-required, aur-build, ci-smoke, ci-full, mybash-bootstrap | `extra/2.56.0-1` |
| `gnome-keyring` | ci-full, desktop, keyring | `extra/1:51.1-1` |
| `gum` | ci-full, desktop, iso | `extra/2.0.2-1` |
| `gvfs` | ci-full, desktop, file-manager | `extra/1.62.0-3` |
| `gvfs-smb` | ci-full, desktop, file-manager | `extra/1.62.0-3` |
| `imlib2` | build, ci-smoke, ci-full | `extra/1.12.7-3` |
| `inotify-tools` | ci-smoke, ci-tools, ci-full, desktop | `extra/4.26.270-1` |
| `iw` | ci-full, desktop, network | `core/6.17-1` |
| `jq` | ci-smoke, ci-tools, ci-full, desktop, iso | `extra/1.8.2-1` |
| `kitty` | terminal | `extra/0.49.2-1` |
| `libnotify` | ci-full, desktop | `extra/0.8.8-1` |
| `libpulse` | ci-full, desktop | `extra/17.0+r98+gb096704c0-1` |
| `libva-intel-driver` | gpu-intel | **missing** |
| `libx11` | build, ci-smoke, ci-full | `extra/1.8.13-2` |
| `libxcb` | build, ci-smoke, ci-full | `extra/1.17.0-1` |
| `libxft` | build, ci-smoke, ci-full | `extra/2.3.9-1` |
| `libxinerama` | build, ci-smoke, ci-full | `extra/1.1.6-1` |
| `libxrender` | build, ci-smoke, ci-full | `extra/0.9.12-1` |
| `lightdm` | lightdm | `extra/1:1.33.1-1` |
| `lightdm-slick-greeter` | lightdm | `extra/2.2.7-1` |
| `light-locker` | ci-full, desktop | `extra/1.9.0-7` |
| `maim` | ci-full, screenshot-optional | `extra/5.8.2-1` |
| `make` | build, ci-smoke, ci-full | `core/4.4.1-3` |
| `mate-polkit` | ci-full, desktop | `extra/1.28.1-4` |
| `mesa` | gpu-intel | `extra/1:26.2.4-1` |
| `mpv` | ci-full, media | `extra/1:0.41.0-6` |
| `networkmanager` | ci-full, desktop, network | `extra/1.58.1-2` |
| `noto-fonts` | ci-smoke, ci-full, fonts | `extra/1:2026.10.01-1` |
| `noto-fonts-emoji` | ci-smoke, ci-full, fonts | `extra/1:2.051-1` |
| `nvidia-470xx-dkms` | gpu-nvidia-470xx | **missing** |
| `nvidia-470xx-utils` | gpu-nvidia-470xx | **missing** |
| `nvidia-580xx-dkms` | gpu-nvidia-580xx | **missing** |
| `nvidia-580xx-utils` | gpu-nvidia-580xx | **missing** |
| `nvidia-open` | gpu-nvidia | **missing** |
| `nvidia-open-dkms` | gpu-nvidia-dkms | `extra/615.78.08-1` |
| `nvidia-utils` | gpu-nvidia, gpu-nvidia-dkms | `extra/615.78.08-1` |
| `openssl` | iso | `core/3.6.5-1` |
| `packagekit` | ci-full, system-management | `extra/1.4.0-1` |
| `pacman-contrib` | ci-full, desktop, update-indicator | `extra/1.13.1-1` |
| `papirus-icon-theme` | ci-full, theme | `extra/20260801-1` |
| `pavucontrol` | ci-full, desktop | `extra/1:6.2-1` |
| `pciutils` | ci-full, desktop, iso | `core/3.15.0-1` |
| `picom` | ci-full, desktop | `extra/13-2` |
| `pipewire` | ci-full, desktop | `extra/1:1.6.9-1` |
| `pipewire-pulse` | ci-full, desktop | `extra/1:1.6.9-1` |
| `pkgconf` | build, ci-smoke, ci-full | `core/3.0.7-1` |
| `playerctl` | ci-full, desktop | `extra/2.4.1-5` |
| `plymouth` | iso | `extra/26.134.222-3` |
| `power-profiles-daemon` | ci-full, desktop | `extra/0.30-1` |
| `procps-ng` | runtime-required, ci-smoke, ci-full | `core/4.0.7-1` |
| `psmisc` | runtime-required, ci-smoke, ci-full | `core/23.7-2` |
| `python` | ci-full, desktop, system-management | `core/3.14.8-1` |
| `python-dbus` | ci-tools, ci-full | `extra/1.5.0-1` |
| `python-gobject` | ci-full, system-management | `extra/3.58.1-1` |
| `python-pillow` | ci-tools, ci-full | `extra/12.3.0-1` |
| `qemu-guest-agent` | vm-guest | `extra/11.1.2-1` |
| `qemu-hw-display-virtio-vga` | vm-guest | `extra/11.1.2-1` |
| `qt6ct` | ci-full, theme-optional | `extra/0.11-9` |
| `qt6-declarative` | ci-full, qml-development, qml-validation | `extra/6.12.0-1` |
| `quickshell` | ci-smoke, ci-full, desktop, qml-validation | `extra/0.3.2-1` |
| `reflector` | iso | **missing** |
| `rsync` | ci-full, desktop-optional | `extra/3.5.1-2` |
| `shellcheck` | ci-tools, ci-full | **missing** |
| `shfmt` | ci-tools, ci-full | `extra/3.14.1-1` |
| `spice-vdagent` | vm-guest | `extra/0.23.0-1` |
| `squashfs-tools` | ci-full, desktop, appimage | `extra/4.7.5-1` |
| `starship` | ci-full, shell | `extra/1.26.0-1` |
| `sxiv` | ci-full, media | `extra/26-2` |
| `system-config-printer` | ci-full, system-management-optional | `extra/1.5.18-7` |
| `tar` | mybash-bootstrap | `core/1.35-5` |
| `thunar` | ci-full, desktop, file-manager | `extra/4.20.10-1` |
| `thunar-archive-plugin` | ci-full, desktop, file-manager | `extra/0.6.0-1` |
| `trash-cli` | ci-full, shell | `extra/0.24.5.26-3` |
| `tree` | ci-full, mybash-bootstrap, shell | `extra/2.1.0-1` |
| `ttf-meslo-nerd` | ci-smoke, ci-full, fonts, font-meslo | `extra/3.5.1-2` |
| `tumbler` | ci-full, desktop, file-manager | `extra/4.20.2-2` |
| `unzip` | runtime-required, ci-smoke, ci-full, mybash-bootstrap | `extra/6.0-23` |
| `upower` | ci-full, desktop | `extra/1.91.5-1` |
| `util-linux` | runtime-required, ci-smoke, ci-full | `core/2.42.4-1` |
| `virtiofsd` | vm-guest | `extra/1.14.0-1` |
| `vulkan-intel` | gpu-intel | `extra/1:26.2.4-1` |
| `wireless-regdb` | ci-full, desktop, network | `core/2026.09.03-1` |
| `wireplumber` | ci-full, desktop | `extra/0.5.18-1` |
| `xcb-util` | build, ci-smoke, ci-full | `extra/0.4.1-2` |
| `xclip` | runtime-required, ci-smoke, ci-full | `extra/0.13-6` |
| `xdg-desktop-portal-gtk` | ci-full, desktop | `extra/1.15.3-1` |
| `xdg-user-dirs` | ci-full, desktop, file-manager | `extra/0.20-1` |
| `xdg-utils` | runtime-required, ci-smoke, ci-full | `extra/1.2.1-2` |
| `xdotool` | runtime-required, ci-smoke, ci-tools, ci-full | `extra/4.20260303.1-1` |
| `xf86-input-libinput` | ci-full, desktop | `extra/1.5.0-1` |
| `xf86-video-amdgpu` | gpu-amd | `extra/25.0.0-1` |
| `xorg-server` | x11, ci-smoke, ci-full | `extra/21.1.25-1` |
| `xorg-server-xvfb` | ci-smoke, ci-tools, ci-full | `extra/21.1.25-1` |
| `xorg-setxkbmap` | x11, ci-smoke, ci-full | `extra/1.3.5-1` |
| `xorg-xauth` | ci-tools, ci-full | `extra/1.1.5-1` |
| `xorg-xinit` | x11, ci-smoke, ci-full | `extra/1.4.4-1` |
| `xorg-xinput` | x11, ci-smoke, ci-full | `extra/1.6.4-2` |
| `xorg-xmessage` | ci-full, desktop | `extra/1.0.7-2` |
| `xorg-xprop` | runtime-required, ci-smoke, ci-full | `extra/1.2.8-1` |
| `xorg-xrandr` | x11, ci-smoke, ci-full | `extra/1.5.4-1` |
| `xorg-xrdb` | x11, ci-smoke, ci-full | `extra/1.2.3-1` |
| `xorg-xset` | x11, ci-smoke, ci-full | `extra/1.2.6-1` |
| `xorg-xsetroot` | x11, ci-smoke, ci-full | `extra/1.1.4-1` |
| `xscreensaver` | xscreensaver | `extra/6.15-1` |
| `xsettingsd` | x11, ci-smoke, ci-full | `extra/1.0.4-1` |
| `zoxide` | ci-full, shell | `extra/0.10.0-1` |

## Not tested

- Installing these packages: that is ARM1-06 (`install.sh` on this VM).
- A native aarch64 machine: the system was emulated. Package availability
  does not depend on that.
- The AUR pins and downloaded tools (`yay-bin`, `topgrade-bin`, herdr, Gear
  Lever, AppImages): ARM1-03.
