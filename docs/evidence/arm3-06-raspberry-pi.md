# ARM3-06: the Raspberry Pi image on a real Pi 4

ARM Sprint 3 item ARM3-06 (issue #17), run 2026-11-04 on the maintainer's
Raspberry Pi 4. The image was built on that Pi from `main` and written to
an SD card. It booted through the first-boot wizard to LightDM and the
desktop. Picom stayed off at login, as #32 requires on V3D 4. The update
(2026-11-05) installed upstream Lyona and removed the ARM support, as #53
says, and the rollback restored every file. The overview worked with 30
terminals open. The maintainer also briefly tried the Pi 5, where Picom was
on, and `install.sh` on Arch Linux ARM's own image, which worked; neither
has details recorded here ("Reported, not recorded"). NVMe was not run (see
"Not tested").

## The machine

| | |
| --- | --- |
| Board | Raspberry Pi 4 Model B Rev 1.1, 4 GB (3.7 GiB in `free -h`), 4 cores |
| Boot medium | SD card, 64 GB (`mmcblk0`, 59.5 GiB) |
| Display | HDMI-1, 2560x1440 at 75 Hz (monitor model not recorded) |
| Network | Ethernet (`end0`), with the board's Wi-Fi seeing networks |
| Kernel | `6.18.60-1-rpi` (Arch Linux ARM `linux-rpi`) |

## The image

| | |
| --- | --- |
| Source | Lyona-ARM `main` at `51a72b9` ("bug fixes 2"), copied to the Pi as a git bundle (the repository is private) |
| Builder | `scripts/build-lyona-rpi-image.sh --output release/`, as root, through `systemd-run` so that a dropped SSH session could not stop it |
| Build host | the same Pi 4, booted from the previous Lyona Pi image (`ff191bd`, Arch Linux ARM), git 2.56.0, e2fsprogs 1.47.4; it first needed `arch-install-scripts`, `dosfstools` and `mtools` |
| Build time | 11:39 to 13:08 EST, about 1 h 29 min. Most of it was the `install.sh --profile full` step and the copy of the root partition into the disk image on the SD card |
| Output | `lyona-2026.10.0-beta.7-rpi-aarch64.img.xz`, 810 MiB compressed, 5828 MiB written out |
| SHA-256 | `cbda44cbac38593c93fc305dfcae420e7af27214f967e90e5d8b50dd7fb325a0` |
| Written with | Raspberry Pi Imager, as a custom image, with no OS customisation |

The build log had no errors. The mkinitcpio warnings (`architecture
'aarch64' not supported`, `drm_privacy_screen_register`, no
`/etc/vconsole.conf`) and bsdcpio's "Failed to set default locale" are the
usual ones on aarch64.

The image was confirmed to be from `51a72b9` by its contents: the installed
`dwm-settings-picom` has the `bcm2711` device-tree check, which only that
commit has. `/etc/lyona-release` could not show it (finding 1).

## Results

| Check | Result |
| --- | --- |
| Boot splash | Shown on the Pi 4's KMS console (seen by the maintainer). This closes ARM3-03's open question |
| First-boot wizard | Went through without a problem (seen by the maintainer) |
| First boot runs once | `lyona-firstboot.service` disabled and inactive afterwards, and again after a reboot; no failed units; `systemctl is-system-running` reports `running` |
| Root partition grown | 59 GB of the 64 GB card. The partitions are labelled `LYONA_BOOT` and `lyona-root`, and the root is found by `root=PARTUUID=bfa346a3-02` |
| Nothing from the build | 4 new SSH host keys and a new machine-id; the only user is the one the wizard made (in `wheel`) |
| zram | 1.9 GiB, zstd, `linux-rpi` has it (ARM3-02's open question) |
| Locale, timezone | `en_US.UTF-8`, the wizard's timezone, NTP in sync |
| LightDM | The greeter on seat0, Xorg on vt7, login works |
| Picom at login | Not running. `dwm-settings-picom status` reports `renderer: v3d4`, `running: false`: "Picom is off at login on this GPU (V3D 4, the Raspberry Pi 4)". The user service `app-picom@autostart.service` was skipped by its `ExecCondition` |
| Menus without Picom | Working: no blackout on click-away (#32, #384) |
| Overview | Working, with icon cards |
| Settings | Every pane opens without an error (maintainer). The SoC temperature source, `cpu-thermal`, read 45 degrees C |
| Network | NetworkManager only; systemd-networkd inactive. The old Pi 4 problem, both of them managing `end0`, is gone |
| Bluetooth | Powered and not blocked. Named `archlinux` on the first boot and `lyona-arm` after the reboot (finding 2) |
| Audio | The HDMI sink, "Built-in Audio Digital Stereo (HDMI)", is the default |
| Boot time after the first boot | 13.4 s: 1.7 s kernel, 2.0 s initrd, 9.8 s userspace. The first boot's 3 min 14 s of userspace includes the time spent in the wizard |

### Idle cost

Measured over 60 s, logged in, with the launcher closed and Picom off.
The CPU figures are from `/proc/<pid>/stat`; the whole-machine figure is
from `/proc/stat`.

| Process | CPU (of one core) | RSS |
| --- | --- | --- |
| quickshell | 0.23% | 174 MiB |
| Xorg | 0.25% | 92 MiB |
| dwm | 0.03% | 15 MiB |
| Whole machine | 0.99% busy (4 cores) | 621 MiB used of 3.7 GiB |

The previous image's Picom run (2026-10-28, `measure-picom-cost`, with two
windows at 2560x1440) gave similar figures: quickshell 0.02% and 199.7 MiB,
Xorg 0.05% and 82.9 MiB, and the machine 0.38% busy. Picom with XRender
added 6 MiB and no measurable CPU when idle. That image still started
Picom at login, which `51a72b9` fixed.

## Findings

1. **`LYONA_COMMIT=unknown`** in `/etc/lyona-release`, and
   `LYONA_ISO_COMMIT=unknown` in `/etc/lyona-iso-release`. The builder reads
   the commit with `git -C "$repo_dir" rev-parse HEAD` as root, on a
   checkout the user owns. Since git 2.35.2, git refuses to read that
   ("dubious ownership") unless the checkout is listed in `safe.directory`.
   The failure is hidden, so the builder writes `unknown` without a
   warning. **Fixed** in the Pi builder (`git -c safe.directory=...`, with a
   check in `tests/test-rpi-image-builder.sh`). The x86_64 ISO builder,
   which is shared code, has the same line: technicks89/Lyona#478. Lyona's
   release workflow already trusts its checkout, so released ISOs are not
   affected.
2. **Bluetooth named `archlinux` on the first boot.** bluetoothd starts
   before the wizard sets the hostname and keeps the name it read then. After
   a reboot it is the hostname. **Fixed**: the wizard runs `systemctl
   try-restart bluetooth.service` after `hostnamectl set-hostname`, and
   `tests/test-rpi-firstboot.sh` checks that.
3. **Suspend was in the power menu** of a system that cannot suspend.
   logind's `CanSuspend` is `na` on the Pi 4. `8f60aed` stopped it from
   erroring, but the item was still offered. **Changed** so that Suspend is
   not shown in the power menu or in the Power pane's session buttons where
   the system cannot suspend, or before logind has answered. Suspend
   blocked by policy is still shown, with the reason. Checked statically
   (`tests/test-quickshell-power-model.sh`, qmllint), and on the Pi, with the
   three changed QML files copied into `~/.config/quickshell`: Suspend is not
   in the power menu, and Settings > Power describes it as read-only and not
   supported on this system.
4. **No `glxinfo`.** `mesa-utils` is not in any profile, on x86_64 either.
   Not changed: it is a diagnostic tool, not part of the desktop.
5. **#53 reproduced on a Pi.** `lyona-update check` compares the installed
   `2026.10.0-beta.7` (commit `unknown`) with upstream Lyona's
   `2026.10.0-beta.7` (`e1c92e9`). `lyona-update apply --yes` (2026-11-05,
   backup `20261105T131026Z-7115`) then installed upstream's tarball. Compared
   with checksums taken before it, 17 of the 121 managed files changed, plus
   `/etc/lyona-release` (now `LYONA_SOURCE=tarball`), and no files were added:
   - `dwm-settings-picom`, `dwm-settings-provider`, `dwm-system-health`,
     `lyona-appimage`, `lyona-update`, `xscreensaver-setup.sh`;
   - `lib/lyona/autostart.sh`, `dwm-aur.sh`, `dwm-packages.sh`,
     `dwm-quickshell-lifecycle.sh`, `dwm-utils.sh`,
     `lyona-install-verify.sh`;
   - `lyona_system_management/__init__.py`, `snapshots.py`,
     `system_information.py`;
   - `libexec/lyona/dwm-system-health-root`, `lyona-update-root`.

   After the update, no installed file mentions `archarm` (3 did before).
   `dwm-utils.sh` gives `DISTRO_FAMILY=unknown` and has no
   `is_arch_family`, and `dwm-settings-picom` has lost the Pi 4 check, so
   Picom would start at the next login. ARM2-05 found 11 changed files on
   the VM; upstream has changed more since. `lyona-update rollback --yes`
   then restored all 121 files exactly (every checksum matches), with the 3
   `archarm` files, the Pi 4 Picom check, and `LYONA_SOURCE=iso`. The update
   and the rollback both work. What is wrong is where the update comes from
   (#53).
6. **Quickshell crashed during the rollback** (SIGSEGV, core dump present).
   The rollback restored `~/.config/quickshell`, and the running shell
   reloaded those files. The rollback then restarted the shell
   (`dwm-quickshell-controlcenter action restart-quickshell`). The old
   instance's log ends with "Exiting due to IPC request", and it crashed
   while exiting, in `QXcbWindow::hide` (Quickshell 0.3.2, Qt 6.12.0). The
   new instance started at the same second (08:12:42), so the panel came
   back without a gap, and the desktop kept working. Only the old process
   crashed, and systemd-coredump took a minute to write its dump. Cause not
   found: there are no debug symbols, and it happened once. Not the same as
   the earlier Pi 4 crash of a second instance in `libgallium` (2026-10-15).
   The report is in `~/.cache/quickshell/crashes/iqa0z51ot/` on the Pi.

## Reported, not recorded

The maintainer ran these on 2026-11-05 and reported the outcome. No figures
or logs were captured, so they are not measurements.

- **The overview with 30 windows** (ARM3-04): it works with 30 terminals
  open, with icon cards since Picom is off. It was not timed, and its CPU
  cost was not measured.
- **The Pi 5** (8 GB, SD card), briefly: Picom was on at login, as intended
  on V3D 7. Not recorded: the image or its checksum, the wizard, Settings,
  Picom's backend and its cost, and the idle cost.
- **`install.sh` on Arch Linux ARM's own Pi image** (carried over from
  ARM1-06): it worked. Not recorded here: the profiles run, the logs, or the
  ARM1-06 checks on V3D. Those belong in the Raspberry Pi section of
  `docs/evidence/arm1-06-install-sh.md`.
- **Wi-Fi as the only network** on the Pi 4: it works. Not recorded: the
  band, the signal, or whether the wizard's Wi-Fi step (with no Ethernet
  connected) was used.

## Not tested

- **The Pi 5's NVMe boot.** There is no NVMe board, and none will be
  bought. It is expected to work: `lyona.txt` turns on PCIe under `[pi5]`,
  the root is found by PARTUUID, and the boot order is the Pi 5's EEPROM
  setting. But it has not been booted. The Pi 5's own run is only what
  "Reported, not recorded" says.
- **Two displays on a Pi 4.** There is no second display to test with, and
  none will be bought. They are expected to work: the Pi 4 has two HDMI
  ports under the same `vc4` KMS driver, and the shell makes one panel per
  screen. But this has not been seen.
- **Other boards**: outside the sprint.
- **GPU load.** `glxinfo` is not installed, and the Pi has no GPU monitoring
  tool like `intel_gpu_top`.
