# #244: Picom required, and the cost of window previews

Issue `#244`. Plan: `docs/plans/244/` (step 4: `04-validation.md`).

**Status: waiting for the old machine.** Staleness is answered; the overview
timing (development machine), the idle cost (development machine and a VM
without GPU acceleration) and a light normal-use load (the VM) are recorded,
and all of them pass. Still to come: the maintainer's run on old hardware, and
the development machine's normal-use sample (see below). The issue's validation
is blocking: it is not done until the old machine's numbers are in.

## How it was measured

- `tests/test-window-thumb-staleness-xvfb.py`: does Picom keep an off-tag
  window's picture current? In `make check` (`check-window-thumb-xvfb`).
- `tests/measure-overview-previews-xvfb.py`: real dwm, Picom (lyona's default
  configuration, XRender), the real `dwm-window-thumb` and the real overview in
  Xvfb (software rendering, 1920x1080), with 10, 60 and 200 real windows spread
  over the nine tags. Run by hand.
- `tests/measure-picom-cost.sh`: in a real session, idle and normal-use CPU and
  memory with Picom stopped (before) and running (after), and the cost of
  capturing every open window. Run by hand.

## Staleness: current (2026-10-07)

A window that redraws while it is off screen on a hidden tag is captured as it
is now. feh shows a red picture and reloads it every second; with the window on
a hidden tag, the picture is replaced with blue. The capture before was
`(220, 20, 20)`, and 2.5 s after the change `(20, 20, 220)`. Three runs, all
current. Picom keeps redirected off-screen windows up to date, so the
overview's capture on every opening shows the window as it is.

## Overview timing: development machine, Xvfb (2026-10-07)

AMD Ryzen 5 3600 (12 threads), 15 GiB, Radeon RX 9070 (unused: Xvfb renders in
software), Picom 13 with XRender. Branch `picom-required-previews`.

| Windows | First frame | All on-screen previews | On screen | Peak CPU: Quickshell / Picom / X server | Peak RSS: Quickshell / Picom | Back to idle |
| --- | --- | --- | --- | --- | --- | --- |
| 10 | 72 ms | 192 ms | 2 | 120% / 0% / 40% | 308 / 6.9 MiB | 1.0 s |
| 60 | 88 ms | 167 ms | 3 | 130% / 10% / 40% | 324 / 7.0 MiB | 1.0 s |
| 200 | 136 ms | 229 ms | 3 | 169% / 0% / 30% | 345 / 7.7 MiB | 1.0 s |

- Quickshell's idle CPU before opening was 0.0% in every run, as in the S9-04
  baseline, and it was back there within the first 500 ms window measured after
  closing.
- Peak CPU is the highest 100 ms sample while open: the burst of laying out the
  cards and decoding the previews, not a sustained load. Above 100% means more
  than one core.
- "On screen" is 2 or 3 because a card with a preview is tall at 1920x1080:
  only those are captured, which is why the time hardly grows with the window
  count.
- The 500 ms pass level for 60 windows is met with room to spare here; this is
  a fast machine, so it says little about old hardware.

## Real-session measurements (2026-10-08)

`tests/measure-picom-cost.sh` in a real lyona X session, with this branch's
`dwm-settings-picom` and lyona's default configuration. "Before" is Picom
stopped; "after" is Picom running as the helper starts it. CPU is the average
over the sample, as a share of one core (the machine figure is the whole
machine); memory is resident.

### Development machine: idle, 5 minutes each

AMD Ryzen 5 3600 (12 threads), 15.5 GiB, Radeon RX 9070, two monitors
(2560x1440 and 1920x1080), 6 windows. The automatic choice was GLX
(`picom --backend glx`, renderer `amd`). No `~/.config/picom.conf`, so lyona's
default was the configuration.

| | Picom | Quickshell | Xorg | Machine busy |
| --- | --- | --- | --- | --- |
| Before (Picom stopped) | - | 0.04%, 277 MiB | 0.02%, 61 MiB | 0.49% |
| After (Picom, GLX) | 0.01%, 74 MiB | 0.04%, 277 MiB | 0.04%, 61 MiB | 0.46% |

Capturing every open window, one at a time: 6 captured, 0 failed, 72 ms in
all, the slowest 19 ms.

### VM without GPU acceleration: idle (5 minutes) and a light load (60 s)

QEMU/KVM, 4 vCPUs (`-cpu host`, the same Ryzen), 3.8 GiB, virtio graphics
without 3D (software rendering), 1280x800, an image install with this branch's
helper and default copied in. The session's own autostart started Picom through
the new helper: `auto`, renderer `software`, so `picom --backend xrender`, with
`/usr/local/share/lyona/xdg/picom/picom.conf` as the configuration.

| | Picom | Quickshell | Xorg | Machine busy |
| --- | --- | --- | --- | --- |
| Idle, before | - | 0.00%, 323 MiB | 0.00%, 93 MiB | 0.55% |
| Idle, after (XRender) | 0.00%, 6.8 MiB | 0.00%, 323 MiB | 0.01%, 109 MiB | 0.44% |
| Light load, before | - | 0.02%, 329 MiB | 0.32%, 94 MiB | 2.76% |
| Light load, after | 0.50%, 6.9 MiB | 0.00%, 330 MiB | 0.73%, 101 MiB | 2.91% |

- The light load stands in for "normal use": a terminal typed into by
  `xdotool` and a 720p30 test video (`mpv`, `testsrc2`) playing. `mpv` used
  about 9% of one core. No browser scrolling. Picom added 0.5% of one core and
  Xorg about 0.4%; the machine as a whole, 0.15 points. No lag or tearing can
  be judged by eye in a headless VM.
- Xorg's memory grows by about 8 to 16 MiB with Picom running: the redirected
  windows' buffers.
- Capturing every open window: 4 captured, 14 ms in all, the slowest 5 ms.

### Development machine: normal use, not measured

The interactive sample was started but could not complete: during it, the
machine's local session became inactive (a LightDM greeter session became the
active one on the seat, as when the screen locks), and logind withdrew the
session's access to the GPU device. Every GL call on the display then blocked,
including `picom --diagnostics` and `glxinfo`, so the helper could not start
Picom again. That is the session state, not this change: it happens the same
way with an empty Picom configuration. It is worth knowing, though: while a
session is locked out of the GPU, starting or restarting Picom through the
helper waits for its 8 s diagnostics timeout and fails.

## Pass levels against these numbers

| Pass level (old machine) | Here |
| --- | --- |
| Idle: Picom + Quickshell under 1% CPU | Met on both: 0.05% (development machine), 0.00% (VM) |
| Normal use: Picom adds at most ~5 points | Met in the VM's light load: 0.5% of one core |
| Overview, 60 windows: previews within ~500 ms | Met on the development machine: 167 ms |
| Back to idle after closing within a few seconds | Met: within 1 s |
| Quickshell idle no higher than S9-04 | Met: 0.00 to 0.04% |

These are fast machines; the old machine's numbers decide.

## Still to run

| Machine | What |
| --- | --- |
| The maintainer's old or low-end machine | `tests/measure-picom-cost.sh` (with and without `PICOM_BACKEND=xrender` if it picks GLX) and `tests/measure-overview-previews-xvfb.py`; runbook in `docs/plans/244/04-validation.md` |
| Development machine, normal use | `tests/measure-picom-cost.sh` with the session active |

## Not tested

- Real old hardware and NVIDIA (pending above). GLX was only measured idle.
- Multiple monitors with previews: covered functionally by the overview's own
  tests, not measured here.
