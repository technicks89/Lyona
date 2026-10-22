# ARM Sprint 2 -- The generic aarch64 UEFI image

Index: [`ARM64.md`](ARM64.md). Depends on ARM-1.

**Status:** planned 2026-10-11. ARM2-01 reported 2026-10-22
([`docs/evidence/arm2-01-spike.md`](../evidence/arm2-01-spike.md)): A-2, A-3
and A-4 decided. ARM2-02 built 2026-10-22
([`docs/evidence/arm2-02-live-medium.md`](../evidence/arm2-02-live-medium.md)):
the medium boots to the wizard on QEMU/KVM; UTM and Parallels are untested. GitHub: issues #7 to #11
(label `arm64`); milestone "ARM Sprint 2 - Generic aarch64 image", created by
[`arm-sprints-github.sh`](arm-sprints-github.sh).

**Goal:** an installer image for any aarch64 machine that boots UEFI, built
the way the x86_64 image is built, which installs Lyona with the same wizard
and reaches a working desktop on three virtual machines. GB10 detection
(ARM-4) and N1X (ARM-5) later reuse this image.

| Item | Kind | Gate |
| --- | --- | --- |
| [ARM2-01](#arm2-01-builder-and-installer-spike) | Spike | Reported 2026-10-22: A-2 (a), A-3 (a), A-4 (a) |
| [ARM2-02](#arm2-02-the-aarch64-live-medium) | Feature | ARM2-01 |
| [ARM2-03](#arm2-03-the-arm-installer-path) | Feature | ARM2-01, ARM2-02 |
| [ARM2-04](#arm2-04-mirrors-keyring-and-what-the-installer-skips-on-arm) | Fix | ARM2-03 |
| [ARM2-05](#arm2-05-validate-on-three-virtual-machines) | Validation | ARM2-02 to ARM2-04 |

---

## ARM2-01: Builder and installer spike

Time-boxed to the sprint's first week. It answers A-2, A-3 and A-4 with
evidence, in `docs/evidence/arm2-01-spike.md`.

1. **archiso on aarch64.** On an Arch Linux ARM build host (A-3), build a
   minimal archiso profile with an aarch64 UEFI boot mode, `linux-aarch64` and
   `archlinuxarm-keyring`. Does it boot to a shell on UTM, Parallels and
   QEMU/KVM?
2. **If not, mkosi** (and archboot as a reference for what a working aarch64
   Arch install image needs). Same three machines.
3. **archinstall on Arch Linux ARM.** Run the x86_64 image's JSON
   configuration through archinstall on the booted medium. If it works
   unpatched, A-4 is (a); otherwise (b).
4. **Report:** the chosen builder, the build host and time, the image size,
   and what each option would cost to keep working.

**Acceptance:** A-2, A-3 and A-4 decided and recorded in `ARM64.md`.

## ARM2-02: The aarch64 live medium

1. **Profile.** An aarch64 profile beside `archiso/` (for example
   `archiso-aarch64/`), sharing `airootfs/root/` with the x86_64 one where the
   files are architecture-neutral. Its package list,
   `packages.aarch64`, is the dependency map's new `alarm:iso` profile,
   kept in sync as `archiso/packages.x86_64` is with `arch:iso` (the test in
   `tests/test-arch-iso-builder.sh` is extended, not copied).
2. **Builder.** `scripts/build-lyona-arch-iso.sh` gains `--arch aarch64` (or
   an aarch64 sibling script if ARM2-01 chose a different tool), with the same
   rebranding, quiet boot, Plymouth and checks. It refuses to run on the wrong
   host architecture unless the spike proved emulation reliable (A-3).
3. **Boot.** GRUB or systemd-boot for `aa64`, whichever ARM2-01 found boots on
   all three machines. Secure Boot is out of scope, as on x86_64.
4. **Tests.** `make check-archiso` covers the aarch64 profile statically.

**Acceptance:** the image builds on the build host and boots to the wizard on
all three machines.

## ARM2-03: The ARM installer path

1. **The wizard is shared.** `lyona-install.sh`'s questions (keymap, disk,
   filesystem, user, hostname, timezone with the opt-in lookup, mirrors) stay
   one implementation; only the install step differs by architecture.
2. **Under A-4 (b),** an ARM install step replaces archinstall: partition
   (GPT, an EFI system partition and a root partition), format (ext4 or btrfs,
   the same subvolume layout as x86_64), `pacstrap` the base and
   `linux-aarch64`, `genfstab`, locale, timezone, hostname, user and sudo,
   bootloader, NetworkManager. The same Retry recovery menu and log
   (`/var/log/lyona-install.log`).
3. **The postinstall** (`lyona-postinstall.sh`) runs unchanged where it can;
   its x86_64-only steps (CachyOS, the NVIDIA prompt for PCI GPUs, Steam) are
   skipped on aarch64 by the architecture gates from ARM-1, never by a second
   copy of the script.
4. **Tests.** The installer's existing tests run against the ARM path with
   stubs, as `tests/test-iso-install-recovery.sh` does for x86_64.

**Acceptance:** the stubbed install runs end to end on both paths; the
x86_64 path's tests are unchanged.

## ARM2-04: Mirrors, keyring and what the installer skips on ARM

1. **Mirrors.** reflector ranks Arch's mirrors only. On aarch64 the mirror
   step uses Arch Linux ARM's mirrorlist (the geo-balanced
   `mirror.archlinuxarm.org`, or the country mirrors the user picks) and does
   not run reflector. The wizard's mirror question says what it does on ARM.
2. **Keyring.** `pacman-key --populate archlinuxarm` on the medium and the
   new system; the installer checks the keyring is ready before downloading,
   as the 2026-10-10 DNS diagnosis showed it should check the network.
3. **CachyOS** is never offered on aarch64.
4. **Network checks.** The name-resolution check before each download step
   (proposed after the 2026-10-10 install failure) applies on ARM too.

**Acceptance:** an install on a VM uses Arch Linux ARM's mirrors and keyring
with no warning from reflector or CachyOS in the log.

## ARM2-05: Validate on three virtual machines

1. **Machines:** UTM (QEMU backend) and Parallels on Apple Silicon; QEMU/KVM
   on an aarch64 Linux host. UEFI on all three.
2. **Run:** a fresh install with ext4 and with btrfs on each; log in; the
   checks of ARM1-06; an update from the image's release to the next
   build and a rollback (`lyona-update`).
3. **Record** in `docs/evidence/arm2-05-generic-image.md`, as
   `docs/RELEASING.md` asks of the x86_64 image: build host, image checksum,
   firmware mode, GPU and driver path (virtio-gpu, Apple's paravirtual GPU),
   and what was not tested (real ARM hardware other than the VMs' hosts).

**Acceptance:** all six installs reach a working desktop with no manual step.

---

## Not in this sprint

GB10 and N1X detection (ARM-4, ARM-5), the Raspberry Pi (ARM-3, which does
not use this image), publishing the image (ARM-5).
