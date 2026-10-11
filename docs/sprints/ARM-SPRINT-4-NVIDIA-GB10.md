# ARM Sprint 4 -- NVIDIA GB10 (DGX Spark and OEM systems)

Index: [`ARM64.md`](ARM64.md). Depends on ARM-2.

**Status:** planned 2026-10-11. Not started. Needs GB10 hardware.

**Goal:** the generic image (ARM-2) detects a GB10 system and offers its
kernel and NVIDIA driver, recommended, as the x86_64 image offers
`nvidia-open`; the installed system reaches a working desktop with the driver.

## Why this is the riskiest target

Checked 2026-10-11:

- **Kernel.** Mainline Linux does not carry GB10's hardware-enablement
  patches; under a generic kernel, USB does not come up, so neither does a USB
  keyboard or mouse. NVIDIA ships a patched Ubuntu kernel in DGX OS (DGX OS
  7.6 moved to a 7.0 `-nvidia` kernel). A community project packages a GB10
  kernel for Arch from NVIDIA's sources (`linux-dgx-spark`), unofficial and
  unsupported by NVIDIA.
- **Boot arguments.** Reported as needed on every boot:
  `pci=pcie_bus_safe initcall_blacklist=tegra234_cbb_init`.
- **Driver.** NVIDIA's open kernel modules list GB10 as supported, and NVIDIA
  publishes an aarch64 driver. Arch Linux ARM packages neither, and Arch's
  `nvidia-open`/`nvidia-utils` PKGBUILDs are x86_64 only.
- **Validation.** NVIDIA validates DGX OS only, and the hardware is expensive.

So this sprint depends on sources outside Arch Linux ARM, chosen under A-6,
and on access to a machine.

| Item | Kind | Gate |
| --- | --- | --- |
| [S4-01](#s4-01-where-the-kernel-and-driver-come-from) | Decision, packaging | A-6 |
| [S4-02](#s4-02-detect-gb10-and-offer-its-driver) | Feature | A-7, S4-01 |
| [S4-03](#s4-03-install-the-kernel-boot-arguments-and-driver) | Feature | S4-01, S4-02 |
| [S4-04](#s4-04-the-desktop-on-nvidia-aarch64) | Measurement, fix | S4-03, hardware |
| [S4-05](#s4-05-validate-on-gb10-hardware) | Validation | S4-01 to S4-04, hardware |

---

## S4-01: Where the kernel and driver come from

1. **Under A-6 (a):** pinned PKGBUILDs, reviewed at a commit, written down
   with the AUR exception in `docs/AUR-PACKAGES.md` as Sprint 14 wrote down
   the legacy NVIDIA drivers:
   - the kernel: built from NVIDIA's published GB10 kernel source, or the
     community package of it, whichever is reviewed and pinned;
   - the driver: NVIDIA's open kernel modules and user-space driver for
     aarch64, adapted from Arch's `nvidia-open` and `nvidia-utils`.
2. **Built as the new user, never as root, never through `yay`;** installed
   with `pacman -U`. The guard in `tests/test-no-aur.sh` allows it in one
   function only, as it does for the legacy drivers.
3. **Measure** the kernel build time on GB10. If it is too long for an
   install (the threshold set in the evidence), move to A-6 (b), a signed
   Lyona aarch64 repository, as its own decision and sprint item.
4. **Revisit (c)** at each release: once mainline and Arch Linux ARM carry
   GB10, the pinned kernel goes.

**Acceptance:** both packages build from their pins on GB10 and install; the
pins and what was reviewed are in `docs/AUR-PACKAGES.md`.

## S4-02: Detect GB10 and offer its driver

1. **Detection** in `archiso/airootfs/root/lyona-nvidia.sh` beside the PCI
   path: by the NVIDIA GPU's PCI ID where the GPU is on the PCI bus, else by
   SMBIOS (`/sys/class/dmi/id/`). Both IDs recorded from real hardware in the
   evidence, not guessed.
2. **The prompt:** on GB10, the installer recommends "NVIDIA GB10 kernel and
   driver (recommended)", says it builds them during the install and how long
   that takes, and keeps "generic kernel (no keyboard or USB until a GB10
   kernel is installed)" as the honest alternative. On any other machine,
   nothing changes.
3. **Tests** with fixture IDs: GB10, an Apple Silicon VM, a Pi, an x86_64
   NVIDIA card (unchanged path).

**Acceptance:** each fixture takes its path; the x86_64 NVIDIA tests are
unchanged.

## S4-03: Install the kernel, boot arguments and driver

1. **Profile:** `alarm:gpu-nvidia-gb10` in the dependency map, installed only
   when the user chose it, never shipped in the image.
2. **Boot arguments** (S4-01's list, re-checked against NVIDIA's current
   kernel) added to the bootloader entry for the GB10 kernel only, reported to
   the user, and documented.
3. **The live medium itself** boots with a generic kernel, so a GB10 machine
   may have no USB keyboard on the medium. S4-03 finds out on hardware and,
   if so, documents the workaround (a GB10 kernel on the medium as a second
   boot entry, or installing over SSH) and picks one.
4. **Tests** against a stub chroot, as `tests/test-legacy-nvidia.sh` does.

**Acceptance:** the stubbed install writes the right boot entry and installs
the profile only when chosen.

## S4-04: The desktop on NVIDIA aarch64

1. **Picom** with GLX on the NVIDIA driver (its x86_64 counterpart, upstream-sync
   Sprint 4 S4-01, is still waiting on hardware); XRender if GLX misbehaves.
2. **The overview's previews,** idle CPU and memory, a display on the HDMI
   port, and a second display if the system has one.

**Acceptance:** recorded numbers, and a backend choice for GB10 set from them.

## S4-05: Validate on GB10 hardware

1. **Hardware:** a DGX Spark, or an OEM GB10 system (recorded by make and
   model), with a display.
2. **Run:** boot the generic image, install with the GB10 option, reboot, log
   in, the checks of ARM-1's S1-06, `nvidia-smi`, a reboot, an update and a
   rollback, and a kernel update.
3. **Record** in `docs/evidence/arm-s4-05-gb10.md`, with what was not tested
   (other OEM systems, ConnectX networking).

**Acceptance:** a working desktop with the NVIDIA driver on a real GB10
system.

---

## Not in this sprint

N1X laptops (ARM-5's watch item), CUDA and AI tooling (not Lyona's scope),
and DGX OS compatibility.
