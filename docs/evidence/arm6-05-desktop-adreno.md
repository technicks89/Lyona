# ARM6-05: the desktop on Adreno X1

Dell XPS 13 9345, installed from `new13` (kernel 7.3.3-1-aarch64-ARCH,
Mesa 26.2.6, Picom 13, 2560x1600 internal panel, 31 GiB), measured over SSH on
2026-11-11 with `tests/measure-picom-cost.sh --no-use --seconds 60`, one run
per backend. Desktop at rest, one window open.

## Picom (item 1)

| Backend | Picom CPU idle | Picom RSS | Quickshell | Xorg | Capture of the one window |
| --- | --- | --- | --- | --- | --- |
| stopped | - | - | 0.00%, 167 MiB | 0.00%, 89 MiB | - |
| xrender | 0.00% | 6.0 MiB | 0.00%, 167 MiB | 0.02%, 89 MiB | 9 ms |
| glx | 0.00% | 63.3 MiB | 0.00%, 167 MiB | 0.00%, 89 MiB | 10 ms |

- Picom starts and runs with GLX on this machine: no error, no fallback, 0%
  CPU idle. Whether it is the Adreno GPU (msm, freedreno) or software GL
  was not checked (`glxinfo` is not installed on the XPS).
- The Automatic policy chose `xrender` here: the helper reported
  `renderer unknown`, and Automatic uses GLX only for Intel and AMD
  (`scripts/dwm-settings-picom`, `backend()`). So the default session runs
  Picom on XRender, which the previews need only for being on at all (#244).
- Machine load at rest: 0.06% busy, load average 0.00.

## Not measured yet

- The overview with many windows, and a real browser or video player under
  Picom.
- The GL renderer name (see the load test: the evidence points at the Adreno
  but does not prove it).
- Whether Automatic should pick GLX for the Adreno (needs the renderer
  identified and a use sample).
- Idle numbers against the Pi 4 and x86_64 with the same window count.

## Settings backends (item 3), read-only over SSH

The helpers' read paths, run over SSH with `DISPLAY=:0`; the Settings panes
themselves were not opened (that needs someone at the screen), and nothing was
changed (no brightness, profile or suspend write).

- **Battery:** `qcom-battmgr-bat` is present; UPower shows the battery (DELL
  J7H5M44Q, 55 Wh, 100%, 11 cycles, 12.7 V, 30 C, charge thresholds 75% to
  80%). `power-snapshot` reports `power-battery available full 100` and
  external power on. UPower's `energy-full-design` reads 0 Wh (sysfs says 55 Wh
  full design), so a wear figure based on it would be wrong here.
- **Power profiles:** `power-profiles-daemon` is active with a `placeholder`
  platform driver: only `balanced` and `power-saver`, no `performance`. The
  helper lists both and `balanced` active; changing the profile was not tried.
- **Brightness:** `/sys/class/backlight/dp_aux_backlight` (0 to 1023, now
  1023) and `brightnessctl` see the internal panel. Setting it was not tried.
- **Suspend:** `/sys/power/mem_sleep` is `s2idle [deep]`, logind and UPower
  active, lid policy `suspend` owned by logind, `power-suspend available
  delegated`. An actual suspend and resume was not tried.
- **Display:** `eDP-1` 2560x1600 at 60 and 120 Hz, DP-1 and DP-2 disconnected,
  DPI 150 saved.
- **Screen lock:** `power-lock unavailable` ("light-locker needs a LightDM
  login, and this session has none") although light-locker is running in the
  session. The check was run from an SSH shell, so this may be the SSH
  environment and not the desktop; recheck from a terminal on the screen.
- **Journal:** no user-journal errors this boot except two `sudo` password
  prompts from my own probes.

## Picom under load (2026-11-11)

Over SSH, `DISPLAY=:0`, 2560x1600 panel: two alacritty windows printing text
and moved about 18 times a second (`xdotool windowmove`) plus a 1280x720
30 fps mpv `testsrc2` window (`--vo=x11`), for 40 s each, with Picom off, on
xrender and on glx, lyona's default Picom configuration. CPU is share of one
core over the 40 s; the GPU rows are time per clock frequency from
`/sys/class/devfreq/3d00000.gpu/trans_stat` (300 MHz is its lowest step).

| Picom | Machine busy (12 threads) | Picom | Xorg | Quickshell | Picom RSS | GPU time above 300 MHz |
| --- | --- | --- | --- | --- | --- | --- |
| off | 5.1% | - | 2.8% | 0.0% | - | 6% (687 MHz 4%, 1250 MHz 2%) |
| xrender | 7.8% | 0.9% | 5.4% | 0.0% | 5.7 MiB | 9% (687 MHz 9%, 1250 MHz 1%) |
| glx | 7.9% | 2.1% | 4.8% | 0.0% | 59.6 MiB | 0% (687 MHz 0.1%) |

- Both backends cost little under this load: 1 to 2% of one core in Picom,
  about 3 points of the whole machine, the desktop never above 8% busy. The
  video and the windows kept playing, and no error reached Picom's log.
- Is GLX on the Adreno? With GLX, Picom maps Mesa's `libgallium` and holds
  three `/dev/dri/card0` (the msm device) descriptors, and the GPU stays at its
  lowest clock for the whole run (this load is too light to raise it). That
  fits the hardware driver, but the renderer name was not read, so software GL
  is not strictly excluded (`kms_swrast` also opens the card).
- xrender raised the GPU clock more than glx did (9% against 0%): there the
  X server's glamor does the drawing.
- One run of each, 40 s, a light load. Not measured: the battery cost, a
  browser, a real 4K or 60 fps video, many windows.

## What this says for the Automatic policy

On this machine Picom on GLX is as cheap as on XRender, so GLX is usable on
the Adreno X1-85. The Automatic policy still chooses XRender (it names the
GPU "unknown"), which is the cheaper and safer default; no change is made
here. Choosing GLX for Qualcomm needs the renderer read and more than one
machine's numbers.

## Settings panes

Every Settings pane was opened on the XPS by the maintainer, and all worked
with no error (reported by the maintainer; no log kept).
