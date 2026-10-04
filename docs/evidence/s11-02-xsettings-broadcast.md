# S11-02 -- broadcast the GTK and icon theme over XSETTINGS

Plan: `docs/sprints/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md#s11-02-broadcast-the-gtk-and-icon-theme-over-xsettings`. Issue `#153`.

## Change

`scripts/theme-apply.sh` writes `Net/ThemeName` and `Net/IconThemeName` into
`xsettingsd.conf` with the existing `xsettingsd_write_line()` (it preserves every
other line and sends `SIGHUP` to the daemon). New helpers `xsettings_string_ok()`
(no CR or LF, at most 1024 characters) and `xsettings_escape()` (quote and
backslash). The icon theme follows the `gtk2_set` rule: set when effective,
removed when the recorded baseline had none, untouched otherwise.

## Results (2026-09-26, CachyOS, working tree, nothing committed)

- `tests/test-dwm-settings-theme.sh` now also checks: `Net/ThemeName` present and
  equal to `gtk-theme-name` in `gtk-3.0/settings.ini`; two successive themes leave
  one `Net/ThemeName` and one `Net/IconThemeName` line, with `Xft/DPI` and the
  cursor keys intact; `We"ird\Name` is written as `We\"ird\\Name`; a name with a
  carriage return is refused with `not broadcasting an invalid GTK theme name` and
  the previous value stays. Passes.
- Mutation: the same test against the original `theme-apply.sh` fails.
- `check-appearance`, `check-gtk-theme`, `check-theme-apply-gtk-fallback`,
  `check-theme-apply-qt-palette`, `check-install`, `check-shell`, `check-format`: pass.
  `shellcheck` on `theme-apply.sh`: 1 finding, the same as before; `shfmt -d`: clean.

## Notes

- `personalization.conf` already refuses values over 128 characters, so the length
  limit in `theme-apply.sh` covers a `gtk_theme` that comes from `themes.toml`,
  which it does not bound.
- Upstream's part of `#351` that resolves which GTK theme to pick (Nordic,
  Dracula, Gruvbox-Dark ...) is not needed here.

## Not verified

A running GTK 3 application repainting when the theme changes. Open Thunar, switch
theme in Settings, and confirm it follows without a restart. The `xsettingsd`
daemon was a stub in the test.
