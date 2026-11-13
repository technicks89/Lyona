# ARM2-03: the installer on aarch64

ARM Sprint 2 item ARM2-03 (issue #9). Run 2026-10-22 and 2026-10-23, on the
build host and virtual machine of ARM2-01 and ARM2-02
(`docs/evidence/arm2-01-spike.md`, `docs/evidence/arm2-02-live-medium.md`).

The plan's item 2 (a `pacstrap` install step of Lyona's own) was for A-4 (b).
ARM2-01 decided A-4 (a): archinstall, unpatched, installs the system. The
wizard and its archinstall step stay one implementation for both
architectures; what differs is the configuration it writes and the
postinstall steps its gates run.

## What changed

The wizard (`archiso/airootfs/root/lyona-install.sh`), on aarch64:
- no CachyOS step (x86_64 only), with a line saying so and no warning;
- no NVIDIA question (its driver profiles are x86_64 only);
- archinstall's configuration has no `[multilib]` (Arch Linux ARM has none),
  keeps `kernels: ["linux"]`, which `linux-aarch64` provides, and installs
  `archlinuxarm-keyring`.

The postinstall (`archiso/airootfs/root/lyona-postinstall.sh`), on aarch64:
- skips the CachyOS repositories and kernel, keeping the stock kernel;
- installs the kernel-name hook (ARM2-02's
  `archiso-aarch64/airootfs/etc/pacman.d/hooks/lyona-vmlinuz-linux.hook`) in
  the new system and makes `/boot/vmlinuz-linux` a current copy of
  `/boot/Image`, before the first system update, so an upgrade there is
  followed too;
- adds a firmware boot entry, `lyona`, for GRUB's removable path
  (`\EFI\BOOT\BOOTAA64.EFI`) with `efibootmgr`, replacing one an earlier run
  made. A failure is a warning on the closing screen, not a failed install;
- puts the kernel console on the display: `console=tty0
  plymouth.ignore-serial-consoles` through
  `/etc/default/grub.d/90-lyona-console.cfg`, which `install.sh`'s GRUB theme
  step builds into `grub.cfg` with the splash's `splash` (#246);
- has 15 steps instead of 12.

x86_64 runs as before: the same configuration, questions and steps.

## Found in the virtual machine

The stubbed tests passed before any of these were found; each was a product
failure, fixed in this change.

1. **The new system did not trust Arch Linux ARM's packages.** Arch Linux
   ARM's `base` depends on Arch Linux's keyring, not its own. archinstall
   installs with `pacstrap` against the medium's keyring, so the install
   itself worked, but the new system's first download (the postinstall's
   NetworkManager step) failed with "signature from Arch Linux ARM Build
   System is unknown trust". archinstall now installs
   `archlinuxarm-keyring`, whose install script populates the new system's
   keyring. This is the smallest part of ARM2-04's keyring item, done here
   because the install could not finish without it; ARM2-04's check that the
   keyring is ready before downloading is still to do.
2. **An encrypted disk's passphrase prompt was not on the screen.** With no
   `console=` on the command line, the kernel takes the console the firmware's
   ACPI SPCR table names, the PL011 serial port (`/proc/consoles` listed
   `ttyAMA0` alone). The screen stayed black with a cursor; the prompt was on
   the serial port, and typing on the keyboard did nothing. Typed on the
   serial port, the passphrase unlocked the disk and the system reached the
   greeter, so the encryption itself worked. With `console=tty0` the prompt
   was on the screen, but as text: Plymouth draws only text while a serial
   console is active. With `plymouth.ignore-serial-consoles` too, the lyona
   splash drew its passphrase box, and the passphrase typed there reached the
   greeter. x86_64 does not have this: its default console is the display.

## The firmware boot entry, and what removed it

After the ext4 install the disk alone first started the UEFI shell, although
the postinstall's log said "Added the firmware boot entry "lyona" for /dev/vda
partition 1", and `bcfg boot dump` showed no `lyona` entry. Proven to be the
test machine, not the installer:

| Boot | Firmware variables | Result |
| --- | --- | --- |
| The entry made again from the installed system with the postinstall's command, the disk alone | as left | `Boot0007 "lyona"` started; login |
| The medium attached as the launcher gives it, `bootindex=0`, then the disk alone | as left by that boot | UEFI shell; no `lyona` entry |
| The entry restored; the medium attached without `bootindex` | with the entry | `Boot0007 "lyona"` started, before the medium |
| Then the disk alone | as left by that boot | `Boot0007 "lyona"` started; login |

With a `bootindex`, QEMU hands the firmware a boot order, and the firmware
deletes the boot entries that are not in it. The postinstall's reboot with the
medium still attached, as its closing screen asks ("Leave the install medium
in until the screen goes dark"), is such a boot. A real machine has no QEMU
boot order. A VM launched with one, with the medium first, starts the
installer again; following the closing screen ("remove the medium and
restart") then reaches AAVMF's UEFI shell, since the entry is gone and the
firmware's own order put its shell before the disk. Fresh variables boot the
disk. Whether UTM and Parallels launch their VMs that way is for ARM2-05. The
LUKS runs below used the medium without `bootindex`.

## Runs

The medium is ARM2-02's, rebuilt from `main` at `71facce` (#45):
`lyona-2026.10.0-beta.6-aarch64.iso`, 1,436,813,312 bytes, SHA-256
`8691c134d1c87ec327d06045772bdaf982de19ec8518ad05988ec08eb8d21180`; its
`/etc/lyona-iso-release` names that commit. Each run copied this branch's
wizard and postinstall onto it (checked by SHA-256) and answered the wizard
from a file through a stand-in for `gum`'s questions; every screen and step
otherwise ran as a user's would. On the medium: archinstall 4.5-1,
`linux-aarch64` 7.2.11-1, GRUB 2.16-1, efibootmgr 18-4,
`archlinuxarm-keyring` 20240419-2.

Machine: QEMU 8.2.2 with KVM, `virt`, 8 vCPUs on GB10's Cortex-X925 cluster,
8 GiB, the ISO as a USB stick, a 32 GiB virtio disk, virtio-gpu, AAVMF
2024.02 without Secure Boot.

Answers: keyboard English (US), `/dev/vda`, the filesystem, user `spike`,
hostname `lyona-arm`, no online timezone lookup, Europe/Berlin, the
suggested mirrors, "Wipe /dev/vda and install".

| Run | Result |
| --- | --- |
| ext4, first try | archinstall done in 1 m 26 s; the postinstall failed at NetworkManager ("unknown trust"): finding 1 |
| ext4 | all 14 steps done, postinstall 3 m 08 s, no warnings, the automatic reboot. The disk boots: with the live session's variables through the `lyona` entry (after the table above), with fresh variables through the disk's removable path (`UEFI Misc Device`). Both reach the lyona LightDM greeter |
| ext4 + LUKS | archinstall done in 2 m 33 s; all 14 steps done, 4 m 22 s, no warnings. The reboot, with the medium attached, started `Boot0008 "lyona"`: the prompt on the serial port only (finding 2). Unlocked there, the greeter |
| ext4 + LUKS, the console fix by hand | `console=tty0`, then also `plymouth.ignore-serial-consoles`, in a drop-in on that system: the splash's passphrase box on the screen; the passphrase typed on the keyboard reached the greeter |
| ext4 + LUKS, with the fix | a fresh disk and fresh variables: all 15 steps done, 3 m 53 s, step 6 "Putting the console on the display". The reboot started `Boot0008 "lyona"`, and the splash's passphrase box was on the screen; typed on the keyboard, the passphrase reached the greeter. The command line ends `quiet console=tty0 plymouth.ignore-serial-consoles splash`; `/proc/consoles` has `tty0` first, then `ttyAMA0`. With fresh variables again, the disk's removable path (`UEFI Misc Device`), the same box, the greeter |

## Tests

`tests/test-iso-install-aarch64.sh` (`make check-iso-install-aarch64`, new)
loads the wizard as a library on both architectures, with every command that
would touch the machine a stub, and checks each change above: the questions
asked and skipped, both archinstall configurations, the CachyOS steps, the
kernel copy (copied, a stale copy replaced, a current one left, no kernel a
failure), the firmware entry (the `efibootmgr` calls, an earlier entry
replaced and a similar name left, no UEFI a no-op, no GRUB a failure), the
console drop-in (its line, once on a second run, no command run in the new
system), and that each aarch64 step runs on aarch64 only, in its place.
`tests/test-iso-install-warnings.sh` checks the aarch64 step count against the
`run_logged` calls.

Run on aarch64 in the Arch Linux ARM CI container (on all 20 cores: `taskset`
on `ci-local.sh` does not reach the container, as found on 2026-10-23 for
Lyona#447; this said "two pinned cores" until ARM2-04):
`check-iso-install-aarch64`, `-warnings`, `-recovery`, `-credentials`,
`-mirrors`, `-wifi` and `check-archiso` passed. `check-archiso` first failed
on a `grub-mkconfig` the console step ran itself, against #246's one
regeneration in `install.sh`; the step now leaves it to the theme step, as
the splash does. shellcheck 0.10.0 (`-S warning`) and shfmt 3.10.0: no new
warning, no diff. The x86_64 tests are unchanged; the Full suite's x86_64 job
runs them.

## Not tested

- btrfs, with or without LUKS (ARM2-05 installs btrfs on each machine).
- UTM and Parallels: no Mac is available (ARM2-05).
- A real aarch64 machine, and Secure Boot.
- If `install.sh` fails before its GRUB theme step, `grub.cfg` keeps
  archinstall's command line, without `console=tty0`, so an encrypted aarch64
  system asks for its passphrase on the serial port only. The splash has the
  same dependency on that step.
- A VM launched with a QEMU boot order (`bootindex`) loses the `lyona` entry
  at the postinstall's reboot (above); nothing in the installer can keep it
  there. ARM2-05 checks how UTM and Parallels launch.
- ARM2-04's mirrors (the run used the medium's Arch Linux ARM mirrorlist
  unchanged) and its keyring check.
