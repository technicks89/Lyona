# ARM1-04: code that assumes x86_64

ARM Sprint 1 item ARM1-04 (issue #4), 2026-10-13.

## The search

Repeated from the sprint plan: `x86_64`, `uname -m`, `amd64`, `i686`,
`/proc/cpuinfo`, `model name`, DMI and device-tree paths across `scripts/`,
`config/quickshell/`, `install.sh`, the C sources, `config.mk` and the
`Makefile`. What it found, beyond the gates ARM1-01 to ARM1-03 already handle
(the identity, the package map, CachyOS, gaming, multilib, the AUR pins,
herdr and AppImages):

| Place | On aarch64 before | Now |
| --- | --- | --- |
| System Information's CPU (`system_information.py`) | "unknown": arm64's `/proc/cpuinfo` has no `model name` | Named from the cores' implementer and part codes, else the board's name, else the codes (below) |
| NVIDIA detection | Not PCI-based where it matters: `dwm-display-setup` reads the X server's log; `detect_gpu` (`dwm-utils.sh`, unused) returns `unknown` with or without `lspci`; the image's PCI detection is x86_64-only (the medium) | Unchanged; tests for a Pi 4's and the VM's `lspci`, and none |
| Picom's backend (`dwm-settings-picom`) | Auto asks the running X server's GL renderer, not PCI: GLX only for accelerated Intel and AMD, XRender otherwise | Unchanged; tests for v3d (Pi 4, Pi 5), virgl, Mali/Panfrost, Adreno (all XRender) and NVIDIA GB10 (XRender until ARM Sprint 4 measures it) |
| GRUB theme (`install.sh`) | Applied only when `/etc/default/grub` and `grub-mkconfig` exist; otherwise "this machine does not boot with GRUB" | Unchanged |
| Suspend and hibernate (Settings) | From logind (`CanSuspend`): "not supported by this system" when it says so; lid actions are logind's | Unchanged. The VM reports suspend `yes`, hibernate `na` |
| Boot entries and firmware (Settings) | Settings has no boot-entry pane; Secure Boot reads its EFI variable and is "unsupported" without one | Unchanged |
| `nvidia-gpu`, `nvidia-temp` | Installed, called by nothing | Unchanged |
| The C build | Not built on aarch64 before | Built (below) |

## System Information's processor on ARM

- Cores Lyona names: Arm Cortex-A35/53/55/57/72/73/75/76/77/78/78C/510/520/
  710/720/725, X1/X2/X4/X925, Neoverse N1/N2/N3/V1/V2/V3, Qualcomm Oryon,
  Ampere-1 and 1a, by the codes in Linux's `cputype.h` and util-linux's
  `lscpu`. A chip with two kinds lists both, in order.
- Any other core: the device tree's model (a Raspberry Pi), else SMBIOS
  `product_name` (a UEFI machine), each read with a 256-byte cap and only on
  this path; else the codes ("CPU implementer 0x00 part 0x051").
- The sprint listed the board's name first. The field is "Processor model",
  so a known core's name comes first and the board is the fallback.
- On x86_64, `model name` is read as before and nothing else is.

## On the emulated aarch64 VM

The VM from ARM1-02 (Arch Linux ARM, QEMU 11.1.2 TCG `-cpu max`, edk2 UEFI
with ACPI, `linux-aarch64` 7.1.6-1).

- `/proc/cpuinfo`: implementer `0x00` (reserved for software), part `0x051`,
  no `model name`; no device tree (ACPI); SMBIOS `QEMU Virtual Machine`.
- System Information's reader (Python 3.14.8): `cpu-model` "QEMU Virtual
  Machine", `architecture` `aarch64`, `logical-cpus` 6, `os-name` "Arch
  Linux ARM".
- bash's `$HOSTTYPE` is `aarch64` (what #25 relies on).
- `lspci`: QEMU host bridge, virtio network, virtio GPU, QEMU xHCI and
  virtio block: `detect_gpu` says `unknown`.
- The build, from `git archive HEAD` with the project's flags (`-std=c99
  -pedantic -Wall`): GCC 16.1.1 and Clang 23.1.1 each build `dwm`,
  `dwm-xwatch`, `dwm-window-thumb` and `lyona-toml` with no warning; `dwm` is
  an aarch64 PIE.

## Not tested

- Real ARM hardware: the Pi 4 and GB10 core names come from fixtures in the
  kernel's format, not from the machines. ARM Sprint 3 (Pi) and 4 (GB10)
  check them there.
- Running dwm or the shell on aarch64: ARM1-06.
- Picom's renderer on a real ARM GPU (v3d is ARM Sprint 3's).
