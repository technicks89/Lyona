# ARCH-002: LUKS through to the desktop

The wizard with btrfs in LUKS, under UEFI, from an image built from `main`, to
a working desktop. Run A (`arch001-archinstall-4.5.md`) took an encrypted
install only as far as archinstall and a login prompt, without postinstall.

## Image

The image of the legacy BIOS run (`arch004-legacy-bios.md`): built from `main`
at `2b7d9cc`, stamped `2026.10.0-beta.6`, SHA-256
`1237d292fe1a2b0b3c2b196ce1593ee72e1ba3021f0adcf201194286880c924a`,
archinstall 4.5-1 and linux 7.2.11.arch1-1. It is not the published beta.6
image.

## Machine

QEMU 11.1.2 with KVM, q35, x86_64, UEFI (OVMF, fresh variables), 4 GiB, a
40 GiB virtio disk, a standard VGA adapter, no NVIDIA GPU, user-mode
networking. The image was booted from an emulated CD, unmodified.

## Run F, 2026-10-19

The wizard was driven on screen:
- US keyboard, `/dev/vda`, "btrfs + LUKS encryption", an encryption
  passphrase entered and confirmed.
- User `tester`, hostname `lyona`.
- The online timezone lookup declined, UTC chosen.
- The worldwide mirrors.

Its summary showed "Filesystem: btrfs (LUKS encrypted)", "Boot: UEFI (GRUB)"
and "NVIDIA driver: not needed (no NVIDIA GPU detected)".

| Step | Result |
|---|---|
| Install | archinstall, then `lyona-postinstall.sh`, finished and rebooted with no manual help, in under 9 minutes |
| Boot | GRUB from the disk, then the initramfs asked for the passphrase for `/dev/vda2`. With it, the system booted to LightDM |
| Session | Logged in as `tester`. dwm and the managed shell came up, the launcher listed 17 applications, and the Control Center opened and showed `2026.10.0-beta.6` |
| System | `/sys/firmware/efi` present. GPT, FAT `/boot` (512 MiB), `vda2` `crypto_LUKS` with btrfs `/` inside, opened as `root`. `cryptdevice=UUID=...:root` on the kernel command line, and `encrypt` in the initramfs hooks. Kernel `7.2.11-1-cachyos`. `lightdm` and `NetworkManager` active. zram swap, plus the 2 GiB `/opt/swap/swapfile` that postinstall creates, inside the encrypted volume. PipeWire serving PulseAudio clients (1.6.9) |

## Not covered here

ext4 in LUKS, LUKS under legacy BIOS, a keyboard layout other than US at the
passphrase prompt, Wi-Fi installs, real hardware and NVIDIA.
