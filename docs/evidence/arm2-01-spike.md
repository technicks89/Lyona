# ARM2-01: builder and installer spike

ARM Sprint 2 item ARM2-01 (issue #7). Run 2026-10-22. It answers decisions
A-2, A-3 and A-4 (`docs/sprints/ARM64.md`). Nothing under `archiso/` or
`scripts/` changed: the profile below was staged outside the repository, as
the sprint plan keeps the real profile for ARM2-02.

## The machines

| | |
| --- | --- |
| Build host | NVIDIA GB10 (DGX Spark), its Ubuntu 24.04 based OS, kernel 7.0.0-1019-nvidia. The build ran natively in a privileged Docker container of Arch Linux ARM (`lyona-archlinuxarm:base-devel`, `pacman -Syu` first: pacman 7.1.0, systemd 262.1) |
| Builder | archiso **v91** (2026-09-27), `mkarchiso` from the upstream Git tag, unpatched; `mkinitcpio-archiso` 73-1 from Arch Linux ARM |
| Virtual machine | QEMU 8.2.2 with KVM, `virt` machine, 8 vCPUs (`-cpu host`) pinned to the Cortex-X925 cluster, 8 GiB, the ISO as a USB stick (`usb-storage` on `qemu-xhci`), a blank 32 GiB virtio-blk disk, virtio-gpu, user-mode virtio network |
| Firmware | UEFI: AAVMF (`qemu-efi-aarch64` 2024.02-2ubuntu0.10), `AAVMF_CODE.no-secboot.fd`, no Secure Boot |
| Kernel | `linux-aarch64` 7.2.11-1 (7.2.11-1-aarch64-ARCH) |

Not tried: UTM and Parallels (no Mac is available), a GitHub arm64 runner as
the build host, real hardware, Secure Boot, and an encrypted install.

## 1. archiso on aarch64

archiso is **not packaged in Arch Linux ARM**, so `mkarchiso` ran from the v91
source tree. v91 knows aarch64: it maps `aarch64` to the UEFI architecture
`AA64`, builds GRUB's `arm64-efi`, has `kernel_params_aarch64`, and its releng
profile has a `packages.aarch64`. That list is written for Arch Linux's own
aarch64 port (`linux`, `linux-dtbs`, `stubble`), which had no public
repositories on 2026-10-22 (`geo.mirror.pkgbuild.com/core/os/aarch64/` and
`archlinux.org/packages/core/aarch64/linux/` returned 404; the only ISO was
x86_64). Arch Linux ARM stays the base (A-1).

The spike profile is releng v91 with six changes (the staging script is in
the appendix):

| Change | Why |
| --- | --- |
| `bootmodes=('uefi.systemd-boot')`, no syslinux, no memtest entry | No BIOS on aarch64. `systemd-bootaa64.efi` is in Arch Linux ARM's `core/systemd` |
| `linux-aarch64` instead of `linux` and `linux-dtbs`; no `stubble`, `edk2-shell`, `ghostty-terminfo` | The five packages releng's aarch64 list names that Arch Linux ARM lacks (of 119). `linux-aarch64` carries `/boot/dtbs` |
| Arch Linux ARM's `pacman.conf` (`core`, `extra`, `alarm`, `aur`) and `archlinuxarm-keyring` | Its repositories and signing keys |
| A build-only pacman hook that copies `/boot/Image` to `/boot/vmlinuz-linux` | `mkarchiso` copies `/boot/vmlinuz-*` to the medium; `linux-aarch64` installs `/boot/Image` (an EFI-bootable arm64 kernel). `mkarchiso` points pacman's `HookDir` at the profile's hooks while it builds, so no archiso change is needed |
| SquashFS `-Xbcj arm64`, not releng's `x86,arm64` | See below: the first image could not be read |
| No `memdisk` in the live initramfs's `HOOKS` | syslinux's BIOS RAM-disk boot; its hook failed the initramfs build (`module not found: 'phram'`, `binary not found: 'memdiskfind'`) |

Three builds:

| Build | Changes | `mkarchiso` | Image | Boot |
| --- | --- | --- | --- | --- |
| 1 | the first four | exit 0, 225 s | 1,414,653,952 bytes | systemd-boot, kernel and archiso hooks fine, to `archiso login:`, **but 634 `SQUASHFS error` lines** |
| 2 | + `-Xbcj arm64`, no `memdisk` | exit 0, 198 s, no `mkinitcpio` errors | | to the root shell in about 40 s, 0 SquashFS errors |
| 3 | + the hook marked for removal (below) | exit 0, 198 s | 1,415,192,576 bytes, SHA-256 `e8dc2c12b8585928180dc2cd93c21737db508157fd8809e905cbb442f65b7f4e` | as build 2; no custom pacman hook on the live system |

The image is 435 packages: releng's live system, not the desktop.

**The SquashFS errors (build 1).** Every error was `xz decompression failed,
data probably corrupt`, for the same few blocks, after `Copying rootfs image
to RAM`, so not a USB read fault. `unsquashfs` extracted the whole image
without an error (`Filters selected: x86, arm64`), and `linux-aarch64`'s
configuration has `CONFIG_XZ_DEC_ARM64=y` but `# CONFIG_XZ_DEC_X86 is not
set`. `mksquashfs` picks the filter that compresses each block best, so every
block it gave the x86 filter was unreadable on the booted system. The image
still reached a login prompt, with those files broken. An aarch64 image must
use `-Xbcj arm64` alone.

**The hook leak (build 2).** releng's `zzzz99` hook removes only the build
hooks that contain the text `remove from airootfs`. Without it, the
`Image`-to-`vmlinuz-linux` hook stayed on the live system, and archinstall's
`pacstrap` ran it for the new system too (section 3). Build 3 adds the
marker.

**Mirrors.** `mirror.archlinuxarm.org` failed three times in the day: two
package downloads in a build (`Operation too slow`) and one database sync in
archinstall (`failed to synchronize all databases`). A retry worked each
time. A package cache mounted into the build container avoids downloading the
435 packages again. ARM2-04 (mirrors) should keep this in view.

**Answer: yes on QEMU/KVM.** archiso v91 builds a working aarch64 UEFI image on
Arch Linux ARM, unpatched, with a profile of Lyona's own. UTM and Parallels
are untested.

## 2. mkosi

Not tried: the plan tries mkosi (and archboot as a reference) only if archiso
fails. `mkosi` 14 is in Arch Linux ARM's `extra` if A-2 is ever revisited.

## 3. archinstall on Arch Linux ARM

The medium has `archinstall` 4.5 from Arch Linux ARM. The configuration was
the x86_64 image's own: `generate_configs` and `write_credentials_json` from
`archiso/airootfs/root/lyona-install.sh` (lines 819-950, unchanged), with the
answers `DISK=/dev/vda`, UEFI, ext4, no encryption, `kernels: ["linux"]`,
GRUB (`removable: true`), `multilib`, NetworkManager, zram swap. It ran as
`run_archinstall` runs it: `archinstall --config --creds --silent
--skip-version-check`.

| Run | archinstall | `/boot` | GRUB's entries | First boot |
| --- | --- | --- | --- | --- |
| Build 2's medium (the leaked hook) | exit 0, about 2 min | `Image`, `Image.gz`, `dtbs`, `initramfs-linux.img`, `vmlinuz-linux` (identical to `Image`) | `linux /vmlinuz-linux root=UUID=...` with `initrd /initramfs-linux.img`, plus an `Image` entry | to `lyona-spike login:` (see firmware, below) |
| Build 3's medium (no leak) | exit 0 on the second try (the first lost the mirror) | `Image`, `Image.gz`, `dtbs`, `initramfs-linux.img` | **only `linux /Image root=/dev/vda2 ...`, with no `initrd`** | to `lyona-spike login:`, `BOOT_IMAGE=/Image root=/dev/vda2`; `systemd-analyze` shows kernel and userspace only, no initrd |

What archinstall did right, unpatched:
- `kernels: ["linux"]` installed `linux-aarch64`, which provides `linux`.
- GRUB went in as `arm64-efi`, `\EFI\BOOT\BOOTAA64.EFI` on the ESP.
- `multilib` appears in its log but not in the new `pacman.conf`, which has
  `core`, `extra`, `alarm` and `aur`; `pacman -Sy` works in the new system.
- NetworkManager, the user and sudo were set up.

What is wrong:
- **GRUB and Arch Linux ARM's kernel name.** GRUB's `10_linux` finds
  `/boot/Image`, but pairs an initramfs with a kernel only by its version
  name, and `linux-aarch64`'s preset writes `initramfs-linux.img`, which it
  pairs only with `vmlinuz-linux`. So the `Image` entry has no initramfs, and
  without one GRUB writes `root=/dev/vda2` instead of the UUID. It booted here
  because `linux-aarch64` builds virtio-blk and ext4 in. An encrypted root
  (the wizard's `ENCRYPT=1`) cannot be unlocked without an initramfs, and a
  device name breaks when disks are named in another order. With a
  `/boot/vmlinuz-linux` beside it (build 2), GRUB wrote the right entry, with
  the initramfs and the UUID.
- **That copy must be kept current.** In build 2 the copy came from the leaked
  hook, once; the new system had no hook, so the first `linux-aarch64` upgrade
  would leave GRUB booting the old kernel against the new modules.
- **Firmware boot entry.** archinstall installs GRUB as removable and adds no
  firmware boot entry. With the firmware variables the live session had used,
  AAVMF went to the UEFI shell after the medium was removed;
  `FS0:\EFI\BOOT\BOOTAA64.EFI` started from that shell booted the system, and
  with fresh variables it booted on its own both times.

**Answer: archinstall works unpatched for the base system**, if Lyona gives
both the medium and the new system a hook that keeps `/boot/vmlinuz-linux`
current from `/boot/Image`: on the medium (not marked for removal) so
`pacstrap` names it before archinstall runs `grub-mkconfig`, and in the new
system for every upgrade after. That is a few lines of Lyona's own, not a
change to archinstall. An encrypted install was not tried.

## 4. Decisions

| | Decision | What it costs to keep working |
| --- | --- | --- |
| **A-2** | **(a) archiso**, with an aarch64 profile of Lyona's own, layered on releng as the x86_64 image is | archiso is not in Arch Linux ARM's repositories: the builder must fetch a pinned archiso release (v91 here) and check it, or Lyona packages it. Six differences from releng to keep (above), each caught by a test in ARM2-02. Upstream's aarch64 path is written for Arch Linux's port; when that port ships, A-1 and this profile should be looked at again |
| **A-3** | **(a) a native aarch64 host**: a privileged Arch Linux ARM container on an aarch64 machine built the image in about 200 s | The Apple Silicon VM was not tried (no Mac). A GitHub arm64 runner was not tried; the build needs a privileged container (`pacstrap` mounts), which ARM2-02 should check there |
| **A-4** | **(a) archinstall, unpatched**, with Lyona's kernel-name hook on the medium and in the new system | The hook, and a test that the new system's GRUB entry has its initramfs and a `root=UUID=`. ARM2-03 still has to try an encrypted install and to add a firmware boot entry (for example with `efibootmgr`), so the firmware does not stop in its shell |

## Appendix: the staging script

Run as `stage-profile.sh RELENG_DIR OUT_DIR` on archiso v91's
`configs/releng`, then `mkarchiso -v -w WORK -o OUT OUT_DIR` as root in the
Arch Linux ARM container, after `pacman -Syu arch-install-scripts
squashfs-tools libisoburn mtools dosfstools erofs-utils mkinitcpio-archiso
grub systemd-ukify`.

```bash
#!/usr/bin/env bash
set -euo pipefail

releng=${1:?usage: stage-profile.sh RELENG_DIR OUT_DIR}
out=${2:?usage: stage-profile.sh RELENG_DIR OUT_DIR}

rm -rf -- "$out"
cp -a -- "$releng" "$out"
cd -- "$out"

# UEFI only: there is no syslinux (or BIOS) on aarch64.
sed -i "s/^bootmodes=.*/bootmodes=('uefi.systemd-boot')/; /^           'uefi.systemd-boot')/d" profiledef.sh
sed -i 's/^iso_name=.*/iso_name="lyona-arm2-01-spike"/; s/^iso_label=.*/iso_label="LYONA_ARM_SPIKE"/' profiledef.sh
rm -f efiboot/loader/entries/03-archiso-memtest86+x64.conf
rm -rf syslinux

# aarch64 kernels decompress only the ARM BCJ filters.
sed -i "s/'-Xbcj' 'x86,arm64'/'-Xbcj' 'arm64'/" profiledef.sh
grep -q "'-Xbcj' 'arm64'" profiledef.sh

# memdisk is syslinux's BIOS RAM-disk boot.
sed -i 's/ memdisk / /' airootfs/etc/mkinitcpio.conf.d/archiso.conf
! grep -q memdisk airootfs/etc/mkinitcpio.conf.d/archiso.conf

# Arch Linux ARM's kernel and the packages its repositories lack.
sed -i '/^linux$/d; /^linux-dtbs$/d; /^stubble$/d; /^edk2-shell$/d; /^ghostty-terminfo$/d' packages.aarch64
printf 'linux-aarch64\narchlinuxarm-keyring\n' >>packages.aarch64
printf 'archlinuxarm-keyring\n' >>bootstrap_packages

cat >pacman.conf <<'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = aarch64
ParallelDownloads = 5
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[alarm]
Include = /etc/pacman.d/mirrorlist
[aur]
Include = /etc/pacman.d/mirrorlist
EOF

# mkarchiso copies /boot/vmlinuz-*; linux-aarch64 installs /boot/Image.
cat >airootfs/etc/pacman.d/hooks/lyona-vmlinuz-name.hook <<'EOF'
# remove from airootfs!
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux-aarch64

[Action]
Description = Naming linux-aarch64's Image as mkarchiso expects...
When = PostTransaction
Exec = /usr/bin/cp -f /boot/Image /boot/vmlinuz-linux
EOF

grep -q 'vmlinuz-linux$' efiboot/loader/entries/01-archiso-linux.conf
```
