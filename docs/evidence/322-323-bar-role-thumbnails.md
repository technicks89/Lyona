# #322 and #323: the bar's declaration and server-side previews, validated

Branch `bar-role-thumbnails-322-323`, with the CodeRabbit follow-ups (the
thumbnail fallback after a Render error, `scanaltbars()` keeping a shown bar,
and docks in `scan()`'s transient pass).

## What Quickshell sets on X11

Probed under Xvfb with Quickshell 0.3.1: a `PanelWindow` is a dock
(`_NET_WM_WINDOW_TYPE_DOCK`) with no `WM_CLASS`; `exclusiveZone: 30` sets
`_NET_WM_STRUT_PARTIAL` (30 at the top, across the width) and `_NET_WM_STRUT`,
and `ExclusionMode.Ignore` sets neither. So dwm's old `quickshell` class match
never matched, and the bar was chosen by "a dock wider than tall". The strut is
the panel's declaration now.

## Suite

Each of the 152 steps of `make check` was run on its own through
`scripts/run-tests`: 152 of 152 passed, none skipped, no process left behind.
The CodeRabbit follow-ups came after it; the steps they touch were run again
and pass: `check-dwm-bar-docks-xvfb`, `check-xvfb-runtime`,
`check-window-thumb-xvfb`, `check-overview-thumbnails-xvfb`,
`check-dwm-activate-xvfb`, `check-monitor-tags`, `check-session-scripts-xvfb`.

Against the code before the change: the new bar test fails (a 40-pixel dock with
no strut took the bar's place). `test-xvfb-runtime.sh`'s fake panel was a 1x1
window of class "quickshell", the old guess; it now declares itself as the real
panel does (a dock with a strut).

Thumbnails under Xvfb with Picom, a 4K window, 20 captures each: 6 ms per
capture scaled by the server against 23 ms on the client. A first version used
one 15x15 box convolution on the server: 43 ms, with the server serving no one
meanwhile; the halving chain replaced it.

## The VM (2026-10-09)

| | |
| --- | --- |
| Image | `lyona-2026.10.0-beta.6-x86_64.iso`, SHA-256 `9956f9f10da9bc5d12b88dd9c6edd2ec6a9bced471dd804f3f52686c3144bc32` |
| VM | QEMU with KVM, q35, 4 GB, 4 CPUs, OVMF (UEFI), `-vga std` 1280x800 (modesetting, no GPU acceleration), virtio disk 32 GB, no NVIDIA |
| Install | the image wizard (us, btrfs, no encryption) |
| Branch | `make release` of the working tree, installed with `lyona-update apply --file` (no mismatch), then a new login; the installed `dwm-window-thumb` links libXrender |

- **The 96 desktop checks** of the earlier runs: all pass.
- **#322, the bar:** the real panel is the one dock that reserves space (its
  strut is its height, 30); a new window starts below it; after a shell reload
  (its config touched) one panel is still the bar, the window is still below it,
  and dwm used 0 ticks in 6 s (no raising war); with two monitors each has a
  panel reserving space and a window on the second starts below its panel; back
  to one monitor, one panel.
- **#323, previews on Xorg with Picom:** a 1100x650 window gives a 256x154
  preview; the server and client paths agree (mean difference 0.00); a window on
  another tag is captured. Time, 10 captures each: 27 ms against 25 ms at
  1100x650, 27 ms against 26 ms at 1270x760: the same at this size, with a
  twentieth of the data read.
- **PR 2's checks** (#318 to #321): all 23 pass again.

## Not tested

- Real hardware, a GPU-accelerated X server (glamor), two physical outputs.
- A window larger than the VM's 1280x800 screen in the VM; 4K was measured under
  Xvfb only.
- `scanaltbars()` keeping a shown bar against a lower one, and a transient dock
  at startup: covered by reading the code, not by a dedicated test.
