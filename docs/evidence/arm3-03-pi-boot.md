# ARM3-03: the Raspberry Pi image's boot configuration and splash

ARM Sprint 3 item ARM3-03 (issue #14), built 2026-10-27 on the maintainer's
x86_64 host: the builder's changes and their tests. The image itself was
not built here (it builds on an aarch64 Arch Linux ARM host as root, as
`docs/RELEASING.md` says), and no Pi has booted it: that is ARM3-06's run,
and the list at the end says what it has to look at.

## What the image gets

1. **The kernel** is Arch Linux ARM's `linux-rpi`, as A-5 decided: one
   kernel the firmware boots directly, for the Pi 4 and the Pi 5, with the
   firmware's per-board device trees. Nothing changed here; the Pi 5's 16K
   kernel is not measured (a Pi 5 arrived 2026-10-27, after this build).

2. **`config.txt`** stays the kernel package's file. It is in the package's
   backup list, so pacman keeps it across updates (and sets a changed
   package file aside as `.pacnew`), and it already turns on the KMS driver
   (`dtoverlay=vc4-kms-v3d`, `max_framebuffers=2`,
   `disable_fw_kms_setup=1`, `disable_overscan=1`, `arm_boost=1`). The
   builder checks the `vc4-kms-v3d` line is there and appends, once:

   ```
   # lyona (build-lyona-rpi-image.sh): the desktop's settings, then your own. lyona
   # may replace lyona.txt; custom.txt is yours. Keep these two lines last.
   include lyona.txt
   include custom.txt
   ```

   The firmware's `include` puts a file's lines where the include is, so
   `lyona.txt` (`rpi/lyona.txt`, installed to `/boot`) comes after the
   package's lines and `custom.txt` (`rpi/custom.txt`, comments only) after
   lyona's: a later line wins, so the user's settings override lyona's, and
   an update that replaces `lyona.txt` touches nothing of theirs. `lyona.txt`
   holds what the package's file lacks and the desktop wants:
   `dtparam=audio=on` (the Pi 4's headphone jack; HDMI audio comes with
   vc4), `disable_splash=1` (no firmware rainbow square before the splash),
   and under `[pi5]`, `dtparam=pciex1` (the PCIe connector, for an NVMe drive
   on a board that is not a HAT+; a HAT+ turns it on itself), then `[all]`,
   so `custom.txt` starts unfiltered. The firmware reads a line of up to 98
   characters; both files keep under that, and the test checks it.

   **HDMI hotplug:** the plan named it. Under KMS the kernel's driver sees a
   display plugged in or out itself, and `hdmi_force_hotplug` is a legacy
   option of the firmware's own video path (Raspberry Pi's documentation
   lists it under the legacy options), which does nothing with
   `vc4-kms-v3d`. So no line is set for it, and `lyona.txt` says why.

3. **The boot splash** is the lyona Plymouth theme, as the install medium's
   postinstall gives an x86_64 system (`install_boot_splash`): the theme
   generated from the `tokyonight` palette (`LYONA_SPLASH_PALETTE`
   overrides, as for the medium) into `/usr/share/plymouth/themes/lyona`,
   the medium's `plymouthd.conf`, the `plymouth` hook right after `udev` in
   `HOOKS` (or `systemd`, mkinitcpio 42's default since; fixed 2026-10-28), the `plymouth` package (the map's `boot-splash` profile), whose
   own pacman hook rebuilds the initramfs, and `splash
   plymouth.ignore-serial-consoles` on the command line
   (`ignore-serial-consoles` because `linux-rpi`'s line names the serial
   console first, which would make Plymouth draw text). One thing the x86_64
   path does not need: `vc4` in `MODULES`. mkinitcpio's `kms` hook adds the
   display drivers the build host has loaded, under `autodetect`, and the
   host need not be a Pi (the builds so far ran in a container on GB10), so
   the initramfs could have no display driver until the root is mounted, and
   the splash would not show before it. `linux-rpi` builds `vc4` as a module (Raspberry Pi's
   `bcm2711_defconfig`: `CONFIG_DRM_VC4=m`). After the package is installed
   the builder lists each initramfs in `/boot` with `lsinitcpio` and fails
   the build if one lacks `plymouthd` or `vc4.ko`.

   The first-boot wizard runs on tty1; `lyona-firstboot.service` is now also
   `After=plymouth-quit-wait.service`, as Arch's `getty@.service` is, so it
   does not draw under the splash.

4. **The Pi 5 and NVMe:** `dtparam=pciex1` is set for the Pi 5 (above). The
   boot order is the Pi 5's EEPROM setting, not the image's; the Pi
   documentation's `rpi-eeprom-config` sets it. Not tested: there is no NVMe
   board (2026-10-27); the Pi 5 itself boots from an SD card in ARM3-06.

`--check-root` checks all of it: the KMS line and both includes in
`config.txt`, both files, the theme, `plymouthd.conf`'s `Theme=lyona`, the
hook and `vc4` in `mkinitcpio.conf`, and `splash` on the command line.

## Tests

`make check-rpi-image` (`tests/test-rpi-image-builder.sh`,
`tests/test-rpi-firstboot.sh`): the builder's lines for each step and their
order (the boot files and the splash before `install.sh`; the initramfs check
right after `plymouth` is installed), `rpi/lyona.txt` and `rpi/custom.txt`
in the firmware's format and under the line limit, lyona's three settings
with PCIe under `[pi5]` only and a final `[all]`, `custom.txt` all comments,
no `hdmi_force_hotplug`, the unit's ordering after `plymouth-quit-wait`, and
ten new `--check-root` fault cases. With `check-shell` and `check-format`.

## Not tested

- **The build itself.** The new steps ran in no build: the host here is
  x86_64, and the GB10 that built the images so far is no longer available
  (2026-10-27). The next build, on the Pi 4 or the Pi 5 running Arch Linux ARM,
  runs them; the two checks that can fail it are `config.txt` without the `vc4-kms-v3d` line and an initramfs
  without `plymouthd` or `vc4.ko`.
- **The splash on a Pi 4's KMS console** (ARM3-06): that it shows at boot,
  quits before the wizard on tty1 and before LightDM, and that the headphone
  jack appears as an audio device. If it does not show or stays, removing
  `splash` from `/boot/cmdline.txt` is the quiet text boot.
- **The Pi 5** (8 GB, since 2026-10-27): its boot from an SD card is ARM3-06's
  run too; its NVMe boot and `dtparam=pciex1` with a drive are not tested
  (no NVMe board).
- **A `linux-rpi` update** on an installed Pi: that pacman keeps the edited
  `config.txt` and writes a `.pacnew`, and that the includes survive it.
