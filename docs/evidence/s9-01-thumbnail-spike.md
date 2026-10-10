# S9-01 -- live per-window thumbnails: spike outcome

Plan: `docs/sprints/SYNC-SPRINT-9-OVERVIEW-POLISH.md#s9-01-live-per-window-thumbnails-a-spike`. Issue `#350`. **Decided and built:** the spike below
answered feasibility; previews were then built as `dwm-window-thumb.c` (with
Sprint 9, `5e5faad`), which captures only while a compositor runs, and Picom was
made part of the desktop for them (#244, `5bd6907`; `docs/evidence/244-picom-required.md`).

## What was tried (2026-09-27, Xvfb 1024x768 and 3840x2160, real dwm, feh test window, nothing committed)

A throwaway C probe (kept out of the repository) captured one window two ways: `XGetImage` on the window itself,
and `XCompositeNameWindowPixmap` followed by `XGetImage` on that pixmap. Each was run against a window on the
visible tag (control) and after `xdotool set_desktop 1` made dwm's `showhide()` move it to `x = -2 * width`.
Two scenarios: no compositor, and Picom (`backend = "xrender"`).

| Scenario | Window | `XGetImage` on the window | Name-window-pixmap |
| --- | --- | --- | --- |
| no compositor | visible tag | real image | black |
| no compositor | off-tag | **BadMatch, no image** | black |
| Picom | visible tag | real image | black |
| Picom | off-tag | **real image** (300x200, many colours) | black |

- The name-window-pixmap path returned a uniform black image in every case, so it is not usable as tried.
- Capture cost with Picom, off-tag: about 15 ms for a 1024x768 screen (2.4 MB of raw pixels) and about 140 ms for
  3840x2160 (24.9 MB). Those figures include process start-up and writing a PPM; they are the cost of a whole-screen
  sized window, so a normal window is cheaper.

## What that means

- The plan's premise that `maim --window <id>` already does this is wrong: `scripts/dwm-screenshot` captures by
  geometry or selection, and `maim` is an optional package that is not installed here. The working call is plain
  `XGetImage`, which needs only libX11.
- Capturing an off-tag window works only while a compositor is redirecting it. Lyona ships Picom but treats it as
  optional (AGENTS.md); with no Picom, or with Picom stopped from Settings, there is no image and the card would need
  to keep today's icon-and-title layout. So thumbnails could only ever be an enhancement, not the card design.
- Whether Picom keeps a fresh pixmap for a window the user is not looking at (a window that repaints while off-tag)
  was not measured; a thumbnail would show the contents at the last time it was drawn, which may be stale.

## Decision needed before building

1. Is a Picom-only, best-effort thumbnail worth a new helper (a small C or `python-xlib`-free program using only
   libX11, called on demand while the overview is open, never while it is closed)?
2. Privacy: captured pixels are the contents of every window on every tag, including ones the user has hidden. They
   should stay in memory or in `$XDG_RUNTIME_DIR` (mode 0700), never in a persistent cache. The plan's "cache the
   last capture between overview opens" is only acceptable on that basis.
3. Cost at scale: the idle-CPU promise (S9-04) has to be re-measured with captures, and capturing every window when
   the overview opens is the cost to bound (on demand as a card scrolls into view).

Until then the icon-and-title card stays the design. Nothing in the repository changed for S9-01.
