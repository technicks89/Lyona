# S11-08 -- a layout switcher in the Control Center

Plan: `docs/sprints/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md#s11-08-a-layout-switcher-in-the-control-center`. Issue `#159`.
Decision D-12 (2026-09-26). The only Sprint 11 item that changes the dwm C core.

## Change

- `dwm.c`: atoms `_DWM_LAYOUT` and `_DWM_SET_LAYOUT`; `updatelayoutprop()` publishes the
  selected monitor's layout index for its current tag, cached so it is written only on a
  change, and is called from `setlayoutshrink()`, `focus()` and `updatecurrentdesktop()`;
  `applylayoutrequest()` reads and deletes `_DWM_SET_LAYOUT`, range-checks it, and calls
  `setlayout()`; `propertynotify()` dispatches to it for a root-window change. About 54
  changed lines, no new dependency, nothing blocking.
- `scripts/dwm-quickshell-state`: `layout=` in `state`, `_DWM_LAYOUT` in both `xprop`
  reads that matter (the snapshot and the `watch` spy), and a `layout <index>` command.
- `DwmState.qml`: `layoutIndex`, `setLayout()`. `ControlCenterWindow.qml`: a required
  `dwmState`, a static `layoutChoices` list, and the "Window layout" row of
  `PresetButton`s. `shell.qml` passes `dwmState`.
- `docs/src/control-center.md`: describes the row.

## Results (2026-09-26, CachyOS, working tree, nothing committed)

- Fresh `make clean all` with the repo's `-std=c99 -pedantic -Wall`: no warnings.
- `check-xvfb-runtime`: PASS, now also asserting that `_DWM_LAYOUT` starts at 0; a request
  for 2 is applied; 7 and -1 change nothing; `_DWM_SET_LAYOUT` is consumed; another tag has
  its own layout (0), and returning to the first shows 2. Against the original `dwm.c` it
  fails with `expected _DWM_LAYOUT 0`.
- `check-quickshell-state`: PASS with `layout=2`, the command sending
  `-root -f _DWM_SET_LAYOUT 32c -set _DWM_SET_LAYOUT 2`, and `abc`, `-1`, `100`, `1 2` and
  the empty string refused before anything reaches `xprop` (fails when the parse is removed).
- Earlier, in a scratch copy: the real state script against the prototype dwm reported
  `layout=0`, then 2, then 1, ignored 9, refused `abc`, and its `watch` stream emitted a new
  block on a change; the hotkey path (`Super+f`, `Super+t`) and tag switching each updated
  the property.
- `check-quickshell-panel-menus`: PASS, pinning the wiring and one list entry per layout in
  `config.def.h`. Removing `dwmState: dwmState` from `shell.qml` fails it.
- `shellcheck` findings and `shfmt -d` are unchanged from before on every shell file touched.

## Not verified

- **The UI.** Nothing was clicked. Open the Control Center: the current layout's button is
  highlighted; each button re-tiles the windows; `Super+t` and `Super+f` move the highlight;
  switching tag shows that tag's layout.
- **More than one monitor.** The request applies to the selected monitor, as the hotkeys do;
  only one monitor was available.
- **A customised `layouts[]`.** The button list is static. A user's `config.h` with different
  layouts would map the buttons to the wrong ones; the count pin only checks the defaults.
- **Real client windows.** The prototype and the harness had none, so `arrange()` ran with
  nothing to arrange; the hotkey path calls the same function.
