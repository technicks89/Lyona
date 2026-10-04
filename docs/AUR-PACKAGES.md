# AUR packages in Lyona

Audit of 2026-09-20 on a CachyOS host with `core`, `extra` and `multilib`
synced. Branch `no-aur-native-packages`, based on `origin/main` at `ed5ba44`.

**Policy (decision D-27, 2026-10-02): limit the AUR to where it is needed.**
Packages come from the official repositories (`core`, `extra`, `multilib`), or
the CachyOS repository where the medium adds it, whenever one of them can do the
job. The AUR is used only where none can.

Each use is written down here, pinned or bounded, reviewed, and listed in
`make check-aur-policy` (`tests/test-aur-policy.sh`), which fails on any other.
A new use needs all of that, and a decision; it is never added quietly.

Where the AUR is used today:

| Use | Why there is no official package | Where | Bounded by |
| --- | --- | --- | --- |
| The `yay-bin` helper, for the user | `yay` is not in the official repositories | `install.sh`, `ensure_yay_installed()` | a pinned commit (`YAY_BIN_REF`) |
| Legacy NVIDIA drivers, for older cards (Sync Sprint 14) | Arch dropped every pre-Turing driver | `install_legacy_nvidia_driver` in the live medium's postinstall | the CachyOS repository first; otherwise pinned, reviewed PKGBUILDs |
| The user's own package update (Sync Sprint 15, D-26) | AUR-built packages, such as the drivers above, are not updated by `pacman -Syu` | `run_system` in `scripts/lyona-update-terminal`: `yay -Syu` when `yay` is installed | the exact full upgrade, started by the user in their terminal; it names no packages, so it installs nothing new |

Kept out of the AUR:

- **Topgrade** (Sync Sprint 15 S15-06, decision D-28): AUR-only on Arch. It is
  built instead from its crates.io release by `scripts/install-topgrade`, using
  `rustup` from `extra`, or another Rust toolchain already installed.
  - **The version:** always the newest release on crates.io, looked up each
    time it runs (decided with the maintainer, 2026-10-02).
  - **What checks it:** `--locked` builds the dependency versions in the
    release's published `Cargo.lock`, and cargo checks every crate it downloads
    against the checksums in the crates.io index.
  - **What it does not do:** no version or hash is pinned in this repository,
    and a release is used as soon as it is published. That was chosen over a
    pinned, reviewed version, so that installs are always current. The trust
    rests on crates.io and Topgrade's maintainers.
  - **The guard:** `make check-aur-policy` fails if `topgrade` or
    `topgrade-bin` is ever named in a package profile, because neither is in
    the official repositories.

## Legacy NVIDIA drivers (Sync Sprint 14)

The legacy NVIDIA drivers for older cards, which have no driver in `core`,
`extra` or `multilib` since Arch moved to `nvidia-open` (Turing and newer):

| Branch | Cards | Packages (`scripts/dwm-packages.sh`) | AUR base | Pinned commit |
| --- | --- | --- | --- | --- |
| 580xx | Maxwell, Pascal, Volta (GTX 750 to GTX 10xx, Titan V) | `nvidia-580xx-dkms`, `nvidia-580xx-utils` (`arch:gpu-nvidia-580xx`) | `nvidia-580xx-utils` | `3d31a20c08a1e6c11c1abe953954f44158c9a592` (580.178.04-2) |
| 470xx | Kepler (GTX 600 and 700) | `nvidia-470xx-dkms`, `nvidia-470xx-utils` (`arch:gpu-nvidia-470xx`) | `nvidia-470xx-utils` | `af0b7617132e32dd39174779aa8ced2a726afc51` (470.256.02-8.03) |

- **When:** only on the live medium, only after the user picks the NVIDIA
  driver, and only on a card the device table
  (`config/nvidia-legacy-gpus.tsv`) maps to that branch.
- **From where (decision D-22):** the CachyOS repository's prebuilt, signed
  packages when the medium added that repository. Only otherwise does the AUR
  come in.
- **How:** `install_legacy_nvidia_driver` in
  `archiso/airootfs/root/lyona-postinstall.sh` clones the pinned commit as the
  new user. It installs the PKGBUILD's dependencies as root, runs `makepkg` as
  that user (never as root, never through `yay`), and installs the built
  packages with `pacman -U`. Any failure leaves nouveau.
- **What was reviewed at each pin:**
  - every source downloads from `download.nvidia.com` over HTTPS or ships in
    the repository, and has a checksum (no `SKIP`);
  - nothing pipes to a shell, uses `sudo` or clones more code;
  - the install script does no more than Arch's own `nvidia-utils`: the 580xx
    one enables NVIDIA's suspend and resume services, and the 470xx one prints
    a hint.

  Re-pin only after reviewing the diff since the last pin.
- **Updates:** an AUR-built driver is a foreign package. `pacman -Syu` does not
  update it, and the user's `yay` does; the install says so. Settings -> System
  -> **Update packages** runs `yay -Syu` when `yay` is installed, so it updates
  the driver too (Sync Sprint 15 S15-04). A driver from the CachyOS repository
  updates with `pacman` as usual.
- **What an update builds:** the pins cover only the first install. `yay -Syu`
  (and so "Update packages") updates the driver, and `yay-bin` itself, from
  each package's current AUR PKGBUILD, which nobody here has reviewed. Run it
  yourself, read what it shows, and use yay's diff prompt when it offers one
  (Sync Sprint 16 R16-12).
- **The guard:** `tests/test-aur-policy.sh` allows AUR access and `makepkg`
  only in `install.sh` (the helper bootstrap) and inside
  `install_legacy_nvidia_driver` (the legacy driver fallback). It requires each
  package in the two legacy profiles to be built by a pinned base. The one
  AUR-helper call it allows is the user's own full upgrade, `yay -Syu`, inside
  `run_system` in `scripts/lyona-update-terminal`. Any other AUR use fails it.

The 390xx driver (Fermi) is not included (D-23); those cards keep nouveau.

## AUR packages that existed

Two AUR packages were reachable from the repository. Only the first was a
dependency of anything.

| Package | Where it was referenced | What used it | Status |
| --- | --- | --- | --- |
| `xkbset` (AUR only; no package in `core`, `extra` or `multilib`) | `scripts/dwm-packages.sh`, profile `arch:desktop-optional` | `scripts/dwm-settings-input` and `scripts/dwm-settings-provider`, for the XKB AccessX controls: sticky, slow, bounce and mouse keys, and the AccessX shortcuts | **Removed.** Replaced by the in-tree `scripts/dwm-xkbset` (see below). Nothing in Lyona depends on `xkbset` any more. |
| `yay-bin` 13.0.1 (the AUR helper) | `install.sh`: `YAY_BIN_URL`, pinned `YAY_BIN_REF=13e0a4754d106a9252b7479bf1b370fbe454fc48`, `ensure_yay_installed()` | Nothing at install time. It is a standing convenience tool for the user, independent of every package profile | **Kept, by decision.** No package Lyona installs is built or fetched through it, and the guard below fails if one ever is. Settings uses it only for the user's own `yay -Syu` (Sync Sprint 15). |

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

113 unique package names across every profile in `scripts/dwm-packages.sh` and
`archiso/packages.x86_64`:

| Repository | Packages |
| --- | --- |
| `core` | 11 |
| `extra` | 99 |
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

`make check-aur-policy` (`tests/test-aur-policy.sh`; `make check-no-aur` is
its old name) fails when:

- an AUR helper is invoked (`yay -S`, `paru -S`, and so on) anywhere but the
  user's own `yay -Syu` in `run_system`;
- code outside `install.sh` (the helper bootstrap) or
  `install_legacy_nvidia_driver` in `archiso/airootfs/root/lyona-postinstall.sh`
  (the legacy driver fallback) reaches `aur.archlinux.org` or runs `makepkg`;
- a package named by any profile or the ISO is not in `core`, `extra` or
  `multilib`, except the two pinned legacy NVIDIA profiles above (a group such
  as `base-devel` also counts as found).

The repository check needs the official repositories synced. On a host that
cannot answer, it says so and passes the rest, so it never fails on a machine
that simply lacks a sync database.

To check by hand:

```bash
pacman -Si core/NAME || pacman -Si extra/NAME || pacman -Si multilib/NAME
```
