# ARCH-001/ARCH-002: the wizard and the manual fallback

The first installs of an image built by the release workflow, through the
wizard and through the manual `archinstall` fallback, both to the desktop.
Runs A and B (`docs/evidence/arch001-archinstall-4.5.md`) covered the new
archinstall configuration through archinstall and first boot only.

## Image and machine

- **Image:** the release workflow's `lyona-2026.10.0-beta.6-x86_64.iso`,
  SHA-256 `1c1722b6d0b6cd400e45d09a8fddaa571598e17343b119b0505d41ae4ef13a84`,
  verified against the release's `SHA256SUMS`, used unmodified. It carries
  archinstall 4.5-1 and linux 7.2.9.arch1-1. It is not the image the
  2026-10-09 qualification built on the maintainer's host (`9956f9f1...`).
- **Machine:** QEMU 11.1.2 with KVM, q35, x86_64, UEFI (OVMF), 4 GiB, a
  40 GiB virtio disk, a standard VGA adapter, no NVIDIA GPU, user-mode
  networking.

## VM runs, 2026-10-19

| Run | Path | Result |
|---|---|---|
| C | The wizard, booted from the CD and driven on screen: btrfs, no encryption, the online timezone lookup declined (UTC chosen), the default worldwide mirrors | archinstall, then `lyona-postinstall.sh`, in 3m 28s with no manual help. The system rebooted to LightDM; dwm and the managed shell came up, the launcher listed 17 applications, and the Control Center showed `2026.10.0-beta.6` |
| D | The manual fallback: `archinstall --config --creds` from the live root shell with a plain configuration (stock `linux`, ext4, GRUB, NetworkManager, PipeWire, no `[multilib]`), then `/root/lyona-postinstall.sh` against the mounted target | Postinstall completed. It reported the gaming packages skipped because `[multilib]` was not enabled, and how to enable it, which is correct. The system booted to LightDM, the desktop and the Control Center |

## Not covered here

- Run C used the beta.6 image's own archinstall configuration, the one before
  #418 moved it to archinstall 4.5's current forms. The new configuration was
  run through archinstall and first boot (runs A and B), not yet through
  postinstall to the desktop.
- Run D wrote its configuration as a file, so archinstall's own menu screens
  were not driven by hand.
- Legacy BIOS to the desktop, LUKS to the desktop, Wi-Fi installs, real
  hardware and NVIDIA.
