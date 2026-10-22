# ARM2-02: the aarch64 live medium

ARM Sprint 2 item ARM2-02 (issue #8). Run 2026-10-22, after the ARM2-01 spike
(`docs/evidence/arm2-01-spike.md`), on the same build host and virtual
machine.

## What changed

- `scripts/build-lyona-arch-iso.sh --arch aarch64` (the default stays
  `x86_64`, unchanged). It refuses a build for another architecture than the
  host's before anything else (ARM64.md A-3), and a `releng` without aarch64
  support, as before archiso 91 (A-2). `LYONA_MKARCHISO` names the
  `mkarchiso` to run, as Arch Linux ARM does not package archiso.
- On aarch64 the builder changes releng as the spike did, each change checking
  the shape it edits, so a new releng fails the build rather than the image:
  UEFI only (`bios.syslinux`, the syslinux directory and the memtest entry
  removed), `-Xbcj arm64`, no `memdisk` hook, and `linux-aarch64` and
  `archlinuxarm-keyring` for `linux`, `linux-dtbs`, `stubble`, `edk2-shell`
  and `ghostty-terminfo`. The syslinux quieting and menu steps are x86_64 only.
- `archiso-aarch64/`: what the aarch64 medium changes. Its `packages.aarch64`
  is the `arch:iso` profile with `ARCH=aarch64`; `pacman.conf` is Arch Linux
  ARM's (`core`, `extra`, `alarm`, `aur`); and
  `airootfs/etc/pacman.d/hooks/lyona-vmlinuz-linux.hook` copies
  `/boot/Image` to `/boot/vmlinuz-linux`. The hook stays on the live medium,
  so archinstall's `pacstrap` gives the new system that copy for GRUB
  (ARM2-03). Everything else is `archiso/`'s, shared.
- `scripts/dwm-packages.sh`: `reflector` in `arch:iso` is x86_64 only. It
  ranks Arch Linux's mirrors, and is not in Arch Linux ARM; the wizard's
  mirror step there is ARM2-04's.
- The plan named a new `alarm:iso` profile. Since it was written, ARM1-02
  made the map one `arch` family gated by architecture, with no `alarm`
  family, so the aarch64 list is `arch:iso` with `ARCH=aarch64`.

## Tests

`tests/test-arch-iso-builder.sh` (`make check-archiso`):
- `archiso-aarch64/packages.aarch64` stays in sync with the map, without
  `reflector`.
- `--arch` is validated, a build for another architecture is refused, and so
  is a releng from before archiso 91.
- An aarch64 releng fixture, shaped as archiso 91 ships it, stages with every
  change above. That includes a `bootmodes` array that is still valid and is
  `uefi.systemd-boot` alone, and the kernel-name hook kept on the medium. The
  rest is checked to be the x86_64 medium's: the quiet boot, no menu, the
  rebranding, the splash, the installer on tty1, the release stamp and the
  executable bits.
- Four releng shapes that changed (no `-Xbcj x86,arm64`, no `memdisk`, no
  `linux`, no `uefi.systemd-boot`) each fail the staging with their reason.
- The root check now runs for the host's own architecture, so it holds on the
  aarch64 CI job too.

`tests/test-arch-packages.sh`: `reflector` is gated on aarch64, and the
x86_64 medium keeps it.

The fixture caught one bug before any image was built: the hook's first
comment quoted releng's removal marker while explaining that the hook had
none. releng's `zzzz99` hook matches that text anywhere in a file, so it
would have deleted the hook from the medium. The test checks for the text.

Run on aarch64 in the Arch Linux ARM CI container (two pinned cores):
`check-archiso`, `check-arch-packages` and `check-ci-parity` passed.
shellcheck 0.10.0 (`-S warning`, as the Makefile) and shfmt 3.10.0 were clean
on the changed scripts. Not run here: `check-archiso` on x86_64, which the
Full suite's x86_64 job runs.

## The image

| | |
| --- | --- |
| Build | `scripts/build-lyona-arch-iso.sh --arch aarch64` as root in a privileged Arch Linux ARM container on GB10, with archiso v91's `mkarchiso` and `releng` (`LYONA_MKARCHISO`, `LYONA_RELENG_DIR`): exit 0 in 182 s, with a warm package cache |
| Image | `lyona-2026.10.0-beta.6-aarch64.iso`, 1,436,809,216 bytes, SHA-256 `0b3af28ca016c824a287319c54d51f11469f1121a5f2096c87c90c4593d2a1a3` |
| Contents | SquashFS `Filters selected: arm64`; `/etc/pacman.d/hooks/` holds only `lyona-vmlinuz-linux.hook` (releng's build hooks were removed); the lyona splash theme, `/usr/local/bin/lyona-install` and `/etc/lyona-iso-release` are present |
| Warnings | only the expected ones: no `stubble` (no merged device trees), the microcode hook skipped on aarch64, and the volume label being too long for Joliet, as on x86_64 |
| Machine | QEMU 8.2.2 with KVM, `virt`, 8 vCPUs on the Cortex-X925 cluster, 8 GiB, the ISO as a USB stick, AAVMF without Secure Boot, fresh firmware variables |
| Result | it booted to the wizard on tty1 (the keyboard-layout step, in the lyona console palette) within 25 s, with no command typed, and no SquashFS error |

`LYONA_ISO_COMMIT` was `unknown` in that build's stamp: the checkout was
copied into the container, where root's `git` refuses a repository another
user owns. On a host where the maintainer runs the builder with `sudo`, git
accepts it. An aarch64 build in CI must make sure the stamp gets the commit.

## Not tested

- UTM and Parallels: no Mac is available. The acceptance asks for all three
  machines; only QEMU/KVM was run.
- The boot splash: screenshots every 5 s missed it (one frame showed the
  display handover, the next the wizard), so whether Plymouth drew on
  virtio-gpu is not shown.
- Installing from the medium, which is ARM2-03 (its known gaps:
  `docs/evidence/arm2-01-spike.md`), and the wizard's steps past the first.
- Building on a GitHub arm64 runner (A-3's CI half).
- Real hardware and Secure Boot.
