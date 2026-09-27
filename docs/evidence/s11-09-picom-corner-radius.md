# S11-09 -- a Picom window corner-radius slider

Plan: `docs/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md#s11-09`. Issue `#160`.
Decision D-12 (2026-09-26): a corner-radius slider, no dwm change.

## Change

- `scripts/dwm-settings-picom`: `CORNER_RADIUS_MAX = 32`, `Configuration.corner_radius()`,
  the `set-corner-radius` action (in `mutate()` and the argument parser), the
  `corner_radius` status field, a refusal to edit while Picom runs with `--corner-radius`,
  and a sentence in the status detail.
- `PicomModel.qml`: default `corner_radius: 0`, response validation that tolerates a missing
  field from an older helper, and `setCornerRadius()`.
- `PicomSettingsPane.qml`: the slider (`picomCornerRadius`, 0 to 32) with its own debounce
  timer and state, so it does not interfere with the opacity sliders.
- `docs/src/theming.md`: documents the slider and its caveats.

## Results (2026-09-26, CachyOS, working tree, nothing committed)

- `make check-picom`: 56 tests OK (51 existing plus 5 new). Two mutations fail the new
  tests: dropping the range check, and not removing the entry at 0.
- `make check-picom-xvfb`: all PASS, including the new
  `corner radius is set, replaced and cleared through the pane`, which goes through the
  real helper and the real QML pane. With the model's command name broken it fails at
  `QML corner radius mutation did not converge`.
- `check-quickshell-appearance-model` (new source pins), `check-quickshell-picom-model-xvfb`,
  `check-quickshell-settings-loading`, `check-quickshell-qml`, `check-shell`,
  `check-format`: pass.
- Real Picom v13 accepts `corner-radius = 8;` with `--backend xrender --diagnostics` and
  with `glx` (the helper validates with the `xrender` command). `--diagnostics` also exits
  0 for `corner-radius = "eight";`, so the helper's integer check is the guard.

## Not verified

- **The rounding itself.** Xvfb has no compositing (EGL errors in Picom's diagnostics).
  On a real session, check a tiled window, a floating window, a window with dwm's border
  and a fullscreen window (which should stay square), on each backend the machine supports.
- **How Picom clips dwm's 1 px X border** at a rounded corner.
- **The slider under a real mouse or keyboard.** The harness drives the pane's own edit
  path (`applyCornerRadius()`), not the `Slider` control's `onMoved` handler.
