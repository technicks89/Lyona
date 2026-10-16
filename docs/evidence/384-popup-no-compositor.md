# #384: shell menus without a compositor

Issue `#384`: with no compositor running (Picom stopped, or a Raspberry Pi 4,
where Picom cannot run), every `ClickAwayPopup` menu blacked out the screen
below the panel. Validated on 2026-10-16 with the branch
`fix/popup-no-compositor` (based on `main` at `107d68a`).

## Cause

`ClickAwayPopup` made each menu a popup window over the whole screen below the
panel, with a transparent colour, so that a click anywhere outside the menu
landed on it and closed the menu. Only a compositor shows a transparent window
as see-through; without one, X draws it black.

## What was tried

In a private Xvfb with dwm and Quickshell 0.3.2 (Qt 6.12):

- **Quickshell's `mask`** (a `Region` around the menu) shapes only the input on
  X11: outside the menu stayed black, and a click there went past the popup.
  It cannot give a visible menu with a click-catching surface around it, and
  Quickshell has no input-only window.
- **A popup the size of the menu** looks right. Quickshell holds no pointer
  grab on X11 (an `XGrabPointer` from another client succeeded while a popup
  was open), so an outside click goes to whatever is under it. What the popup
  sees is losing the keyboard. A click on an unfocused window did that (dwm
  focuses it). A click on the desktop, or on the selected window, did not: dwm
  had given the popup the keyboard and left the selected window's plain clicks
  ungrabbed, as a focused window's are.
- Qt closes most popups that lose the keyboard on its own, but not one whose
  `grabFocus` was false when its window was made: the overview's is bound to
  its model, and it stayed open after losing the keyboard.

## The fix

- **Two shapes, by compositor.** With a compositor, `ClickAwayPopup` is the
  full transparent surface, as before. Without one, its window is the menu
  alone, at the same place. `Compositor.running` (new singleton in `core/`)
  decides, and switches a menu that is open.
- **Compositor state, event-driven.** `dwm-window-thumb watch-compositor` prints
  `compositor 1` or `compositor 0` at start and whenever the
  `_NET_WM_CM_S<screen>` owner changes, from XFixes selection events (libxcb's
  `xcb-xfixes`, part of `libxcb`, already a dependency). One resident process,
  blocked on the X connection, run through `WatchedProcess` and
  `Commands.watchCommand` (ends with Quickshell). Unknown (helper missing, not
  reported yet, ended) counts as no compositor, the shape that looks right
  either way. `OverviewModel`'s existing compositor check (`dwm-window-thumb
  available`, exit 3/4 from a capture) is one-shot and only runs while the
  overview is open, so it could not be reused for this.
- **dwm** (`dwm.c`, 12 lines): while a popup holds the keyboard
  (`focusoverridewindow`), the selected window's buttons are grabbed as for an
  unfocused window, so a click on it focuses it; and a click on the desktop
  with a popup holding the keyboard calls `focus(NULL)`. Both clicks then take
  the keyboard from the popup. `focus()` restores the focused-window grabs.
- **`ClickAwayPopup`** dismisses when it loses the keyboard while open, shown
  and holding `grabFocus` (checked with `Qt.callLater`, after the focus change
  settles), and when it is hidden while its owner still wants it (Qt's own
  close). Owners set the new `open` property instead of `visible`, so the two
  can be told apart: before, a menu Qt closed left its model "open", and the
  next open took two clicks.
- **Overview:** no fade without a compositor (`fades`), where a part-transparent
  window draws dark.

## Static and lint checks

- `make check-quickshell-qml` (stock `qmllint` from Qt 6.12 with the script's
  explicit Qt and Quickshell import roots and the lint-only `qs.core` qmldir):
  passes. No new warning in the changed files except "Type Compositor not
  declared as singleton in qmldir", which every existing `core/` singleton
  (`Commands`, `Theme`, `Xdg`, `QueuedRun`) also gets.
- `shellcheck -x` (0.10.0) and `shfmt -d` (3.10.0) on the changed shell files:
  clean.
- `make all` with `-Wall -pedantic`, and `dwm-window-thumb.c` again with
  `-Wextra`: no warnings. `dwm-window-thumb` links `libxcb.so.1` and
  `libxcb-xfixes.so.0`; a bad argument exits 2 with the usage line, and no
  display exits 2.

## Tests (through `scripts/run-tests`, as an unprivileged user)

Run in an Artix Linux ARM container on an aarch64 host (Ubuntu 24.04),
with quickshell 0.3.2, qt6-base 6.12.0, picom 13, xorg-server-xvfb 21.1.25 and
libxcb 1.17.0. Every X server was the test's own Xvfb.

All pass: `check-quickshell-panel-menus`, `check-quickshell-overview`,
`check-quickshell-overview-xvfb` (58 assertions), `check-overview-keyboard-xvfb`,
`check-overview-load-xvfb`, `check-overview-thumbnails-xvfb`,
`check-window-thumb-xvfb`, `check-quickshell-settings-responsiveness-xvfb`,
`check-desktop-smoke-xvfb`, `check-quickshell-idle-watchers-xvfb`,
`check-dwm-activate-xvfb` (one and two screens), `check-dwm-bar-docks-xvfb`,
`check-quickshell-plain-text`, `check-quickshell-plain-text-xvfb`,
`check-quickshell-qml`, `check-session-isolation`, `check-diagnostics`,
`check-quickshell-tray`, `check-quickshell-notifications`,
`check-quickshell-xdg`.

`check-quickshell-controlcenter` and `check-quickshell-watcher-lifetime-xvfb`
fail in this container on `main` too, at the same place (the container's
theme detection, and "only 4 processes under Quickshell"), before anything
this change touches. The control center test's 106 `grep -Fq` source checks
were run on their own: all pass, including the updated `open:` one.

`tests/test-quickshell-panel-menus.sh` pins the wiring: `ClickAwayPopup`'s
shape follows `Compositor.running`, the keyboard-loss and hidden-while-open
dismissals, `Compositor` running `watch-compositor` with no timer, the helper's
XFixes selection events, all nine popups (and only nine) setting `open` and
never `visible`, the overview's `fades`, and both dwm hunks.

`tests/test-panel-popup.py` (part of `check-quickshell-panel-menus`) now checks,
with real clicks against the real `dwm` and a stub panel:

- without a compositor, the popup is the menu alone (280x300 at its place), a
  click on the menu keeps it, and a click on the desktop closes it and tells
  the owner;
- the same for a popup whose `grabFocus` is bound to `open`, as the overview's;
- a click on the selected window (feh) closes either popup and gives that
  window the keyboard back;
- with Picom: `watch-compositor` reports `0`, then `1`, then `0` and `1` again
  as Picom starts, stops and starts; the popup is the full surface and closes
  on an outside click; Picom stopping while it is open shrinks it to the menu,
  still open, and it still closes; Picom starting while it is open makes it the
  full surface again.

The new cases fail against `main`'s `dwm.c` ("Outside click did not dismiss
popup"), without the selected-window grab ("A click on the selected window did
not dismiss popup"), and without the keyboard-loss dismissal (the
`grabFocus: open` popup does not close).

The panel click check this test had passed whatever the click did: it looked
for the window id of the earlier showing, and a popup gets a new X window each
time it opens (checked: `4194334`, then `4194349`). It is removed; a click on
the panel is the panel's own `MouseArea` (S11-03).

## The real shell, in a private Xvfb

The managed shell from this branch (`config/quickshell`, helpers through
`LYONA_DEV_SCRIPTS`, the checkout's `dwm` and `dwm-window-thumb`) on Xvfb
1024x768 with a white root, as an unprivileged user, driven by IPC and
`xdotool`. "Outside" is a point on the far side of the screen from the menu.

| Case | `main` | This branch |
| --- | --- | --- |
| No compositor, control center, power, calendar, controls, network, overview | window 1024x738; pixel outside the menu black (0,0,0) | window the size of the menu (for example 276x432, 420x320); pixel outside white (the desktop) |
| No compositor, outside click on the desktop | closes | closes; one `toggle` opens it again |
| No compositor, outside click on the selected window (xterm), control center and overview | closes | closes; one `toggle` opens it again |
| Picom (xrender), control center, power, calendar, overview | full surface | full surface (1024x738), outside click closes, one `toggle` reopens |
| Picom stopped while the control center is open | (black) | shrinks to 276x432, stays open |
| Picom started while it is open | | full surface again; outside click closes |

Under Picom, the screen pixel reads black on both branches: with no wallpaper
set, Picom paints the root black itself, so it says nothing about the popup.
One `dwm-window-thumb watch-compositor` ran for the session, and none was left
after Quickshell exited. The Quickshell log had no QML errors or binding loops
(only PipeWire's, which the container lacks).

## Not tested

- A live lyona session on real hardware, with Picom stopped and started from
  the Control Center or `dwm-settings-picom` while a menu is open; and the
  menus' look there (only Xvfb screen reads, and the window geometry).
- The Raspberry Pi 4 (aarch64 here was a container on a server, with Xvfb, not
  the Pi's GPU or its Xorg).
- More than one monitor: the menus and the desktop click on another monitor
  (dwm already focused that monitor on such a click before this change).
- A click on a panel button while a menu is open without a compositor (the
  panel is in the same Quickshell process, and the popup keeps the keyboard
  then, as before).
- The tray menu and the Bluetooth and weather popups at runtime (same
  `ClickAwayPopup` code; only the six above were opened).
- Steam's menus, the other popups that ask dwm for the keyboard: a click on
  Steam's own window while one is open is now taken by dwm first (focus, then
  replayed to Steam), as a click on any unfocused window is.
