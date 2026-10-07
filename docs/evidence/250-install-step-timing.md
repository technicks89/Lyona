# #250: install step timing and the smaller install costs

Issue `#250`, part 6/6 of the install-speed series (#245 to #250).

**Status: the timing is in place, and the baseline is recorded** from one
QEMU/KVM install of an image built from commit `d1a7c87` (2026-10-07). Every
column is filled in: "After #249", "After #245", "After #247/#248" and
"After #246".

## A. Step timing

- Image install: `run_logged` (`archiso/airootfs/root/lyona-ui.sh`) logs
  `[HH:MM:SS] [step N/10] <step>` when a step starts and
  `... done in 42s` (or `failed (exit N) after 42s`) when it ends.
  `/var/log/lyona-postinstall.log` on the new system ends with a `Step times`
  table: the wizard's archinstall step, then the ten postinstall steps.
- `install.sh`: a `[TIME] <section>: done in 42s` line after each section, then
  the same table before the closing banner. In an image install these lines are
  part of the "Running install.sh" step's output, so they appear in the same
  log.
- Tested by `tests/test-install-step-timing.sh` (`make check-install-step-timing`)
  against a stub `gum`.

## Baseline: full image install

- **Image:** `lyona-2026.10.0-beta.5-x86_64.iso` built from `d1a7c87`, SHA-256
  `c9f7250b09a1b9d931fffab2544e3976f640a7fd80ace6f46af0b9c240d5178c`.
- **VM:** QEMU 11.1 with KVM, UEFI (OVMF), q35, 4 vCPUs (`-cpu host`, AMD), 4 GiB
  RAM, 40 GiB virtio qcow2 disk on NVMe, user-mode network. Host: 12 threads,
  about 300 Mbit/s.
- **Answers:** btrfs, no encryption, timezone detected as `America/New_York`,
  no NVIDIA GPU (virtio-vga). The CachyOS repositories were set up.
- **How:** the wizard's prompts were answered by a driver over the serial
  console, which then ran the wizard's own steps (`setup_cachyos_repositories`,
  `generate_configs`, `run_archinstall`) and the unchanged postinstall. The
  first boot reached the LightDM greeter within 40 s.

| Step | Baseline | After #245 | After #247/#248 | After #246 | After #249 |
| --- | --- | --- | --- | --- | --- |
| Wizard: choosing the fastest package mirrors | (no step) | 11s | 10s / 10s | 12s | 11s / 12s |
| Wizard: adding the CachyOS repositories | 4s | 5s | 5s / 6s | 3s | 5s / 4s |
| archinstall | 1m 33s | 1m 21s | 1m 31s / 1m 30s | 1m 01s | 1m 19s / 1m 24s |
| Adding the CachyOS repositories | 0s | 0s | 0s / 0s | 0s | 0s / 1s |
| Updating the new system | 2s | 2s | 2s / 2s | 4s | 2s / 1s |
| Installing the CachyOS kernels | 14s | 13s | 13s / 13s | 0s ("Checking the kernel") | 13s / 14s |
| Installing CPU microcode | 6s | 6s | 7s / 7s | (no step) | 6s / 7s |
| Installing GPU drivers | 0s | 0s | 0s / 0s | 0s | 0s / 0s |
| Configuring NetworkManager | 0s | 0s | 0s / 0s | 0s | 1s / 0s |
| Checking swap | 2s | 1s | 2s / 1s | 2s | 1s / 1s |
| Checking for a QEMU/KVM hypervisor | 0s | 0s | 0s / 0s | 0s | 0s / 1s |
| Running install.sh --profile full | 9m 41s | 1m 52s | 1m 26s / 1m 14s | 55s (see below) | 1m 34s / 1m 43s |
| Building Topgrade | 3m 02s (failed) | 5s (installing topgrade-bin) | 5s / 5s | 5s | 5m 38s / 5m 32s |
| **Total of the steps** | 14m 44s | 3m 56s | 3m 41s / 3m 28s | 2m 22s (2m 37s with the Qt step) | 9m 10s / 9m 20s |

Wall clock from the end of the wizard's questions to the reboot: 14m 48s.

The "After #249" column holds two runs, Europe/Berlin / UTC; #249 landed before
the other issues in the series. "After #245" is one Europe/Berlin run with both
#249 and #245 in. "After #247/#248" holds two Europe/Berlin runs, #247 / #248, each on top of
the issues before it. The Topgrade row is a different cost in each column:

- **Baseline:** the cargo build, which failed after 3m 02s.
- **After #249:** the cargo build, which succeeded in both runs (5m 38s and
  5m 32s).
- **After #245, #247, #248 and #246:** no build: `topgrade-bin` from the
  AUR, built with `makepkg` and installed with `pacman -U` (5 s).

Without the Topgrade step, the total went from 11m 42s in the baseline to 3m 32s
and 3m 48s after #249, 3m 51s after #245, 3m 36s after #247, 3m 23s after #248,
and 2m 32s after #246 (counting its 15 s Qt step, below).

`install.sh`'s sections:

| Section | Baseline | After #249 (Berlin / UTC) | After #245 (Berlin) | After #247 (Berlin) | After #248 (Berlin) | After #246 (Berlin) |
| --- | --- | --- | --- | --- | --- | --- |
| Required packages | 13s | 9s / 10s | 11s | (in Packages) | (in Packages) | (in Packages) |
| Recommended packages | 1m 25s | 46s / 45s | 54s | (in Packages) | (in Packages) | (in Packages) |
| Optional extras and gaming | 7m 45s | 23s / 31s | 29s | (in Packages; gaming below) | (in Packages) | (in Packages) |
| Packages: every profile, one transaction | | | | 57s | 58s, gaming included | 41s, gaming included; 31 packages were already installed by the Qt step |
| Gaming: multilib, then its own transaction | | | | 15s | (in Packages) | (in Packages) |
| mybash | 1s | 0s / 0s | 0s | 0s | 1s | 1s |
| Wallpapers | 5s | 5s / 4s | 4s | 4s | 6s | 4s |
| Display manager (LightDM) | 3s | 2s / 2s | 3s | 0s (installed with the packages) | 0s | 0s |
| yay | 4s | 4s / 4s | 3s | 4s | 4s | 4s |
| Build (make clean; make) | 2s | 2s / 2s | 3s | 2s | 2s | 2s |
| make install-system | 2s | 2s / 2s | 1s | 1s | 2s | 1s |
| GRUB theme | 1s | 0s / 1s | 0s | 0s | 1s | 1s |
| Everything else | 0s each | 0-1s each | 0-2s each | 0-1s each | 0-1s each | 0-1s each |

### After #246: one CachyOS kernel, no fallback initramfs

One Europe/Berlin install from an image built from `fb7e28c`, SHA-256
`83cedd085e083a21d247d82bf62710f4ab3533ff27cc9e92de6748c209cd3b52`,
same VM and host as the baseline. The image was built on a host with
squashfs-tools 4.6.1 and `-Xbcj x86`: 4.7.5 failed the squashfs step there with
`xz uncompress failed with error code 9` (a multithreaded race, not this
change).

- **A Qt step outside the installer, needed on 2026-10-07 only.** CachyOS was
  part way through Qt 6.12: `cachyos-extra-v3` had `qt6-declarative 6.12.0-1.1`
  but still `qt6-base 6.11.2-3.1`. pacman prefers the CachyOS repositories, so
  the new system got both, `quickshell` failed to load (`version 'Qt_6.12' not
  found`), and `install.sh` stopped at its Quickshell check. A first run failed
  there, after the kernel steps. For a run that finishes, the driver installed
  `extra/qt6-base 6.12.0-2` after archinstall, using only `[core]` and
  `[extra]`, because the CachyOS key is not trusted until the postinstall's first
  step. That took 15 s and installed 31 packages (24.2 MiB). It is in no step's
  time, and those 31 packages were then already installed when `install.sh` ran,
  so "Packages" (41 s) is low by about that much. Counting it, the total is
  2m 37s, against 3m 28s after #248.
- **Kernel:** archinstall installed `linux-cachyos` as the only kernel
  (`pacman -Q linux` and `linux-cachyos-lts`: not found). `/boot` holds only
  `vmlinuz-linux-cachyos` and `initramfs-linux-cachyos.img`; the preset is
  `PRESETS=('default')`, and GRUB lists `Arch Linux` and `Advanced options` with
  only `linux-cachyos`, no fallback entry. The initramfs was built twice: once by
  archinstall and once by `install.sh`'s transaction, against 8 builds in the
  baseline.
- **Time:** archinstall took 1m 01s, against 1m 30s after #248, and the kernel
  and microcode steps, 20 s after #248, are gone ("Checking the kernel": 0 s).
  The whole install, from the end of the wizard's questions to the reboot, took
  2m 54s, or 2m 39s without the Qt step, against 3m 45s after #248.
- **Microcode:** none installed (`intel-ucode` and `amd-ucode` not found). That
  is the design: archinstall adds it on real hardware and none in a virtual
  machine. Not verified on real hardware.
- No warnings. `topgrade-bin 17.12.3-1` installed. It booted to the LightDM
  greeter within 40 s.
- Not tested in a VM: an install without the CachyOS repositories (stock
  `linux`, then `linux-cachyos` added by the postinstall), and microcode on real
  hardware.

### After #248: gaming in the same transaction

One Europe/Berlin install from an image built from the uncommitted #248 change
on top of `c816c81`, SHA-256
`07722a6f5f3b1b3e3bb326a1e3fca546594645d3947c63685c09808a67a1cc81`,
same VM and host as the baseline.

- `install.sh` ran pacman once: one `pacman -Syu --needed --noconfirm`
  transaction of 509 packages, with Steam, Gamescope, GameMode, MangoHud and
  the VM's Vulkan driver (`vulkan-swrast`, `lib32-vulkan-swrast`) in it. The
  separate `pacman -Syu` for `[multilib]` and the gaming transaction are gone.
  On the image, archinstall had already enabled `[multilib]`, so
  `configure_arch_multilib_repository` changed nothing.
- "Packages" took 58 s with gaming in it, against 57 s plus 15 s for gaming in
  the #247 run. `install.sh` took 1m 14s, against 1m 26s. The whole install,
  from the end of the wizard's questions to the reboot, took 3m 45s.
- The `gamemode` group was created by the package and the user was added to
  it. No warnings; nothing was left out.
- It booted to the LightDM greeter within 40 s.
- Not tested in a VM: an existing system where `[multilib]` is disabled and
  enabled by the installer, and declining it. Both are covered by
  `tests/test-install-multilib.sh` against stubs.

### After #247: one pacman transaction

One Europe/Berlin install from an image built from the uncommitted #247 change
on top of `bc3c2b9`, SHA-256
`6afc869d5bcc659e1944c5892f2aacfb02987b6fe253ac70c7fae8f04e7a555b`,
same VM and host as the baseline.

- `install.sh` ran three pacman commands, against about sixteen before: the
  one `pacman -Syu --needed --noconfirm` transaction with every profile's
  packages, the separate `pacman -Syu` that syncs `[multilib]`, and the gaming
  transaction with the Vulkan drivers. #248 folds the last two into the first.
- "Packages" took 57 s, against 1m 34s for the required, recommended and
  optional sections in the #245 run (whose 29 s optional section included
  gaming; gaming is 15 s here). `install.sh` took 1m 26s, against 1m 52s.
- Nothing was missing from the repositories, so no retry ran and there were
  no warnings. `qt6ct`, `alacritty`, `lightdm`, `maim`, `firefox` and `steam`
  are installed; `qt5ct` is not.
- It booted to the LightDM greeter within 40 s.
- Not tested in a VM: a package missing from the repositories (the retry) and
  an interactive run (pacman's own prompts). Both are covered by
  `tests/test-arch-packages.sh` against a stub pacman.

### After #245: Topgrade from the AUR

One Europe/Berlin install from an image built from `16770d4`, SHA-256
`c431bc66ed2138b0bac241cd6e34fdfcef1372226015d4d7695fb4aefff5e61b`,
same VM and host as the baseline.

- The Topgrade step took 5 s: clone the pinned `topgrade-bin`, download the
  6.24 MiB release tarball (its b2sum passed), `makepkg` as the new user, and
  `pacman -U` as root. The cargo build it replaces took 5m 32s and 5m 38s in the
  #249 runs, and failed after 3m 02s in the baseline.
- On the new system: `topgrade-bin 17.12.3-1` is installed and
  `topgrade --version` runs as the user (`topgrade 17.12.3`, `/usr/bin/topgrade`).
  `rustup`, `rust`, `cargo` and `cargo-update` are not installed, there is no
  `~/.cargo`, and the build directory in `/var/tmp` is gone. No warnings.
- The whole install, from the end of the wizard's questions to the reboot, took
  4m 13s, against 14m 48s in the baseline. It booted to the LightDM greeter
  within 40 s.
- Not tested in a VM: `install-topgrade` on an existing system (its `sudo
  pacman -U` and the offer to remove an older cargo-built copy at a terminal),
  and a build that fails. Those are covered by `tests/test-install-topgrade.sh`
  against stubs.

### After #249: the mirrors and 10 parallel downloads

Two installs, same VM and host as the baseline. The first image was built from
the uncommitted #249 change; the second, SHA-256
`92c878fab17a15a4f638a6c0c5a2fa47669f93b5121fc26911d2d0dac0a85b86`, from
`4b0f583`.

- **Europe/Berlin:** `DE` from `zone.tab`; reflector ranked 20 German HTTPS
  mirrors in 11 s. The ranking ran from this host in the US, so the order is
  German mirrors as seen from here, not what a user in Germany would get.
- **UTC:** no country, so worldwide; 20 mirrors in 12 s, the fastest from here
  first (`losangeles.mirror.pkgbuild.com`, then `geo.mirror.pkgbuild.com`).
- In both, the installed `/etc/pacman.d/mirrorlist` is byte for byte the ranked
  live one, and the installed `/etc/pacman.conf` has `ParallelDownloads = 10`.
- **Found in the Berlin run, fixed before the UTC one:** the live medium still
  had `ParallelDownloads = 5`. `archiso/pacman.conf` configures only the image
  build; the live `/etc/pacman.conf` is the pacman package's. The wizard now
  sets it to 10 before archinstall, and the UTC run had
  `ParallelDownloads = 10` live before archinstall started.
- Both new systems booted to the LightDM greeter within 40 s.
- `install.sh` went from 9m 41s to 1m 34s and 1m 43s, almost all of it the
  gaming download that took 7m 18s in the baseline. One run per setting: mirror
  speed varies from run to run, and the baseline may have caught an unusually
  slow mirror.
- Not run in a VM: the ranking failing or timing out, and a country with fewer
  than three mirrors. Both are covered only by `tests/test-iso-install-mirrors.sh`
  against a stub reflector.

### What the baseline shows

- **One slow download made up most of the install.** In "Optional extras and
  gaming", `pacman -S lib32-vulkan-swrast vulkan-swrast` started at 21:19:49
  and its transaction began at 21:27:07: 7m 18s to download 79.9 MiB, starting
  with `lib32-llvm-libs` from the multilib mirror. The next run downloaded 91.5
  MiB (Steam and the rest of the gaming profile) in 8 s. This is mirror choice
  (#249), not CPU or package count, and it will vary from run to run.
- **Topgrade failed:** `rustup` timed out fetching
  `static.rust-lang.org/dist/channel-rust-stable.toml` after rustup and
  cargo-update were installed. The install still finished and listed it on the
  closing screen, as designed. #245 removes this download.
- The CachyOS CDN (`cdn77.cachyos.org`) returned 404 for several `-v3`
  packages; pacman fell back to other mirrors without failing.
- **Initramfs:** 8 builds in all across three kernels (`linux`,
  `linux-cachyos`, `linux-cachyos-lts`), each only the `default` preset; no
  fallback image was built. The kernels step took 14 s here, so #246's saving
  will mostly be download size and disk space on this host, and more on a slow
  CPU.
- Not run by the image install: Herdr (the full profile without
  `--install-herdr`) and Gear Lever (left for the first login).

## B. The smaller costs

B1 to B3 and B5 were measured on the development machine (12 threads, NVMe,
about 300 Mbit/s); B6 and B7 come from the VM baseline above. Times on old
hardware will be higher.

| Item | Finding | Result |
| --- | --- | --- |
| B1 Meslo Nerd Font | The GitHub `Meslo.zip` is 112,448,359 bytes, downloaded by `install.sh` and again by `install-mybash` when the font was missing. `ttf-meslo-nerd` (extra, 3.5.1-2) is a 5.7 MiB download, and `fc-scan` on its `MesloLGSNerdFont-Regular.ttf` gives the family `MesloLGS Nerd Font`, as the zip does. | **Fixed.** It is in the `fonts` profile (`font-meslo`), installed with the other packages; both downloads are gone. |
| B2 `fc-cache -f` in `make install-user` | `fc-cache -f`: 2.1 s with 219 fonts installed. Plain `fc-cache`: 0.008 s. `make install-user` writes only an alias file (`50-meslolgs-nerd-font-aliases.conf`), which fontconfig reads at lookup time, not from the cache. Pacman's `fontconfig.hook` already refreshes the cache for packaged fonts. | **Fixed.** Plain `fc-cache`. |
| B3 `make clean; make` | 2.1 s for a full rebuild here, and 0.004 s for `make clean`. | **Closed:** seconds even on a slow CPU, not worth an incremental-build rule. Re-check if the old-hardware run says otherwise. |
| B4 Gear Lever and Flatpak at first login | Needs a first login on an image install. | **Open:** not measured. |
| B5 Wallpapers | 85 files, 141 MB at the pinned commit (63 PNG, 22 JPEG). A shallow fetch took 3.8 s here, which is about a minute at 20 Mbit/s. A release tarball would not be smaller: the images are already compressed. | **Open, for a decision:** a smaller default set, with the rest downloaded later, is the only real saving, and choosing which wallpapers stay is a product call. |
| B6 Herdr and yay downloads | yay: 4s in the VM. Herdr is not installed by the image install (the full profile without `--install-herdr`). | **Closed:** too small to move earlier. |
| B7 `pacman -Syu` after archinstall | 2s in the VM: archinstall had already installed from the CachyOS repositories, and the upgrade found nothing to do. | **Closed:** effectively a no-op. #247 can fold it into the single install. |

## Not tested

- One VM run only, on fast hardware with a fast network. No old or low-end
  machine, no BIOS install, no NVIDIA GPU, no encrypted disk, and no install
  without the CachyOS repositories.
- The wizard's prompts were answered by a driver, not typed: the gum screens
  themselves were not exercised.
- The desktop session after login was not checked, so B1 (the font on screen
  with only the package installed) and B4 (Gear Lever at first login) are still
  unverified.
- An existing-system `install.sh` run, outside the image, has not been timed.
