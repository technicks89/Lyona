# ARCH-004: legacy BIOS through to the desktop

Qualifies legacy BIOS in a VM, the target chosen for it on 2026-10-19: the
wizard, run on SeaBIOS from an image built from `main`, to a working desktop.
It is also the first run of #418's archinstall 4.5 configuration through
postinstall to the desktop. Runs A and B (`arch001-archinstall-4.5.md`) took
that configuration only as far as archinstall and first boot.

## Image

- **Built from:** `main` at `2b7d9cc`, a clean worktree, with
  `sudo scripts/build-lyona-arch-iso.sh` on the maintainer's host (CachyOS,
  `archiso` 91-1, squashfs-tools 4.7.5). The image is stamped
  `2026.10.0-beta.6`, `main`'s `config.mk` VERSION. It is not the published
  beta.6 image.
- **File:** `lyona-2026.10.0-beta.6-x86_64.iso`, SHA-256
  `1237d292fe1a2b0b3c2b196ce1593ee72e1ba3021f0adcf201194286880c924a`.
- **Live medium:** archinstall 4.5-1, linux 7.2.11.arch1-1.

## Machine

QEMU 11.1.2 with KVM, q35, x86_64, SeaBIOS (no UEFI firmware), 4 GiB, a
40 GiB virtio disk, a standard VGA adapter, no NVIDIA GPU, user-mode
networking. The image was booted from an emulated CD, unmodified.

## Run E, 2026-10-19

The wizard was driven on screen:
- US keyboard, `/dev/vda`, ext4, user `tester`, hostname `lyona`.
- The online timezone lookup declined, UTC chosen.
- The worldwide mirrors.

Its summary detected "Boot: legacy BIOS (GRUB)" and "NVIDIA driver: not
needed (no NVIDIA GPU detected)".

| Step | Result |
|---|---|
| Install | archinstall, then `lyona-postinstall.sh`, finished and rebooted with no manual help, in under 4 minutes |
| Boot | GRUB from the disk, under SeaBIOS, to LightDM |
| Session | Logged in as `tester`. dwm and the managed shell came up, the launcher listed 17 applications, and the Control Center opened and showed `2026.10.0-beta.6` |
| System | No `/sys/firmware/efi` (booted as BIOS). DOS partition table, ext4 `/boot` (512 MiB) and `/`, GRUB `i386-pc`. Kernel `7.2.11-1-cachyos`. `lightdm` and `NetworkManager` active. zram swap, plus the 2 GiB `/opt/swap/swapfile` that postinstall creates. PipeWire serving PulseAudio clients (1.6.9) |

## Not covered here

LUKS (run under UEFI the same day, `arch002-luks-desktop.md`), Wi-Fi
installs, real hardware (BIOS or UEFI) and NVIDIA.
