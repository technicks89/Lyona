# ARM Sprint 3 -- Raspberry Pi 4 and Pi 5

Index: [`ARM64.md`](ARM64.md). Depends on ARM-1; independent of ARM-2.

**Status:** planned 2026-10-11. Not started.

**Goal:** one ready-to-boot image (A-5) that a user writes to an SD card or
NVMe drive, which boots a Pi 4 or a Pi 5 into a first-boot wizard and then a
working Lyona desktop, within the lean budget.

A Pi has no installer image in the PC sense: the firmware boots a fixed FAT
partition, and Arch Linux ARM ships a root filesystem per board, not an
installer. So the Pi image is the installed system itself, minus the user,
with the wizard's questions asked at first boot.

| Item | Kind | Gate |
| --- | --- | --- |
| [S3-01](#s3-01-the-pi-image-builder) | Feature | A-3, A-5 |
| [S3-02](#s3-02-the-first-boot-wizard) | Feature | S3-01 |
| [S3-03](#s3-03-pi-boot-configuration-and-kernel) | Feature | S3-01 |
| [S3-04](#s3-04-the-desktop-on-v3d) | Measurement, fix | S3-01, a Pi 4 |
| [S3-05](#s3-05-settings-on-a-pi) | Fix | ARM-1 S1-04 |
| [S3-06](#s3-06-validate-on-a-real-pi-4-and-pi-5) | Validation | S3-01 to S3-05, hardware |

---

## S3-01: The Pi image builder

1. **Script.** A new builder (for example `scripts/build-lyona-rpi-image.sh`),
   run on the aarch64 build host (A-3). It makes a disk image file with a FAT
   boot partition and a root partition, unpacks Arch Linux ARM's Raspberry Pi
   aarch64 root filesystem (its checksum and signature checked), and in a
   chroot installs Lyona with `install.sh` for the recommended profile, as the
   image postinstall does.
2. **Nothing personal in the image:** no user, no SSH host keys, no
   machine-id, an empty pacman cache, the keyring initialised at first boot
   rather than shipped.
3. **Output:** a compressed image with its checksum, written with
   `dd`, Raspberry Pi Imager or balenaEtcher; its size kept small enough for
   an 8 GB card, with the root partition grown at first boot.
4. **Tests.** A static test like `check-archiso`: the builder's steps, that
   nothing personal is left in the image, and that its package list comes
   from the dependency map.

**Acceptance:** the builder produces an image whose root filesystem passes
the static checks.

## S3-02: The first-boot wizard

1. **Reuse** the image wizard's questions and UI (`lyona-ui.sh`): keymap,
   user and password, hostname, timezone (opt-in lookup), locale, and Wi-Fi
   when there is no Ethernet (`lyona-wifi.sh`). No disk or filesystem
   question: the system is already on its disk.
2. **First boot:** grow the root partition and filesystem to the card or
   drive, generate the machine-id and SSH host keys, initialise the pacman
   keyring, then the wizard on the console, then LightDM.
3. **Once only:** the wizard's unit removes itself when it finishes; an
   interrupted wizard starts again at the next boot, with nothing half-made.
4. **Tests** with stubs, as the image installer's are.

**Acceptance:** a stubbed first boot creates the user, sets each answer and
disables itself.

## S3-03: Pi boot configuration and kernel

1. **Kernel** under A-5: Arch Linux ARM's `linux-rpi`, which boots both
   boards with the firmware's device trees. Measure the Pi 5 with the 16K-page
   kernel as well; switch only if it is clearly better and nothing in the
   desktop breaks.
2. **`config.txt`:** the KMS display driver (`vc4-kms-v3d`), HDMI hotplug, and
   only what the desktop needs; documented, and kept apart from any line a
   user adds.
3. **Boot splash:** the Lyona Plymouth theme, as on x86_64, if it works on the
   Pi's KMS console; otherwise the quiet text boot.
4. **NVMe on the Pi 5** boots the same image.

**Acceptance:** both boards boot the same image to the wizard, from SD, and
the Pi 5 from NVMe.

## S3-04: The desktop on `v3d`

The Pi 4's VideoCore VI is the slowest GPU Lyona will support. The lean goal
(`AGENTS.md`, and the CPU and GPU check of #244) is measured there first.

1. **Picom.** Measure idle and active CPU and GPU with the GLX backend and
   with XRender on a Pi 4 and a Pi 5. Set the automatic backend choice for
   `v3d` from the numbers.
2. **The overview's previews.** Measure opening the overview with 10 and 30
   windows. If previews are too slow on a Pi 4, the overview uses icon cards
   there by default, with the setting to turn previews on.
3. **Idle.** CPU and memory with the launcher closed, on a 4 GB Pi 4, against
   the x86_64 numbers.
4. **Record** the measurements in the sprint's evidence; any default changed
   for the Pi is written in the user docs.

**Acceptance:** the desktop is usable on a 4 GB Pi 4 by the numbers recorded,
and its idle cost is within the budget the sprint sets from them.

## S3-05: Settings on a Pi

1. **System Information** names the board (from the device tree, ARM-1 S1-04)
   and shows the SoC temperature.
2. **Not on a Pi:** suspend and hibernate, firmware and boot entries,
   backlight on an HDMI display. Each is hidden or explained, never an error.
3. **Updates.** `lyona-update` and the package updates work as on x86_64;
   kernel updates do not need a bootloader step on a Pi.

**Acceptance:** every Settings pane opens on a Pi without an error, and what a
Pi cannot do is hidden or explained.

## S3-06: Validate on a real Pi 4 and Pi 5

1. **Hardware:** a Pi 4 (4 GB) and a Pi 5, each with an HDMI display,
   keyboard and mouse; Ethernet and Wi-Fi.
2. **Run:** write the image, first boot, wizard, log in, the checks of ARM-1's
   S1-06, the S3-04 measurements, a reboot, an update and a rollback.
3. **Record** in `docs/evidence/arm-s3-06-raspberry-pi.md`: board and memory,
   boot medium, image checksum, kernel, display, and what was not tested (for
   example two displays on a Pi 4, or other boards).

**Acceptance:** both boards reach a working desktop from the same image with
no manual step.

---

## Not in this sprint

Other ARM boards (Rock, Orange Pi, Pinebook), 32-bit Pi models, and the
Pi 3 or older. They need their own kernels and are outside the project unless
added later.
