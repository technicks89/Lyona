# ARM6-00: Snapdragon X static survey

Date: 2026-11-05. Static only: no Snapdragon hardware was used. Checked
against Arch Linux ARM's `core` repository database
(`mirror.archlinuxarm.org/aarch64/core/core.files`, the file lists of the
packages below).

## What the packages carry

| Package | Version | Finding |
| --- | --- | --- |
| `linux-aarch64` | 7.3.1-2 | Installs device trees at `/boot/dtbs/qcom/` (not under a per-kernel subdirectory). 52 `x1e*` device trees, among them `x1e80100-dell-xps13-9345.dtb` and its `-el2` variant. |
| `linux-firmware-qcom` | 20261019-1 | Has `usr/lib/firmware/qcom/x1e80100/dell/xps13-9345/`: `qcdxkmsuc8380.mbn` (GPU), `qcadsp8380.mbn`, `qccdsp8380.mbn`, `adsp_dtbs.elf`, `cdsp_dtbs.elf`, the `*.jsn` files, `battmgr.jsn` and the speaker topology `X1E80100-Dell-XPS-13-9345-tplg.bin`. Also the Inspiron 14 Plus 7441 and Latitude 7455. |
| `linux-firmware-atheros` | 20261019-1 | Has the `ath12k` firmware (29 files): the XPS's Wi-Fi. |
| `linux-firmware` (base) | 20261019-1 | Arch Linux ARM splits the firmware by vendor, as Arch does; the Qualcomm and Atheros files are in the split packages, so they must be named. |
| `grub` | 2:2.16-1 | Supports the `devicetree` command on arm64 (A-11 (a)); not exercised. |

## What this changed

- `scripts/dwm-packages.sh`: profile `soc-snapdragon` (aarch64 only):
  `linux-firmware-qcom linux-firmware-atheros`.
- `scripts/lyona-snapdragon.sh`: `lyona_snapdragon_dtb` names the device tree
  of a covered laptop from its SMBIOS strings, and only when the installed
  kernel has it.
- `tests/test-snapdragon.sh` (`make check-snapdragon`).

Neither is wired into the installer: that waits for ARM6-01 (A-10, A-11) and
ARM6-04.

## Not verified

- The XPS's DMI strings (`Dell Inc.` / `XPS 13 9345`) are Dell's published
  names, not read from the machine. ARM6-01 confirms them.
- That GRUB's `devicetree` line boots the XPS, and whether firmware needs
  `devicetree` before or after the kernel line.
- Whether Arch Linux ARM's systemd builds a UKI with `.dtbauto`/`.hwids`
  (A-10), and the `qcvss8380.mbn` gap, the disabled EC, and every runtime
  behavior.
- `shellcheck` and `shfmt` were not installed on the machine this ran on, so
  the new scripts were not linted or format-checked.
