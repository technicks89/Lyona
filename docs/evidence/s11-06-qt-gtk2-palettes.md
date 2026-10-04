# S11-06 -- Qt palettes for qt5ct/qt6ct and a GTK 2 theme

Plan: `docs/sprints/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md#s11-06-qt-palettes-for-qt5ctqt6ct-and-a-gtk-2-theme`. Issue `#157`.

## The fault (verified 2026-09-26, qt6ct 0.11, Qt 6)

Quickshell's `SystemPalette` reports the palette Qt took from its platform theme.
Dracula preset:

| Setup | Palette Qt reports |
| --- | --- |
| `qt6ct`, path set, `custom_palette` absent or `false` | default light: window `#efefef`, base `#ffffff` |
| `qt6ct`, path set, `custom_palette=true` | window `#282a36`, base `#393a45`, text `#f8f8f2`, highlight `#bd93f9` |
| no platform theme | default light |
| `gtk3` platform theme, dark `Lyona-dracula` | window `#282a36`, base `#282a36`, text `#f8f8f2` |

So without `qt6ct`/`qt5ct` Qt already followed the GTK theme, and with them
installed the old block (path only, only if the config existed) had no effect.

## Change

- `scripts/lyona-gtk-theme`: emits `qt/colors.conf` and `gtk-2.0/gtkrc` per palette.
- `scripts/theme-apply.sh`: `qt_ct_set()` and a rewritten Qt block (both keys,
  creates a minimal config, preserves the rest, generated scheme first, then the
  tool's `darker.conf` for dark, none for light; nothing on a runtime-only apply).
- `Makefile`: `check-install` inventory lists the two new files; new targets
  `check-app-palettes`, `check-qt-palette-xvfb`, `check-theme-apply-qt-palette`.
- `docs/src/theming.md`: documents the behaviour and how to opt out.

## Results (2026-09-26, CachyOS, working tree, nothing committed)

- `check-app-palettes`: 3 tests OK. Worst case over the 15 shipped presets: text on
  base 5.94:1, text on window 6.66:1, highlighted text on highlight 5.01:1,
  tooltip text on base 5.94:1, placeholder on base 3.13:1. Mutations: a fixed white
  highlighted text fails (Catppuccin 2.03:1); a 45% placeholder fails (Catppuccin
  Latte 2.01:1).
- `check-qt-palette-xvfb`: PASS for a dark and a light preset, with the negative
  control. Mutation: a wrong palette index fails.
- `check-theme-apply-qt-palette` (real `theme-apply.sh`, stubbed session tools):
  qt6ct config created and pointed at the generated scheme; a light preset
  switches it and keeps `style`, `icon_theme` and `[Fonts]`; `qt5ct` the same via
  `personalization.conf`; a runtime-only apply writes nothing. Against the
  original `theme-apply.sh` it fails at the first case (no config created).
- `check-gtk-theme`, `check-theme-apply-gtk-fallback`, `check-appearance`,
  `check-install`, `check-install-preservation`, `check-shell`, `check-format`: pass.

## Not verified

- **GTK 2 rendering.** GTK 2 is not installed here and not in any Lyona package
  set; the `gtkrc` was checked for structure only. GTK 2 may not search
  `~/.local/share/themes`, where on-demand generation writes a user's theme; system
  installs (`/usr/share/themes`) are unaffected.
- **`qt5ct`.** Same three keys (confirmed in the plugin), but only `qt6ct` was run
  for the palette and only its config was checked for `qt5ct`.
- **A rendered Qt application.** The reported palette was checked, not pixels.
