# ARM1-06: `install.sh` on Arch Linux ARM, on a Raspberry Pi 4

ARM Sprint 1 item ARM1-06 (issue #6). PENDING: the date of the run.

The sprint's last item: `install.sh` installs Lyona on an existing Arch Linux
ARM system and reaches a working desktop with no manual step. The machine is
the maintainer's Raspberry Pi 4 (decided 2026-10-14; see
`docs/sprints/ARM-SPRINT-1-FOUNDATION.md`). The Pi boots through its own
firmware, not UEFI, with Arch Linux ARM's Pi kernel, so this validates
`install.sh`, not the generic image's boot path (ARM-2).

Every value marked PENDING is filled in from the run; each says where it comes
from.

## The machine

| | |
| --- | --- |
| Board | PENDING: Raspberry Pi 4 Model B, its memory (`free -h`) |
| Storage | PENDING: SD card or USB disk, its size |
| Display, keyboard, mouse | PENDING: the monitor's resolution over HDMI, USB keyboard and mouse |
| Network | PENDING: Ethernet or Wi-Fi |
| Root filesystem | PENDING: the Arch Linux ARM Raspberry Pi aarch64 tarball's name, its date, and its SHA-256 (`sha256sum`) |
| Kernel | PENDING: `uname -r` and the kernel package (`pacman -Qo /boot/Image` or `pacman -Q linux-rpi linux-aarch64`) |
| GPU and driver path | PENDING: `glxinfo -B` (renderer and Mesa version), under the running session |
| Lyona-ARM | PENDING: the commit `install.sh` was run from (`git rev-parse HEAD`) |

## Before `install.sh`

Arch Linux ARM's own first steps, not Lyona's: the keyring initialised and
populated (`pacman-key --init`, `pacman-key --populate archlinuxarm`), the
system upgraded (`pacman -Syu`), `sudo` and `git` installed, a user in
`wheel` with `sudo` rights, and a locale set (`locale-gen`, `localectl
set-locale`), since the root filesystem ships `LANG=C` (docs/src/install.md).
`install.sh` runs as that user, never as root, with `sudo` asking for its
password.

PENDING: anything else that was needed before `install.sh` could run. Each
such step is a finding: ARM1-06 asks for no manual step.

## The runs

| Run | Command | Result |
| --- | --- | --- |
| Dry run | `./install.sh --profile recommended --dry-run` | PENDING: the install summary it printed for aarch64: no CachyOS, no gaming, no multilib |
| Recommended | `./install.sh --profile recommended` | PENDING: exit status, time, warnings. It asks to switch from Arch Linux ARM's systemd-networkd to NetworkManager: answer yes |
| Full, over it | `./install.sh --profile full` | PENDING: exit status, time, warnings. Also checks that a second run is safe (`AGENTS.md`: idempotent) |

PENDING: the installer's log or the end of its output for each run.

## The desktop

Checked after each profile: the recommended profile through `startx` from a
TTY (it installs no display manager), the full profile through LightDM, then
through `startx`.

| Check | Recommended, `startx` | Full, LightDM | Full, `startx` |
| --- | --- | --- | --- |
| The session starts: dwm and the panel | PENDING | PENDING | PENDING |
| Launcher (Super+R) opens and starts an application | PENDING | PENDING | PENDING |
| Terminal (Super+X) | PENDING | PENDING | PENDING |
| Overview with Picom: window previews | PENDING | PENDING | PENDING |
| Overview without Picom: icon and title cards, told once | PENDING | PENDING | PENDING |
| Settings: every pane opens | PENDING | PENDING | PENDING |
| Settings, System Information: names the CPU (Cortex-A72, ARM1-04) | PENDING | PENDING | PENDING |
| Audio: a sound plays; the volume control works | PENDING | PENDING | PENDING |
| Network: connected; the panel shows it | PENDING | PENDING | PENDING |
| Reboot, then log in again | PENDING | PENDING | PENDING |
| `lyona-update check` | PENDING | PENDING | PENDING |

## Idle cost

`tests/measure-picom-cost.sh --no-use` in the full profile's session, launcher
closed, nothing else running: idle CPU and memory with Picom stopped and with
Picom running. The Pi 4 is the project's lean bar (`ARM64.md`).

PENDING: the summary it writes (`summary.txt`).

## x86_64

ARM1-06's acceptance also asks for the x86_64 Full suite still green. PENDING:
the Full suite run on the commit above, and its x86_64 result.

## Found

PENDING: every problem met, what was changed for it, and what was not.

## Not tested

- The generic image and UEFI boot: ARM-2.
- A Raspberry Pi 5, and the Pi image and its first-boot wizard: ARM-3.
- GB10: ARM-4, deferred.
- PENDING: anything above that could not be checked, and why.
