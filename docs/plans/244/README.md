# #244: Picom required, and live window previews in the overview

Issue `#244`. Plan written 2026-10-07, on branch `picom-required-previews`.
One file per intended commit, each with the code it adds and removes.

## Where the issue stands against the code

Most of Part 2 (live previews) already landed in Sync Sprints 9, 12 and 16.
The issue was written against the S9-01 spike, which stopped before building
it. What exists today:

| Issue item | State | Where |
| --- | --- | --- |
| Capture helper, plain `XGetImage`, libX11 only | Done | `dwm-window-thumb.c` |
| Capture only while the overview is open, only on-screen cards | Done | `OverviewModel.qml` (`requestThumbnail`, `pumpThumbnails`), `WindowOverview.qml` |
| Downscale at once, never keep full-size pixels | Done | `dwm-window-thumb.c`: fits 256x160, reads 4 MiB bands |
| Previews only under `$XDG_RUNTIME_DIR`, 0700/0600, purged on close | Done | `dwm-window-thumb.c`, `OverviewModel.purgeThumbnails()` |
| Icon-and-title card first, and whenever a capture fails | Done | `OverviewCard.qml`, `thumbnailsAvailable` |
| Refresh when the overview opens, not an old copy | Done | Purged on every close, so every opening captures again |
| Window closing mid-capture, many windows, off-tag, multi-monitor | Done | `tests/test-overview-thumbnails-xvfb.py`, `tests/test-overview-close-xvfb.py` |
| Staleness of Picom's image of an off-tag window | **Not measured** | Step 4 |
| Picom required: installers | Done in practice | `picom` is in `arch:desktop`, part of the required batch for the recommended and full profiles |
| Picom required: checks report a missing Picom as an error | **No** | `dwm_command_tier desktop`: a warning; health report: "Optional compositor" |
| Autostart always starts Picom through `dwm-settings-picom` | Done | `scripts/autostart.sh` |
| One clear message when Picom cannot start | **No** | autostart discards the helper's output |
| What "Stop" means | **To decide** | Settings has no Stop button; the Control Center has "Restart Picom"; `toggle-compositor` is a command-line action only |
| Lean default config: no shadows, fading, blur | **No** | lyona ships no `picom.conf`; Arch's `/etc/xdg/picom.conf` has `shadow = true` and `fading = true` |
| dwm never depends on Picom | Done | nothing in the C code |
| Docs and migration note | **No** | Step 3 |
| CPU/GPU validation (blocking) | **No** | Step 4 |

So the work is Part 1, the staleness measurement and the validation.

## Decisions (2026-10-07)

1. **Where Picom is required:** wherever the lyona desktop is, that is the
   recommended and full profiles (Quickshell installed). The core profile stays
   minimal: no Picom, and its checks do not report it.
2. **The lean default:** lyona ships its own `picom.conf`, used when the user
   has none. The package's `/etc/xdg/picom.conf` is left alone.
3. **Old hardware:** the maintainer runs the old-machine measurements with the
   script from step 4. The VM without GPU acceleration and this development
   machine are measured here.
4. **Stopping Picom:** a troubleshooting action only. "Restart Picom" stays in
   the Control Center; `dwm-settings-picom stop|toggle` and the Control Center's
   `toggle-compositor` action stay, and say that previews are off until Picom
   starts again. No new UI.

## A behaviour change to watch: the backend

Arch's `/etc/xdg/picom.conf` sets `backend = "xrender"`, so today
`dwm-settings-picom` never applies its automatic choice: everyone runs XRender.
lyona's default leaves `backend` unset, so the automatic choice SPEC 5.10.1
describes takes effect: GLX on an accelerated Intel or AMD renderer, XRender for
NVIDIA, software rendering or unknown hardware, with one XRender retry if GLX
fails. That is what the issue asks for, but it moves accelerated Intel and AMD
machines from XRender to GLX. Step 4 measures both on the old machine. If GLX
costs more there, the default sets `backend = "xrender"` instead (one line,
step 1).

Picom 13 refuses to start without a backend. `dwm-settings-picom` always passes
`--backend` (checked on Xvfb: `picom --backend xrender`), and autostart, the
Control Center and Settings all start Picom through it. A `picom` started by
hand with lyona's default and no `--backend` fails with Picom's own message;
the troubleshooting page says to use `dwm-settings-picom start`.

## Order

| Step | File | Commit |
| --- | --- | --- |
| 1 | [01-lean-default-config.md](01-lean-default-config.md) | lyona's lean `picom.conf`, found ahead of the package's |
| 2 | [02-picom-required.md](02-picom-required.md) | Checks, health report, the start-failure message, stop wording |
| 3 | [03-docs-and-migration.md](03-docs-and-migration.md) | AGENTS.md, SPEC.md, docs, CHANGELOG with migration notes |
| 4 | [04-validation.md](04-validation.md) | Staleness, the measurement scripts, the evidence doc |

Steps 1 to 3 are independent of the hardware results. Step 4's numbers decide
whether the issue closes, and whether step 1's backend line changes.

## Not in scope

- Removing the `configure_quickshell_picom_opacity` edit of
  `/etc/xdg/picom.conf` in `install.sh`. With lyona's default in front, that
  file is no longer read by default, so the edit only matters for a user who
  points Picom at it. Removing it is a follow-up, kept out of this change.
- New Settings UI for Picom.
- Wayland.
