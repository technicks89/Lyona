# #250: install step timing and the smaller install costs

Issue `#250`, part 6/6 of the install-speed series (#245 to #250).

**Status: the timing is in place, and the baseline is recorded** from one
QEMU/KVM install of an image built from commit `d1a7c87` (2026-10-07). Add a
column after each of #245 to #249 lands.

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
| Wizard: adding the CachyOS repositories | 4s | | | | |
| archinstall | 1m 33s | | | | |
| Adding the CachyOS repositories | 0s | | | | |
| Updating the new system | 2s | | | | |
| Installing the CachyOS kernels | 14s | | | | |
| Installing CPU microcode | 6s | | | | |
| Installing GPU drivers | 0s | | | | |
| Configuring NetworkManager | 0s | | | | |
| Checking swap | 2s | | | | |
| Checking for a QEMU/KVM hypervisor | 0s | | | | |
| Running install.sh --profile full | 9m 41s | | | | |
| Building Topgrade | 3m 02s (failed) | | | | |
| **Total of the steps** | 14m 44s | | | | |

Wall clock from the end of the wizard's questions to the reboot: 14m 48s.

`install.sh`'s sections, from the same run:

| Section | Time |
| --- | --- |
| Required packages | 13s |
| Recommended packages | 1m 25s |
| Optional extras and gaming | 7m 45s |
| mybash | 1s |
| Wallpapers | 5s |
| Display manager (LightDM) | 3s |
| yay | 4s |
| Build (make clean; make) | 2s |
| make install-system | 2s |
| GRUB theme | 1s |
| Everything else | 0s each |

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
