# AUR packages in Lyona

Audit of 2026-09-20 on a CachyOS host with `core`, `extra` and `multilib`
synced. Branch `no-aur-native-packages`, based on `origin/main` at `ed5ba44`.

**Policy.** An AUR helper stays installed for the user, but **no package Lyona
installs depends on the AUR.** Every package the profiles and the live ISO name
comes from the official repositories, and `make check-no-aur` keeps it that way.

## AUR packages that existed

Two AUR packages were reachable from the repository. Only the first was a
dependency of anything.

| Package | Where it was referenced | What used it | Status |
| --- | --- | --- | --- |
| `xkbset` (AUR only; no package in `core`, `extra` or `multilib`) | `scripts/dwm-packages.sh`, profile `arch:desktop-optional` | `scripts/dwm-settings-input` and `scripts/dwm-settings-provider`, for the XKB AccessX controls: sticky, slow, bounce and mouse keys, and the AccessX shortcuts | **Removed.** Replaced by the in-tree `scripts/dwm-xkbset` (see below). Nothing in Lyona depends on `xkbset` any more. |
| `yay-bin` 13.0.1 (the AUR helper) | `install.sh`: `YAY_BIN_URL`, pinned `YAY_BIN_REF=13e0a4754d106a9252b7479bf1b370fbe454fc48`, `ensure_yay_installed()` | Nothing. It is a standing convenience tool for the user, independent of every package profile | **Kept, by decision.** No package Lyona installs is built or fetched through it, and the guard below fails if one ever is. |

### The `xkbset` replacement

`scripts/dwm-xkbset` is a single Python file that talks to libX11's XKB calls
through `ctypes`, the same approach as `scripts/dwm-cursor-reload`, so it needs
no package beyond what is already installed. It accepts the subset of `xkbset`
that Settings used, so the callers changed only the command name:

```
dwm-xkbset q                 # "Sticky-Keys = On|Off" and four more lines
dwm-xkbset st | -st          # sticky keys on | off
dwm-xkbset sl bo m a         # slow, bounce, mouse keys, AccessX shortcuts
```

`make check-xkbset` runs it against a real X server: each control toggles
alone, persists across processes, applies in order, and bad input is refused
without changing state. It also compares the mask constants with the system
`XKB.h` header, so a wrong bit fails the test.

## Everything else comes from the official repositories

111 unique package names across every profile in `scripts/dwm-packages.sh` and
`archiso/packages.x86_64`:

| Repository | Packages |
| --- | --- |
| `core` | 11 |
| `extra` | 97 |
| `multilib` | 3 (`steam`, `lib32-gamemode`, `lib32-mangohud`, the x86_64 gaming profile) |
| AUR or anywhere else | **0** |

CachyOS builds `-v3` rebuilds of many of these. They resolve to the same names,
so the check asks `core`, `extra` and `multilib` explicitly rather than trusting
whichever repository pacman finds first.

## Not AUR, but outside the official repositories

Not packages, and not changed here. Listed so the picture is complete.

| Item | Source | Where |
| --- | --- | --- |
| GearLever (AppImage manager) | Flathub, through Flatpak | `scripts/install-gearlever` |
| `herdr` | Checksummed release download from herdr.dev | `scripts/install-herdr` |
| `mybash` shell configuration | `git clone` from GitHub | `scripts/install-mybash` |
| Meslo Nerd Font | Checksummed GitHub release zip, pinned to 3.4.0 | `install.sh` (`MESLO_URL`) |
| CachyOS repositories | Optional, `--enable-cachyos-repos`; signing key fingerprint pinned | `scripts/lyona-cachyos` |

## On the audited host, not referenced by Lyona

`pacman -Qm` lists `nvidia-sync`, `nvidia-sync-terminal-fix` and
`yay-bin-debug` (the debug split of the `yay-bin` build that `install.sh`
performs). None of them is named anywhere in this repository.

## Keeping it true

`make check-no-aur` (`tests/test-no-aur.sh`) fails when:

- an AUR helper is invoked to install packages (`yay -S`, `paru -S`, and so on);
- anything other than `install.sh` reaches `aur.archlinux.org` or runs `makepkg`;
- a package named by any profile or the ISO is not in `core`, `extra` or
  `multilib` (a group such as `base-devel` also counts as found).

The repository check needs the official repositories synced. On a host that
cannot answer, it says so and passes the rest, so it never fails on a machine
that simply lacks a sync database.

To check by hand:

```bash
pacman -Si core/NAME || pacman -Si extra/NAME || pacman -Si multilib/NAME
```
