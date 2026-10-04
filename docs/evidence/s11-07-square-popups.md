# S11-07 -- square popups and a 1 px focus ring

Plan: `docs/sprints/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md#s11-07-square-popups-and-a-1-px-focus-ring`. Issue `#158`.
Decision D-10 (2026-09-26): square popups, and the focus ring goes to 1 px.

## Change

- `Theme.qml`: `popupRadius: 0`, `notificationAccentRadius: 0`,
  `controlFocusBorderWidth: controlBorderWidth`.
- `NotificationCard.qml`, `NotificationHistoryWindow.qml`: card radius is
  `Theme.popupRadius`.
- `tests/test-quickshell-accessibility.sh`: the focus-width pin follows the new
  definition. `tests/test-quickshell-design-system.sh`: pins the three radius
  values and the three components that use `Theme.popupRadius`.

## Results (2026-09-26, CachyOS, working tree, nothing committed)

`check-quickshell-design-system`, `check-accessibility`,
`check-quickshell-large-surfaces`, `check-quickshell-large-surfaces-xvfb`
(0.00% closed CPU), `check-quickshell-notifications`,
`check-quickshell-theme-contrast` (174 assertions) and `check-quickshell-qml`:
pass. `shellcheck` and `shfmt -d` clean.

## Not verified, and worth a look

- **Appearance.** Nothing was rendered. Open the launcher, control center,
  Settings and a notification on a light and a dark preset.
- **Square frames around rounded rows.** About 83 places still round their own
  corners inside popups (`controlRadius`, `largeSurfaceCardRadius`). If it looks
  odd, the follow-up is zero for those tokens too, which is a whole-shell change.
- **Emphasis borders that thinned.** `core/PanelSlider.qml:83` and
  `settings/AppearanceSettingsPane.qml` lines 361, 502, 737, 934 use
  `controlFocusBorderWidth` unconditionally, so they are now 1 px. If they read
  too weak, give them their own token.
- **Keyboard focus is now shown by colour only** (`controlFocusBorder`, the
  accent). Check it on a light and a dark preset; high-contrast mode keeps 2 px.
