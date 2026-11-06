# ARM Sprint 6 -- Snapdragon X laptops

Index: [`ARM64.md`](ARM64.md). Depends on ARM-2 (the generic image). Comes
after ARM-3 and before ARM-5, so that ARM-5's release, support contract and
user docs cover it (decided 2026-11-05, by the maintainer).

**Status:** planned 2026-11-05. Static groundwork done the same day
(`docs/evidence/arm6-00-static-survey.md`): the firmware profile
`soc-snapdragon`, a device-tree lookup (`scripts/lyona-snapdragon.sh`) and
`make check-snapdragon`. Nothing is wired into the installer; ARM6-01 (the XPS)
has not started. GitHub: no issues yet.

**Goal:** the generic aarch64 image boots and installs Lyona on Snapdragon X
laptops (X Elite and X Plus). One image covers all of them, with no
per-laptop image. It is validated on the maintainer's Dell XPS 13 9345.

## Why one image can do it

A Snapdragon X laptop's firmware gives Linux no usable description of its
hardware, so Linux boots it from a device tree. The kernel has one device
tree for each laptop it supports. One image covers them all by carrying
every device tree, plus a table from each laptop's hardware IDs (from its
SMBIOS firmware tables) to its device tree. A loader at boot picks the
match before Linux starts. Ubuntu's generic arm64 image works this way, and
so does Arch's own aarch64 release profile, through `stubble`. Our generic
medium dropped `stubble` in ARM2-02 only because Arch Linux ARM does not
package it (`docs/evidence/arm2-01-spike.md`). systemd-stub can make the
same choice itself, from a unified kernel image's `.dtbauto` and `.hwids`
sections (systemd 257 and later).

**The limit:** a laptop is covered only if mainline Linux has its device
tree and `linux-firmware` has its firmware. A Snapdragon laptop with
neither boots on no distribution's generic image. "Supported" in this sprint
means the laptops that pass on real hardware: the XPS 13 9345. Every other
covered laptop is "should work, not tested".

## What is already there (checked 2026-11-05)

- **Kernel:** Arch Linux ARM's `linux-aarch64` 7.3.1 builds the X1E80100
  drivers: `PINCTRL_X1E80100`, `CLK_X1E80100_GCC` and `_DISPCC`,
  `INTERCONNECT_QCOM_X1E80100`, `DRM_MSM` and `PHY_QCOM_EDP` (display),
  `ATH12K` (Wi-Fi), `SND_SOC_X1E80100` (audio), `QCOM_PMIC_GLINK`,
  `BATTERY_QCOM_BATTMGR` and `UCSI_PMIC_GLINK` (battery and USB-C),
  `QCOM_Q6V5_PAS` (the DSPs), `I2C_QCOM_GENI` and `I2C_HID_OF` (keyboard and
  touchpad).
- **Device tree:** mainline has `x1e80100-dell-xps13-9345.dts`, and an
  `-el2` variant that boots Linux at EL2. The EL2 variant is out of scope.
  Dell's Inspiron 14 Plus 7441 and Latitude 7455 have device trees too.
- **Firmware:** `linux-firmware` has `qcom/x1e80100/dell/xps13-9345/`: the
  GPU's `qcdxkmsuc8380.mbn`, the audio and compute DSPs' `qcadsp8380.mbn`
  and `qccdsp8380.mbn` with their `*_dtbs.elf`, `battmgr.jsn`, and the
  speaker topology `X1E80100-Dell-XPS-13-9345-tplg.bin`. Nothing has to be
  copied from Windows. The video decoder's `qcvss8380.mbn` is missing; the
  desktop does not need it.
- **Checked against Arch Linux ARM's repositories (2026-11-05):** the device
  trees install at `/boot/dtbs/qcom/`, and the firmware is in the split
  packages `linux-firmware-qcom` and `linux-firmware-atheros` (ath12k), not the
  base `linux-firmware`.
- **Known gap:** the XPS's device tree has its embedded controller turned
  off (`&i2c5`, "EC @0x3b", `status = "disabled"`). ARM6-01 finds out what
  that affects.
- **The desktop** is Xorg on the `msm` driver with Mesa's freedreno, the same
  modesetting and glamor path as the Pi. dwm and the shell need no change.
  System Information already names Qualcomm as a CPU implementer.

## Decisions

| ID | Question | Recommendation | Status |
| --- | --- | --- | --- |
| **A-10** | How does the live medium choose the device tree? (a) `stubble`, packaged for Arch Linux ARM by Lyona (a pinned PKGBUILD, as `dwm-aur.sh` pins AUR packages), (b) systemd-stub's `.dtbauto` and `.hwids` in a unified kernel image | Decide from ARM6-01. Prefer (b) if Arch Linux ARM's systemd builds it and archiso's systemd-boot path can boot a UKI, since it needs no new package | **(b)**: on the installed XPS (systemd 262.1) a `ukify` UKI with `.dtbauto` and `.hwids` booted the laptop with no `devicetree` line, no `stubble` ([evidence](../evidence/arm6-01-snapdragon-spike.md)). Not yet checked on the live medium's own systemd | Decided |
| **A-11** | How does the installed system choose it? (a) The installer matches the laptop once and writes a `devicetree` line for GRUB, (b) the same mechanism as the medium (A-10), with systemd-boot or a UKI | **(a)** unless A-10 is (b) and the installed system can use it too. The installed system boots one known machine, and GRUB stays the bootloader the aarch64 install already uses (ARM2-03) | Open |

## Items

| Item | Kind | Gate |
| --- | --- | --- |
| [ARM6-01](#arm6-01-spike-on-the-xps-13-9345) | Spike | ARM-2, the XPS |
| [ARM6-02](#arm6-02-the-device-tree-on-the-live-medium) | Feature | ARM6-01, A-10 |
| [ARM6-03](#arm6-03-the-device-tree-in-the-installed-system) | Feature | ARM6-02, A-11 |
| [ARM6-04](#arm6-04-firmware-and-packages) | Feature | ARM6-01 |
| [ARM6-05](#arm6-05-the-desktop-on-adreno-x1) | Measurement, fix | ARM6-03, ARM6-04 |
| [ARM6-06](#arm6-06-validate-on-the-xps-13-9345) | Validation | ARM6-01 to ARM6-05 |

---

## ARM6-01: Spike on the XPS 13 9345

1. **Medium:** today's generic aarch64 medium, built on the Pi 4
   (`scripts/build-lyona-arch-iso.sh --arch aarch64`; the Pi 5 is not a
   build host), on a USB stick.
   Secure Boot off in the XPS's firmware. Windows stays on the internal
   drive, untouched.
2. **Boot it by hand** with the XPS's device tree: a `devicetree` line added
   at the systemd-boot menu, or a test entry on the stick, naming
   `dtbs/qcom/x1e80100-dell-xps13-9345.dtb`. Any kernel arguments the boot
   needs are recorded.
3. **Record what works** on the live system: the internal display,
   keyboard and touchpad, Wi-Fi, USB-C, the GPU (`glxinfo -B` on `msm`),
   battery and charging, audio, suspend and the lid, and what the disabled
   EC takes away.
4. **Answer A-10:** does Arch Linux ARM's systemd build a UKI with
   `.dtbauto` and `.hwids` that boots here, or is `stubble` needed?

**Acceptance:** `docs/evidence/arm6-01-snapdragon-spike.md` says what boots,
what works, and how big ARM6-02 to ARM6-05 are.

## ARM6-02: The device tree on the live medium

1. The medium carries the device trees and the hardware-ID table, through
   A-10's mechanism, and boots a covered laptop with no menu edit.
2. A machine with no match boots as today (ACPI, as on the virtual machines
   and servers), so the generic image does not regress.
3. **Tests:** `check-archiso` checks the medium's profile and that the table
   comes from the kernel's device trees, not from a hand-kept list.

**Acceptance:** the XPS boots the medium to the wizard with no manual step,
and the three ARM2-05 virtual machines still do.

## ARM6-03: The device tree in the installed system

1. The installer finds the laptop's device tree (A-11) and makes the new
   system boot with it, across kernel updates.
2. An installed system on a machine with no match is unchanged.
3. **Tests** with stubs, as the image installer's are.

**Acceptance:** an install on the XPS reboots to LightDM with no manual
step, and again after a kernel update.

## ARM6-04: Firmware and packages

1. The Qualcomm firmware the laptops need (`linux-firmware`'s `qcom`
   files, in Arch Linux ARM's split packages), through the dependency map,
   installed only on a Snapdragon machine, as NVIDIA packages are installed
   only where the driver is used.
2. Whatever else ARM6-01 finds missing, each checked with `pacman -Si` on
   aarch64.

**Acceptance:** the installed XPS loads its GPU, DSP and Wi-Fi firmware
(`dmesg` shows no missing firmware), from packages the dependency map names.

## ARM6-05: The desktop on Adreno X1

1. **Picom** with GLX on the Adreno X1-85: idle and active cost, as #244
   measured on x86_64. Whether the Automatic policy keeps it on.
2. **The overview's previews**, and idle CPU and memory with the launcher
   closed, against the Pi 4 and x86_64 numbers.
3. **Settings:** the battery, power profiles, brightness on the internal
   panel, and suspend, each working or hidden or explained (ARM3-05's rule).

**Acceptance:** the desktop is usable by the numbers recorded, and every
Settings pane opens without an error.

## ARM6-06: Validate on the XPS 13 9345

1. **Run:** write the medium, boot, install, first login, the ARM1-06
   checks, the ARM6-05 measurements, a reboot, a kernel update.
2. **Record** in `docs/evidence/arm6-06-xps13-9345.md`: the model,
   firmware version, memory, kernel, the image's checksum, and what was not
   tested: every other Snapdragon laptop, external displays if there are
   none to hand, and EL2.

**Acceptance:** the XPS reaches a working desktop from the generic image
with no manual step.

---

## Not in this sprint

- Laptops with no mainline device tree, and Windows-on-ARM desktops and
  dev kits with no device tree.
- Booting at EL2 (the `-el2` device trees) and KVM on these laptops.
- Dual-boot setup with Windows beyond leaving it untouched: no resizing of
  the Windows partition and no BitLocker handling.
- Speakers and microphones on the XPS 13 9345: its mainline device tree has
  no sound card, and no upstream fix has landed. Not carried here; see
  `docs/evidence/arm6-01-snapdragon-spike.md` ("Sound: decision").
- The camera and the video decoder (`qcvss8380.mbn` is not in
  `linux-firmware`).
