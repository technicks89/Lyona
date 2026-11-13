# ARM6-04: firmware and packages on the XPS 13 9345

ARM6-04's acceptance is that the installed XPS loads its GPU, DSP and Wi-Fi
firmware, with no missing firmware in the kernel log, from packages the
dependency map names. This records that check on an install made by the
installer's own Snapdragon step. ARM6-01 recorded the same check on an earlier
install whose firmware was added by hand (`arm6-01-snapdragon-spike.md`,
2026-11-06).

## The system

- Dell XPS 13 9345 (`/sys/class/dmi/id/product_name` reads `XPS 13 9345`),
  kernel 7.3.3-1-aarch64-ARCH, installed from the `new13` medium (sha256
  `94e1fde9d3ef1a305df627e5591e4c916daf86d30e3ae9ba63e89330a8787db0`, built
  from `52fe88a`) on 2026-11-11, and read over SSH after the reboot.
- The firmware packages were installed by the installer: `pacman.log` has
  `Running 'pacman -S --noconfirm --needed linux-firmware-qcom
  linux-firmware-atheros'` at 10:20:15 and `installed linux-firmware-qcom
  (20261019-1)` at 10:20:30, the command `install_snapdragon_support` runs from
  `dwm_packages arch soc-snapdragon`. `linux-firmware-atheros` (20261019-1) had
  already come in with the base install at 15:19:20 UTC.
  `/var/log/lyona-postinstall.log` is root-only, so its text was not read; the
  step's drop-in (`/etc/default/grub.d/90-lyona-snapdragon.cfg`) and the pacman
  hook for ARM6-03 (`lyona-snapdragon-dtb.hook`) are on the system.

## Results

`journalctl -k -b` as an ordinary user (the boot began 10:41:31):

- **Missing firmware:** none. A search for `Direct firmware`, `request_firmware`,
  `Unable to load` and `failed to load` found no line.
- **Loaded:** both DSPs (`Booting fw image
  qcom/x1e80100/dell/xps13-9345/qcadsp8380.mbn` and `qccdsp8380.mbn`), the GPU
  (`qcom/gen70500_sqe.fw` and `gen70500_gmu.bin`, "loaded ... from new
  location", a normal message), Wi-Fi (ath12k `fw_version 0x1103006c`) and
  Bluetooth (`QCA FW build version: BTFW.HAMILTON.2.0.1-00349-WOS_PATCHZ-2`).
- **Packages:** `linux-firmware-qcom` and `linux-firmware-atheros` are
  installed, with the rest of Arch Linux ARM's split `linux-firmware` set
  (amd, amdgpu, broadcom, cirrus, intel, mediatek, nvidia, other, radeon,
  realtek, ti, whence): the base install brings them all, and only the live
  medium prunes them (ARM6-02). Nothing Snapdragon-specific was added beyond
  the two packages the map names.

## Not tested

- Firmware on any other Snapdragon laptop (the table in
  `scripts/lyona-snapdragon.sh` has only the XPS).
- The video decoder firmware (`qcvss8380.mbn`): not in `linux-firmware`, not
  loaded, left out by the sprint plan.
- Sound: not a packaging problem (the XPS device tree has no sound card,
  `arm6-01-snapdragon-spike.md`).
- That the splash, resume or a kernel upgrade leave the firmware loading; this
  was one boot.
