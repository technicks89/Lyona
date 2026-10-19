# ARM1-06: `install.sh` on Arch Linux ARM, in a KVM virtual machine

ARM Sprint 1 item ARM1-06 (issue #6). Run 2026-10-19.

The sprint's last item: `install.sh` installs Lyona on an existing Arch Linux
ARM system and reaches a working desktop with no manual step. The plan named
the maintainer's Raspberry Pi 4 (2026-10-14). It was not available, so on
2026-10-19 the maintainer moved the Pi run to ARM3-06 and validated ARM1-06
in an Arch Linux ARM virtual machine under KVM on GB10 (see
`docs/sprints/ARM-SPRINT-1-FOUNDATION.md`). This validates `install.sh` on
aarch64 Arch Linux ARM. It does not validate a Raspberry Pi, or the generic
image's installer (ARM-2).

## The machine

| | |
| --- | --- |
| Host | NVIDIA GB10 (DGX Spark: 10 Cortex-X925 and 10 Cortex-A725 cores), its Ubuntu 24.04 based OS, QEMU 8.2.2 with KVM |
| Virtual machine | `virt` machine, 8 vCPUs (`-cpu host`) pinned to the host's Cortex-X925 cluster, 8 GiB, virtio-blk disk, virtio-gpu at 1920x1080, USB keyboard and tablet, Intel HDA audio, user-mode virtio network |
| Firmware and boot | UEFI (AAVMF, no Secure Boot), systemd-boot as `BOOTAA64.EFI` on a 1 GiB FAT ESP mounted at `/boot`, ext4 root |
| Root filesystem | `ArchLinuxARM-aarch64-latest.tar.gz`, signed 2026-08-05 by the Arch Linux ARM Build System key (`68B3537F39A313B3E574D06777193F152BDBE6A6`), SHA-256 `42a4eeaa038994ffd31fa173256ef2f0ef511358eeb41b9ea1f8626391b9b319` |
| Kernel | `linux-aarch64` 7.2.11-1 (7.2.11-1-aarch64-ARCH), after `pacman -Syu` |
| GPU and driver path | virtio-gpu, no virgl: Mesa's software renderer; Picom's automatic choice was the `xrender` backend |
| Lyona-ARM | `9d88128` (`main`, with #34) for the runs and the desktop checks; the fixes below were validated on the tree committed as `91773f9` |

## Before `install.sh`

Arch Linux ARM's own first steps: `pacman-key --init`, `pacman-key --populate
archlinuxarm`, `pacman -Syu` (77 packages, the kernel among them), `pacman -S
sudo git`, and a reboot onto the new kernel. The tarball's `alarm` user is
already in `wheel`.

Not done, and found to be needed (see Found): a locale. The root filesystem
ships `LANG=C`.

Unlike the plan, `wheel` had passwordless `sudo` and the three runs used
`--non-interactive`, so that they ran unattended. The NetworkManager question
was later answered at a real prompt (see Found).

## The runs

| Run | Command | Result |
| --- | --- | --- |
| Dry run | `./install.sh --profile recommended --dry-run --non-interactive` | Exit 0. No CachyOS, gaming or multilib. 33 required and 70 recommended packages |
| Recommended | `./install.sh --profile recommended --non-interactive` | Exit 0 in 168 s (packages 2 min 24 s). Two warnings, both by design: optional extras skipped, and no display manager for this profile |
| Full, over it | `./install.sh --profile full --non-interactive` | Exit 0 in 12 s, no warnings. 14 packages added (LightDM, slick-greeter and others), wallpapers downloaded. A second run changed nothing else |

## The desktop

The recommended profile through `startx` from a TTY (it installs no display
manager), the full profile through LightDM, then through `startx` on tty2
while the LightDM session ran.

| Check | Recommended, `startx` | Full, LightDM | Full, `startx` |
| --- | --- | --- | --- |
| The session starts: dwm and the panel | Pass | Pass | Pass: its own panel and Picom on `:1` |
| Launcher (Super+R) opens and starts an application | Pass (Alacritty) | Pass (Firefox) | Pass |
| Terminal (Super+X) | Pass | Pass | Pass |
| Overview with Picom: window previews | Pass | Pass | Pass |
| Overview without Picom: icon and title cards | Pass | Pass | Not repeated |
| Settings: every pane opens | Pass (all 9) | Pass (all 9) | Not repeated |
| Settings, System Information: names the CPU | "Arm Cortex-X925" | "Arm Cortex-X925" | - |
| Audio: a sound plays; the volume control works | Pass: written to the VM's audio capture; 65% shown in the panel | Pass; the volume was kept across the reboot | - |
| Network: connected; the panel shows it | Connected, but not shown: F-1 | The same: F-1 | The same: F-1 |
| Reboot, then log in again | - | Pass, no failed units | - |
| `lyona-update check` | Exit 0, "ahead" of 2026.10.0-beta.6 | The same | - |

Without Picom, the overview fell back to its cards with no crash. Picom stopped
mid-session raises no notice, by design: the notice is for a Picom missing or
failing at session start, and System Health reports it stopped.

## Idle cost

`tests/measure-picom-cost.sh --no-use` in the full profile's LightDM session,
300-second samples, one window, launcher closed:

| | Machine | Picom | Quickshell | Xorg |
| --- | --- | --- | --- | --- |
| Picom stopped | 0.06% busy | - | 0.01% CPU, 340.0 MiB | 0.00% CPU, 133.3 MiB |
| Picom running (`xrender`) | 0.04% busy | 0.00% CPU, 5.9 MiB | 0.00% CPU, 340.0 MiB | 0.00% CPU, 163.0 MiB |

Capturing the window as the overview does: 2 ms. This is a Cortex-X925, not
the Pi 4's Cortex-A72, so it says nothing about the lean bar (ARM3-06).

## x86_64

ARM1-06's acceptance also asks for the x86_64 Full suite still green. PENDING:
the Full suite workflow run on `91773f9`, and its x86_64 result.

On aarch64, the whole suite passed on the fixes, in the Arch Linux ARM
container (`scripts/ci-local.sh --base-image lyona-archlinuxarm:base-devel
--clang --each check`): 160 targets, 0 failed.

## Found

- **F-1, no network shown.** Arch Linux ARM enables systemd-networkd with two
  stock DHCP files. `install.sh` left NetworkManager off, as it does beside any
  other network manager, so the panel and Settings showed no network though the
  machine was online. Changed: on that exact setup, the installer asks after
  its summary (yes by default) to switch to NetworkManager at the next boot.
  An unattended run switches only with `--switch-to-networkmanager`. Validated
  in the VM at a real prompt: NetworkManager and its sockets enabled, networkd
  disabled, and after a reboot NetworkManager connected, the panel and Settings
  showed the network, and a re-run reported it already enabled. The first
  version missed the stock setup: the shipped files have a carriage return
  after `DHCP=yes`, and the test's fixture did not. The fixture now does.
- **F-2, the plan's columns.** "Recommended, LightDM" cannot happen: the
  recommended profile installs no display manager. Changed to
  "Recommended, `startx`".
- **F-3, the locale.** The session ran with `LANG=C`, and Qt warned that it
  switched to `C.UTF-8`. Changed: `docs/src/install.md` lists Arch Linux ARM's
  first steps, setting a locale among them. The installer is unchanged.
- **F-4, the measurement script.** `tests/measure-picom-cost.sh` printed no
  CPU name on aarch64, which has no `model name` in `/proc/cpuinfo`. Changed: it
  asks the parser System Information uses ("Arm Cortex-A725 + Arm Cortex-X925"
  on the host).
- **F-5, a slow Appearance pane.** Appearance appeared only at its 5-second
  loading cap. Settings' capability discovery ran `bluetoothctl show`, which
  waits out its 2-second timeout when no Bluetooth daemon runs (the VM has no
  adapter), and opening Appearance runs discovery twice. Changed: discovery
  asks the system bus whether a daemon owns `org.bluez` first. In the VM,
  discovery went from 3.9 s to 1.8 s, and Appearance appeared in about 2.6 s, on
  its data rather than the cap. Not specific to ARM: any machine without a
  Bluetooth daemon had it.

## Not tested

- A Raspberry Pi: its firmware boot and `linux-rpi`, the `v3d` GPU and Picom's
  glx backend, the Pi 4's speed (the lean bar), its Wi-Fi, Bluetooth and HDMI
  audio. Moved to ARM3-06.
- `sudo` with a password, and every prompt but the NetworkManager question.
- A real keyboard and display (input went through QEMU's keyboard, screenshots
  through QEMU).
- The iwd, ConnMan and dhcpcd guard on the network switch, added after the VM
  run: unit tests only.
- More than one display.
- The generic image and its installer: ARM-2. A Raspberry Pi 5 and the Pi image
  and its first-boot wizard: ARM-3. GB10 as a Lyona machine itself: ARM-4,
  deferred.
