# ARM Sprint 3 -- Raspberry Pi 4 and Pi 5

Index: [`ARM64.md`](ARM64.md). Depends on ARM-1; independent of ARM-2.

**Status:** planned 2026-10-11. **Done 2026-11-05:** ARM3-06 validated the
image on a real Pi 4 (4 GB, SD card)
([`docs/evidence/arm3-06-raspberry-pi.md`](../evidence/arm3-06-raspberry-pi.md)).
The image was built on that Pi from `main` (`51a72b9`). It showed the splash
and went through the first boot to LightDM with no manual step, with Picom
off at login on V3D 4 (#32). Its update and rollback worked, but the update
installed upstream Lyona (#53, which the merge resolves). The fixes it found
are in `28480a5`: Suspend hidden where the system cannot suspend, the image's
commit stamp, and Bluetooth's name on the first boot. The Pi 5 (Picom on),
`install.sh` on Arch Linux ARM's own image, Wi-Fi alone, and the overview
with 30 windows were reported working, not recorded. Not tested: NVMe on the
Pi 5 and two displays on a Pi 4; there is no hardware for them, and none will
be bought. A-5 decided 2026-10-26 (one image,
`linux-rpi`). ARM3-01 built 2026-10-26
([`docs/evidence/arm3-01-pi-image-builder.md`](../evidence/arm3-01-pi-image-builder.md)),
and ARM3-02 on the same branch
([`docs/evidence/arm3-02-pi-first-boot.md`](../evidence/arm3-02-pi-first-boot.md)):
the image's first boot reached the desktop in a KVM virtual machine, and on
a Pi 4 in a smoke boot on 2026-10-27 (not ARM3-06's run), which found the
install profile not recorded (F-7, fixed since). ARM3-02 also gave the image `quiet loglevel=3` and the root by
PARTUUID in `cmdline.txt`, which are ARM3-03's file. ARM3-03 built 2026-10-27
([`docs/evidence/arm3-03-pi-boot.md`](../evidence/arm3-03-pi-boot.md)):
`config.txt`'s includes of `lyona.txt` and `custom.txt`, and the splash;
its boot on the Pi 4 is ARM3-06's run. ARM3-05 built 2026-10-27
([`docs/evidence/arm3-05-pi-settings.md`](../evidence/arm3-05-pi-settings.md)):
System Information's Board and Processor temperature rows, and "Not
supported" for what a machine lacks; the panes on a Pi are ARM3-06's run.
Validated on a Pi 4, and, since one arrived on 2026-10-27, on an 8 GB Pi 5
from an SD card (there was none on 2026-10-25); the Pi 5's NVMe boot is not tested,
as there is no NVMe board. The image keeps what the Pi 5 needs (the kernel
and the firmware's device trees boot both boards, and its PCIe is on). GitHub: issues #12 to #17
(label `arm64`); milestone "ARM Sprint 3 - Raspberry Pi 4 and 5", created by
[`arm-sprints-github.sh`](arm-sprints-github.sh).

**Goal:** one ready-to-boot image (A-5) that a user writes to an SD card or
NVMe drive, which boots a Pi 4 or a Pi 5 into a first-boot wizard and then a
working Lyona desktop, within the lean budget.

A Pi has no installer image in the PC sense: the firmware boots a fixed FAT
partition, and Arch Linux ARM ships a root filesystem per board, not an
installer. So the Pi image is the installed system itself, minus the user,
with the wizard's questions asked at first boot.

| Item | Kind | Gate |
| --- | --- | --- |
| [ARM3-01](#arm3-01-the-pi-image-builder) | Feature | A-3, A-5 |
| [ARM3-02](#arm3-02-the-first-boot-wizard) | Feature | ARM3-01 |
| [ARM3-03](#arm3-03-pi-boot-configuration-and-kernel) | Feature | ARM3-01 |
| [ARM3-04](#arm3-04-the-desktop-on-v3d) | Measurement, fix | ARM3-01, a Pi 4 |
| [ARM3-05](#arm3-05-settings-on-a-pi) | Fix | ARM1-04 |
| [ARM3-06](#arm3-06-validate-on-a-real-pi-4) | Validation | ARM3-01 to ARM3-05, hardware |

---

## ARM3-01: The Pi image builder

1. **Script.** A new builder (for example `scripts/build-lyona-rpi-image.sh`),
   run on the aarch64 build host (A-3). It makes a disk image file with a FAT
   boot partition and a root partition, `pacstrap`s the dependency map's
   `rpi-image` profile from Arch Linux ARM's signed repositories, and in a
   chroot installs Lyona with `install.sh` for the full profile, as the
   image postinstall does, as a temporary build user it then removes. The
   per-user half of the install is left for the first boot (ARM3-02), from a
   copy of the source at `/usr/local/src/lyona`.

   Changed 2026-10-26: the plan first unpacked Arch Linux ARM's Pi tarball,
   which is a moving `latest` file over HTTP, with only an MD5 and a
   signature, and ships `linux-aarch64`, U-Boot and the default `alarm` and
   `root` passwords, all of which the image would remove. It also named the
   recommended profile, which installs no display manager.
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

## ARM3-02: The first-boot wizard

1. **Reuse** the image wizard's questions and UI (`lyona-ui.sh`): keymap,
   user and password, hostname, timezone (opt-in lookup), locale, and Wi-Fi
   when there is no Ethernet (`lyona-wifi.sh`). No disk or filesystem
   question: the system is already on its disk. (Built 2026-10-26: the
   locale is en_US.UTF-8, as on the install medium, which does not ask; Wi-Fi
   goes through NetworkManager, which the Pi runs, not iwd.)
2. **First boot:** grow the root partition and filesystem to the card or
   drive, generate the machine-id and SSH host keys, initialise the pacman
   keyring, then the wizard on the console, then LightDM.
3. **Once only:** the wizard's unit removes itself when it finishes; an
   interrupted wizard starts again at the next boot, with nothing half-made.
4. **Tests** with stubs, as the image installer's are.

**Acceptance:** a stubbed first boot creates the user, sets each answer and
disables itself.

## ARM3-03: Pi boot configuration and kernel

1. **Kernel** under A-5: Arch Linux ARM's `linux-rpi`, which boots both
   boards with the firmware's device trees. The Pi 5's 16K-page kernel was to be
   measured too; it is not measured (a Pi 5 arrived 2026-10-27, after this
   build), and the image keeps `linux-rpi`.
2. **`config.txt`:** the KMS display driver (`vc4-kms-v3d`), HDMI hotplug, and
   only what the desktop needs; documented, and kept apart from any line a
   user adds.
3. **Boot splash:** the Lyona Plymouth theme, as on x86_64, if it works on the
   Pi's KMS console; otherwise the quiet text boot.
4. **NVMe on the Pi 5** should boot the same image; it is not tested (no
   NVMe board, 2026-10-27). The Pi 5 boots from an SD card in ARM3-06.

**Acceptance:** the Pi 4 boots the image to the wizard from SD. The Pi 5,
from SD and from NVMe, is not tested.

**Built 2026-10-27** ([`docs/evidence/arm3-03-pi-boot.md`](../evidence/arm3-03-pi-boot.md)):
`linux-rpi` as A-5 decided (1); the package's `config.txt` kept, with
`include lyona.txt` and `include custom.txt` at its end, lyona's settings in
`rpi/lyona.txt` (`dtparam=audio=on`, `disable_splash=1`, `[pi5]
dtparam=pciex1`) and the user's in `custom.txt`, which wins (2); the lyona
Plymouth splash as on x86_64, with `vc4` named in `MODULES` so the initramfs
built on a host that is no Pi has the display driver, and `splash
plymouth.ignore-serial-consoles` on the command line (3); the Pi 5's PCIe
turned on for NVMe, untested (4). Whether the splash shows on the Pi 4's KMS
console is checked in ARM3-06; if not, removing `splash` from `cmdline.txt`
is the quiet text boot.

## ARM3-04: The desktop on `v3d`

The Pi 4's VideoCore VI is the slowest GPU Lyona will support. The lean goal
(`AGENTS.md`, and the CPU and GPU check of #244) is measured there first.

1. **Picom.** Measure idle and active CPU and GPU with the GLX backend and
   with XRender on a Pi 4 (the Pi 5 is not measured). Set the automatic backend choice for
   `v3d` from the numbers.
2. **The overview's previews.** Measure opening the overview with 10 and 30
   windows. If previews are too slow on a Pi 4, the overview uses icon cards
   there by default, with the setting to turn previews on.
3. **Idle.** CPU and memory with the launcher closed, on a 4 GB Pi 4, against
   the x86_64 numbers.
4. **Record** the measurements in the sprint's evidence; any default changed
   for the Pi is written in the user docs.

**Already found (#32, 2026-10-15):** on the Pi 4's V3D 4, Picom made the
desktop unusable with both backends it can run. Since 2026-10-21, the
Automatic policy leaves it off at login there (`dwm-settings-picom
session-start`), so the overview shows its cards. Check that on the Pi 4. Whether the
Pi 5's V3D 7 needs the same can be measured on the 8 GB Pi 5 (since 2026-10-27).

**Acceptance:** the desktop is usable on a 4 GB Pi 4 by the numbers recorded,
and its idle cost is within the budget the sprint sets from them.

## ARM3-05: Settings on a Pi

1. **System Information** names the board (from the device tree, ARM1-04)
   and shows the SoC temperature.
2. **Not on a Pi:** suspend and hibernate, firmware and boot entries,
   backlight on an HDMI display. Each is hidden or explained, never an error.
3. **Updates.** `lyona-update` and the package updates work as on x86_64;
   kernel updates do not need a bootloader step on a Pi.

**Acceptance:** every Settings pane opens on a Pi without an error, and what a
Pi cannot do is hidden or explained.

Built 2026-10-27 (`docs/evidence/arm3-05-pi-settings.md`): the Board and
Processor temperature rows, left out where a machine has neither, and Secure
Boot explained without UEFI. Suspend and the lid already follow logind and
UPower, Settings offers no hibernate, firmware, boot-entry or backlight
control, and updates have no bootloader step, so those needed no change.
The acceptance is checked on a Pi in ARM3-06.

## ARM3-06: Validate on a real Pi 4

1. **Hardware:** a Pi 4 (4 GB), with an HDMI display, keyboard and mouse;
   Ethernet and Wi-Fi. A Pi 5 (8 GB) too, since 2026-10-27, from an SD card; its
   NVMe boot is not tested, as there is no NVMe board.
2. **Run:** write the image, first boot, wizard, log in, the checks of
   ARM1-06, the ARM3-04 measurements, a reboot, an update and a rollback.
3. **Record** in `docs/evidence/arm3-06-raspberry-pi.md`: board and memory,
   boot medium, image checksum, kernel, display, and what was not tested (the
   Pi 5's NVMe boot, two displays on a Pi 4, other boards).

**Acceptance:** the Pi 4 reaches a working desktop from the image with no
manual step.

**Also, from ARM1-06 (moved here 2026-10-19):** ARM1-06 was validated in an
Arch Linux ARM VM on GB10, because the Pi 4 was not available. On the Pi 4,
also run `install.sh` on Arch Linux ARM's own Raspberry Pi image, for the
recommended and full profiles. Answer the installer's NetworkManager question,
and use `sudo` with a password. Then repeat ARM1-06's checks on `v3d`, with
Picom's glx backend, the board's Wi-Fi, Bluetooth and HDMI audio, and the idle
cost. Record it in `docs/evidence/arm1-06-install-sh.md`, under a Raspberry Pi
section beside the VM run.

---

## Not in this sprint

Other ARM boards (Rock, Orange Pi, Pinebook), 32-bit Pi models, and the
Pi 3 or older. They need their own kernels and are outside the project unless
added later.
