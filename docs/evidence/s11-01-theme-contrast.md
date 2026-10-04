# S11-01 -- shell text readable on hover and selected surfaces

Plan: `docs/sprints/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md#s11-01-shell-text-stays-readable-on-hover-and-selected-surfaces`. Issue `#152`
(completes `#116`, Sync Sprint 6 S6-03).

## Cause

`Theme.surfaceHover` is the palette's `term_color8` (`dwm-settings-appearance`,
`'surface-hover|term_color8|selbgcolor'`), ANSI bright-black, and hover text was
`Theme.text` or `Theme.textStrong` on top of it. Measured from `config/themes.toml`
before the change, text on the hover surface: catppuccin-latte 1.62:1,
solarized-light 3.37:1 (strong text 1.00:1), rosepine-dawn 2.44:1, tokyonight-day
2.45:1, gruvbox-light 3.16:1, gruvbox 2.68:1, onedark 2.84:1, monochrome 3.21:1,
rosepine 3.91:1, tokyonight 4.23:1, dracula 4.41:1. All 5 light and 6 of 10 dark
presets were below 4.5:1. Upstream fixed the same cause in `#352`.

## Change

- `config/quickshell/core/Theme.qml`: `luminance()`, `readableText()`,
  `readableTextOnSurfaces()`, `lightHover()`; the nine menu and control text
  roles and a new `accentHoverText` use them; `applyAppearanceColors()` derives
  the light hover surface and a readable `accentText`. `luminance()` also accepts
  `#AARRGGBB` (how QML stringifies a colour with alpha), which upstream's does not.
- 13 components take upstream's patch unchanged (`ControlCenterWindow`,
  `BluetoothWindow`, `ControlsActionButton`, `MenuHeader`, `MenuRow`, `ShellButton`,
  `SystemHealthWindow`, `CommandMenuRow`, `LauncherCategoryRow`, `NetworkProfileRow`,
  `NetworkWifiRow`, `TrayItem`, `SettingsWindow`); `ControlsWindow` applied with
  fuzz and was read; `LauncherResultDelegate` was merged by hand (a `hovered`
  property and hover text on the name and category lines).
- Two upstream files do not exist in Lyona (`ControlCenterActionButton`,
  `ControlCenterOptionButton`); Lyona's `ControlCenterRow.qml` has no hover
  state and was left alone.

## Results (2026-09-26, CachyOS, working tree, nothing committed)

- `make check-quickshell-theme-contrast`: `Theme contrast tests: PASS (174
  assertions, 15 presets)`.
- Mutation: the same test against the original `Theme.qml` fails 105 of 174
  assertions across 14 of the 15 presets.
- `check-quickshell-design-system`, `-panel-menus`, `-controlcenter`,
  `-launcher`, `-overview`, `-overview-xvfb`, `check-quickshell-qml`: pass.
- `shellcheck` and `shfmt -d` clean on the new script.

## Not verified

- **Appearance.** These are contrast ratios, not renders. Look at a light preset
  and a dark one on the launcher, control center, network and Settings.
- Whether the black/white fallback looks right on a preset whose accent is
  mid-tone (it is chosen for contrast, not for taste).
