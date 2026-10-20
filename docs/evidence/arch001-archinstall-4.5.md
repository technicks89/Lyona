# ARCH-001: archinstall 4.5

What validated the image installer's archinstall configuration against
archinstall 4.5, which Arch has shipped since 2026-09-29 (`4.5-1`) and which
the `2026.10.0-beta.6` image carries.

## The change

`archiso/airootfs/root/lyona-install.sh` was written for archinstall 4.4. A
reading of archinstall's own source, 4.4 against 4.5, found every key and
value it writes still parsed the same way, with nothing newly required. Two
keys were on 4.5's backwards-compatibility paths, though, and three had no
effect at all, so the configuration moved to the current forms:

- `disk_encryption` moved from the top level into `disk_config`. 4.5 reads it
  there (`DiskLayoutConfiguration.parse_arg`); the top-level form is marked
  "DEPRECATED / backwards compatibility" in `archinstall/lib/args.py`.
- `audio_config` moved under `app_config`. The top-level form is likewise
  only read for backwards compatibility.
- `debug`, `offline` and `no_pkg_lookups` were removed. archinstall reads them
  only as command-line flags, never from the configuration file.
- `version` is `4.5`. archinstall overwrites it after parsing.

archinstall 4.4 already read both new forms, so the change does not depend on
4.5. `tests/test-arch-iso-builder.sh` now fails if a deprecated top-level key
comes back, and checks that the audio server is PipeWire.

## VM runs, 2026-10-19

- **Image:** the release workflow's `lyona-2026.10.0-beta.6-x86_64.iso`,
  SHA-256 `1c1722b6d0b6cd400e45d09a8fddaa571598e17343b119b0505d41ae4ef13a84`,
  verified against the release's `SHA256SUMS`. It carries archinstall 4.5-1
  and linux 7.2.9.arch1-1. Its `lyona-install` was replaced with this branch's
  copy.
- **Machine:** QEMU with KVM, q35, x86_64, 4 GiB, a 40 GiB virtio disk, a
  standard VGA adapter, no NVIDIA GPU. The live medium was booted directly
  (kernel and initramfs from the image) with a serial console.
- **How:** the installer was sourced with `LYONA_INSTALL_LIB=1`, the wizard's
  answers set, and its own steps run in order: `detect_firmware`,
  `use_parallel_downloads`, `rank_mirrors`, `setup_cachyos_repositories`,
  `generate_configs`, then `archinstall --config --creds --silent
  --skip-version-check`. The wizard's questions and `lyona-postinstall.sh` were
  not part of these runs.

| Run | Firmware | Root | archinstall | Result |
|---|---|---|---|---|
| A | UEFI (OVMF) | btrfs in LUKS | exit 0, "Installation completed without any errors" | GPT disk, FAT `/boot`, `vda2` LUKS with btrfs inside, `encrypt` hook, GRUB. Booted: passphrase prompt, then `linux-cachyos` 7.2.7 to a login |
| B | Legacy BIOS (SeaBIOS) | ext4 | exit 0, "Installation completed without any errors" | DOS disk, ext4 `/boot`, GRUB `i386-pc`. Booted to a login on `linux-cachyos` 7.2.7 |

On both systems the user from `creds.json` logged in, was in `wheel` with
`(ALL) ALL` sudo, zram swap was on, NetworkManager was active, and the
PipeWire stack (`pipewire`, `wireplumber`, `pipewire-pulse`) was installed
through `app_config`. The CachyOS repositories were configured and the
CachyOS kernel installed. Its signing key is trusted later, by
`lyona-postinstall.sh` (`pacman-key --populate cachyos`), so `pacman` warns
about it until then.

## Not covered here

The wizard's own questions, `lyona-postinstall.sh` and the desktop, the manual
`archinstall` fallback, real hardware and NVIDIA. The wizard and the fallback
were run to the desktop the same day: the wizard with the image's own
configuration, the fallback with a plain configuration of its own
(`docs/evidence/arch001-wizard-fallback.md`).
