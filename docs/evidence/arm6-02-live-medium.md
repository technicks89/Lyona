# ARM6-02: the live medium on a generic virtual machine

ARM Sprint 6 item ARM6-02, acceptance part 2: a machine with no device-tree
match boots the medium as before. Run 2026-11-10 by the maintainer's Claude
session on a second machine, an AMD Ryzen 5 3600 (6 cores, 12 threads, 32 GB,
CachyOS kernel 7.3.1), with QEMU 11.1.3 and edk2 aarch64 firmware (Aug 25
2026). That host has no aarch64 KVM, so every run was emulated (TCG): the
timings say nothing about real speed. The logs and screenshots stay on that
machine (`~/tmp/vmtest/evidence/`); this file records what that session
reported. The XPS 13 9345 results are in `arm6-01-snapdragon-spike.md`.

## The medium

`lyona-2026.10.0-beta.7-aarch64.iso` (`new11`), sha256
`37a8be3c2eb38b209fde37db7e495a36859e30a0835a49450198b82773a1a1c7`, checked
before the first run; built on the Pi 4 from `ae4f0ba`. Boot entry:
`copytoram=y quiet splash loglevel=3 vt.global_cursor_default=0
plymouth.force-scale=1 systemd.tpm2_wait=0`. Guest kernel 7.3.3-1-aarch64-ARCH.

## The runs

`qemu-system-aarch64 -machine virt,gic-version=3 -cpu max,pauth-impdef=on -smp 4
-accel tcg,thread=multi`, edk2 `QEMU_EFI.fd`, a fresh `QEMU_VARS.fd` per run,
Secure Boot off, user-mode network, no `bootindex` (the firmware booted the
medium on its own). Machine ACPI tables, so no device-tree match.

| Run | Medium, display | RAM | Reached gum, no manual step | Time to gum | Splash |
| --- | --- | --- | --- | --- | --- |
| 1 | USB stick, virtio-gpu | 3 GiB | yes | 97 to 127 s | not seen |
| 2 | virtio-scsi CD, bochs-display | 3 GiB | yes | 114 s | not seen |
| 3 | USB stick, virtio-gpu | 2 GiB | yes | 120 s | not seen |
| 4 | USB stick, virtio-gpu | 1.5 GiB | yes | 120 s | not seen |
| 5 | USB stick, virtio-gpu | 1 GiB | **no** | - | - |

- **Run 5:** the copy into RAM failed at 92 percent
  (`pv: ... write error: No space left on device`), and the initramfs stopped
  at an emergency shell on the serial console only; the screen stayed black.
  The root image is 736 MiB and archiso sizes the copy's tmpfs at 75 percent of
  RAM, about 750 MiB at 1 GiB. The medium fits between 1 and 1.5 GiB; not
  narrowed further. Before ARM6-02 the aarch64 entry was `copytoram=n`, which
  would have booted at 1 GiB. The aarch64 entry is now `copytoram=auto`
  (archiso copies only when the available memory exceeds the image plus 2
  GiB); not yet re-run.
- **Snapdragon modules** (`ps883x`, `pmic_glink`, `pmic_glink_altmode`,
  `qcom_pd_mapper`, `qrtr`, `qrtr-smd`): loaded from the initramfs, bound to
  nothing, and logged nothing (no error, no `Direct firmware load`, no
  `ps883x`, `pmic_glink` or `qrtr` line but the protocol registering).
- **Failed units:** 0 in runs 1 to 4. Warnings, all harmless: the
  `arm64.nopauth` feature mask, `clk_ignore_unused` and `pd_ignore_unused`
  notices, `set-wireless-regdom` exit 1 (no wireless device), and on the CD run
  `pktsetup` exit 1 for `sr0`.
- **`ldconfig`:** `ldconfig.service` is masked and inactive; `ldconfig -p`
  finds 1,031 libraries in the cache. **TPM:** every TPM unit is skipped by its
  condition, with no wait.
- **Splash:** the screen was solid black (every pixel 0) from about 31 s to
  about 103 s while `plymouthd` ran. Cause found by a `plymouth.debug` run on a
  patched copy of the medium (run 1's configuration): the kernel has no
  `console=` argument, so it enables the ACPI SPCR console (`ttyAMA0`), and
  Plymouth logs `serial consoles detected, managing them with details forced`,
  creates only a text display for it and never looks for a DRM device, although
  `virtio_gpu` was up at 21.7 s and `plymouthd` started at 22.1 s. So
  `DeviceTimeout=1` is not involved. With `plymouth.ignore-serial-consoles`
  added, Plymouth found `/dev/dri/card0` (`virtio_gpu`) and the lyona splash
  showed from 30 s to 71 s, then the installer banner at 114 s and gum by 128 s,
  with 0 failed units; the serial console stays. Plymouth's `details` splash
  also explains the black screen in runs 1 to 4: nothing was drawn on the
  display. The aarch64 entry now carries `plymouth.ignore-serial-consoles`; not
  yet re-run. The same should happen on any machine that publishes a serial
  console (an inference, not tried). Not tried: `console=tty0`, which would drop
  the serial console.
- **Boot menu:** none shows, because `loader/loader.conf` has `timeout 0`.

## Not tested

KVM or any real hardware but the XPS; the install itself (nothing past the gum
keyboard menu); memory
between 1 and 1.5 GiB; UTM, Parallels, libvirt, Secure Boot, `-cpu cortex-a72`;
a virtual machine with a device tree (all runs used ACPI).
