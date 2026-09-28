# S12-12 -- overview close asks the window, hidden windows, and thumbnail tests

Plan: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-12-overview-close-asks-the-window-hidden-windows-and-thumbnail-tests`.
Issue `#175`.

## Change

1. **Close asks the window.**
   - `dwm-quickshell-state close` runs `xdotool windowquit` instead of
     `windowclose`, which destroys the window without asking.
   - **Found while testing: the plan's one-line change is not enough.** With a
     window manager running, `windowquit` sends `_NET_CLOSE_WINDOW` to the root
     window, the request for the window manager to close it, and dwm ignored that
     message.
   - Measured under Xvfb: `windowquit` against the old dwm left the window open,
     but never asked it. The old `wmctrl -ic` fallback sends the same message, so
     it never worked under Lyona either.
   - Without a window manager, `libxdo` sends `WM_DELETE_WINDOW` itself. That
     misled an earlier manual check, whose scratch dwm build had failed.
   - `dwm.c` now handles `_NET_CLOSE_WINDOW` in `clientmessage`, through the new
     `closeclient(c)`. That function is `killclient`'s old body, and the close key
     now calls it too.
   - It asks with `WM_DELETE_WINDOW`, and kills only a client that does not support
     that, exactly as the close key does.
   - `NetCloseWindow` joins the atom list, so `_NET_SUPPORTED` advertises it.
2. **Every managed window is listed.**
   - The snapshot's `owner_uid(pid) == 0` filter is removed from both `windows=`
     and `apps=`. It came from upstream, with no recorded reason.
   - Any client could set `_NET_WM_PID` to a root-owned PID and vanish from the
     overview and the task list. It also hid graphical tools run as root
     (`sudo gparted`).
   - The shell's own panels were never covered by it; they are user-owned.
   - With nothing reading it any more, `_NET_WM_PID` is no longer queried.
3. **The thumbnail tests run.** `tests/test-window-thumb-xvfb.py` and
   `tests/test-overview-thumbnails-xvfb.py` are now executable, with
   `check-window-thumb-xvfb` and `check-overview-thumbnails-xvfb` (exit 77 is a skip)
   in `make check`.

## Results (2026-09-28, CachyOS, working tree, nothing committed)

- **`tests/test-overview-close-xvfb.py`** (new, `make check-overview-close-xvfb`).
  - It runs the real dwm, and Tk windows whose `WM_DELETE_WINDOW` handler records
    the request and refuses to close.
  - `dwm-quickshell-state close` asked the window, and it stayed open.
  - `xdotool windowclose`, the old command, run on a second window, destroyed it
    unasked.
  - Against the old dwm with the new script: not asked (that is how the missing
    `_NET_CLOSE_WINDOW` handling was found).
  - Tk has to be the window's own client: the `wm frame` id is not the window dwm
    manages, so the test finds it by title.
- **`tests/test-quickshell-state-close.sh`:** the `xdotool` stub accepts only
  `windowquit`, and the checks name it.
- **`tests/test-quickshell-state.sh`:**
  - The window claiming pid 1 (`0xdd`, "Root App") is now expected in `apps=` and
    `windows=`, in the snapshot and in the three `watch` states.
  - The test no longer needs pid 1 to be root-owned, which made it fail in a
    sandbox (`docs/evidence/s8-01-overview-keyboard-nav.md`).
  - The per-window `xprop` batch no longer names `_NET_WM_PID`.
  - It fails against the old script.
- **`check-window-thumb-xvfb`** and **`check-overview-thumbnails-xvfb`**: PASS.
  Both were already correct, just never run.

## Not verified

- **Closing a real application** with unsaved work (an editor), rather than a Tk
  window that refuses.
- **A client without `WM_DELETE_WINDOW`** is killed on `_NET_CLOSE_WINDOW`, as with
  the close key. That path was not exercised.
