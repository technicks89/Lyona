# ARM6-03: the device tree in the installed system

What was run, on what, and what was not. Reported by the maintainer; the
details below are what they told us, nothing more.

## The medium and the machine

- Medium: `lyona-2026.10.0-beta.7-aarch64.iso` (`new13`), sha256
  `94e1fde9d3ef1a305df627e5591e4c916daf86d30e3ae9ba63e89330a8787db0`,
  970,070,016 bytes, built on the Pi 4 from `52fe88a` (branch
  `arm/arm6-03-installed-device-tree`). Its `root/lyona-postinstall.sh` was
  checked byte for byte against the branch's.
- Machine: the maintainer's Dell XPS 13 9345 (Snapdragon X Elite), Secure Boot
  off, booted from a USB stick written from this image.

## Results (2026-11-11)

| Step | Result |
| --- | --- |
| The installer's Snapdragon step ran on a real install (the log line `Snapdragon X: device tree qcom/x1e80100-dell-xps13-9345.dtb, firmware ...`) | yes |
| The installed system rebooted to LightDM with no manual step | yes |
| After `sudo pacman -S linux-aarch64` and a reboot, the system booted to LightDM again | yes |

This is the first run of `install_snapdragon_support` on a real install: the
ARM6-01 installs predated it.

## What changed in this item

- The `devicetree` line the step writes into `grub.cfg` is guarded by a file
  test (`if [ -f ... ]; then devicetree ...; fi`).
- A pacman hook on `linux-aarch64` runs `/usr/local/lib/lyona/snapdragon-dtb-check`,
  which warns, and never fails the upgrade, when the device tree the GRUB hook
  names is gone. Tests: `tests/test-snapdragon.sh`.

## Not recorded or not tested

- Which disk the system was installed to, the time the install took, and the
  full text of the install log: not given.
- Whether the pacman hook's line ("Checking the Snapdragon X device tree...")
  appeared in the pacman output, and whether the upgrade replaced the kernel or
  reinstalled the same version: not stated. The upgrade test used the same
  package version if no newer one was in the repository, which would not move
  the device tree file; a kernel whose package drops or renames the file is
  untested.
- The guard's behaviour when the file is missing, on hardware: only checked
  statically and by the tests, not by booting without the file.
- Every other Snapdragon laptop (`lyona_snapdragon_dtb` names only the XPS
  13 9345), EL2, and anything past LightDM (ARM6-04 to ARM6-06).
