# Theming

Themes are defined in `~/.config/lyona/themes.toml`. Change the active theme and **save**
to update dwm, Quickshell, terminal, GTK, and Qt styling. No restart needed.

```toml
[active]
theme = "tokyonight"   # ← change this line to switch themes
```

The managed transaction helper is the safe command-line interface for theme
changes:

```sh
dwm-settings-theme preview preview-1 15 dracula
dwm-settings-theme keep preview-1       # confirm before the timeout
dwm-settings-theme revert preview-1     # or restore immediately
dwm-settings-theme abandon preview-1    # accept a conflicting external edit
dwm-settings-theme apply gruvbox
dwm-settings-theme reset                # restore the managed default selection
```

An unconfirmed preview restores the exact previous `themes.toml` bytes and
mode automatically. Apply and reset preserve comments, custom theme sections,
and unrelated appearance settings. If an operation is interrupted after its
atomic write, inspect and restore it with:

```sh
dwm-settings-theme recovery-status
dwm-settings-theme recover
```

Recovery refuses to overwrite an externally changed theme file.

---

## Available Themes

### Dark

| Theme | Description |
|-------|-------------|
| `nord` | Arctic, cool blue palette |
| `dracula` | Purple-tinted dark theme |
| `gruvbox` | Warm retro earth tones |
| `catppuccin` | Mocha variant — soft pastels |
| `tokyonight` | Deep blue-grey night theme (default) |
| `onedark` | Atom One Dark inspired |
| `solarized` | Dark variant of Solarized |
| `rosepine` | Muted rose/pine tones |
| `everforest` | Muted green forest palette |
| `monochrome` | Black and white minimal |

### Light

| Theme | Description |
|-------|-------------|
| `catppuccin-latte` | Catppuccin light variant |
| `gruvbox-light` | Warm light tones |
| `solarized-light` | Classic Solarized light |
| `rosepine-dawn` | Rose Pine dawn variant |
| `tokyonight-day` | Tokyo Night day variant |

---

## Border Size

```toml
[appearance]
borderpx = 1   # 0 = no border, 1 = thin (default), 2-3 = thicker
```

---

## What Each Theme Controls

Each `[theme.name]` section sets colors for all components:

| Key | Applies To |
|-----|-----------|
| `normfgcolor` / `normbgcolor` / `normbordercolor` | Unfocused bar and windows |
| `selfgcolor` / `selbgcolor` / `selbordercolor` | Focused window and active tag |
| `term_bg` / `term_fg` / `term_cursor` | Terminal background, text, cursor |
| `term_color0`–`term_color15` | Full 16-color terminal palette |
| `dark_mode` | GTK dark preference and Capitaine cursor variant (`true` / `false`) |
| `gtk_theme` | Optional installed GTK theme name for GTK apps such as Thunar |

Quickshell derives its opaque surfaces, text, borders, accent, success,
warning, and danger colors from the active theme's existing dwm and terminal
color keys.

---

## Creating a Custom Theme

Add a new section to `themes.toml`:

```toml
[theme.mytheme]
normfgcolor     = "#cdd6f4"
normbgcolor     = "#1e1e2e"
normbordercolor = "#313244"
selfgcolor      = "#cdd6f4"
selbgcolor      = "#89b4fa"
selbordercolor  = "#89b4fa"

term_bg         = "#1e1e2e"
term_fg         = "#cdd6f4"
term_cursor     = "#f5e0dc"
# ... term_color0-15 ...
dark_mode       = true
gtk_theme       = "Lyona-mytheme"
```

Then set `theme = "mytheme"` under `[active]` and save.

`gtk_theme` may name any installed GTK theme. Leaving it out is usually the
right choice: `make install` generates a `Lyona-<name>` GTK theme from every
palette in this file, and that generated theme is what a palette falls back to.
Regenerate one by hand with:

```bash
lyona-gtk-theme generate mytheme ~/.config/lyona/themes.toml ~/.themes/Lyona-mytheme
```

Applications built on libadwaita ignore custom GTK themes by design and stay in
their own light or dark palette regardless of this setting.

The same generated directory carries a GTK 2 theme (`gtk-2.0/gtkrc`) and a Qt
colour scheme (`qt/colors.conf`). With `qt6ct` or `qt5ct` installed, applying a
theme points the tool at that scheme and turns its custom palette on, creating
`~/.config/qt6ct/qt6ct.conf` (or the `qt5ct` one) if it does not exist yet, so
Qt applications follow the palette. Without either tool, Qt uses the GTK theme.
If you would rather pick your own Qt scheme, choose another platform theme under
Settings > Appearance, or set `qt` in `personalization.conf`.

---

## Applying Themes via Control Center

Open the Control Center with <kbd>Super</kbd> + <kbd>F1</kbd>, open **Appearance**, and pick a theme from the list. The theme switches immediately.

---
## Wallpapers

Place images in `~/Pictures/backgrounds/`. Open **Settings → Appearance** to
select an image, choose its fit, preview it for 30 seconds, apply it, or reset
to the random session default. Use `Super` + `Shift` + `W` or
`dwm-settings-wallpaper randomize` for a one-off random wallpaper in the
current session, or persist a specific image and fit from a terminal:

```bash
dwm-settings-wallpaper apply "$HOME/Pictures/backgrounds/mywall.jpg" fill
```

Supported fit modes are `center`, `fill`, `max`, `scale`, and `tile`. Preview a
choice for 30 seconds before keeping it:

```bash
token="wallpaper-$$"
dwm-settings-wallpaper preview "$token" 30 \
  "$HOME/Pictures/backgrounds/mywall.jpg" max
dwm-settings-wallpaper keep "$token"
```

Use `dwm-settings-wallpaper reset` to return to the session's random-fill
default. If a saved image is removed, login remains usable and falls back to
that default until another image is selected or the setting is reset.

---
## Fonts and Text Size

Open **Settings -> Appearance** to select an installed Fontconfig family and a
managed shell text scale from 80, 90, 100, 110, 125, or 150 percent. The icon
font remains the shipped Meslo Nerd Font even when ordinary interface text uses
another family, so changing fonts cannot remove panel or menu glyphs.

Preview changes for 30 seconds before keeping them, or apply and reset from a
terminal:

```bash
token="font-$$"
dwm-settings-font preview "$token" 30 "Noto Sans" 1.25
dwm-settings-font keep "$token"

dwm-settings-font apply "Noto Sans" 1.10
dwm-settings-font reset
```

The setting owns only `font.conf` under the lyona XDG configuration
directory. A malformed file falls back to the existing Meslo family at 100
percent without preventing shell startup. GTK and Qt application font policy
is intentionally deferred to the separate toolkit-control slice.

---
## Boot Menu

The GRUB boot menu uses the `CyberRe` theme, selected by the installer on
machines that boot with GRUB. It is not part of the palette system above --
GRUB reads its own theme long before the session starts, so it does not follow
the dark/light theme you pick in Settings.

```bash
lyona-grub-theme status    # detected bootloader and selected theme
lyona-grub-theme list      # installed themes
lyona-grub-theme apply     # select CyberRe (or apply <name>)
lyona-grub-theme remove    # back to the default GRUB appearance and entries
```

Applying or removing a theme edits `/etc/default/grub` and regenerates
`/boot/grub/grub.cfg`, so it needs root and backs the file up first. Applying
also hides the `(EFI BootNext)` firmware entries GRUB 2.16 adds, through a
drop-in file that removing deletes. See
[Install](install.md#grub-boot-menu-theme) for exactly which keys it changes.

Machines that boot with systemd-boot have no GRUB menu to theme, and the
commands above report that and do nothing. Installs made from the lyona image
boot with GRUB, with this theme.

## Picom opacity and backend

Open **Settings > Appearance > Compositor** to change foreground (active) and
background (inactive) window opacity. Sliders save when released; keyboard edits
save after a short pause. Values stay the same when switching themes. Custom
Picom rules can override these defaults for individual windows.

The same section has a **Window corner radius** slider, from 0 to 32 pixels, that
rounds the corners of every window (dwm draws square borders, so rounding comes from
Picom's `corner-radius` option). At 0 the setting is removed from the configuration.
Picom leaves fullscreen windows square by default, and a per-window `corner-radius` in
a Picom rule overrides the slider. Picom's manual says rounded corners do not combine
well with `transparent-clipping`, so leave that off if you use them. It needs a running
compositor to show; with Picom stopped the value applies the next time it starts.

The controls read the active Picom configuration: your own `~/.config/picom.conf`
or `~/.config/picom/picom.conf` when you have one, otherwise lyona's default
(`/usr/share/lyona/xdg/picom/picom.conf` in a standard install). lyona's default
is lean so that old hardware can run it: no shadows, fading, blur or animations,
and every window opaque. It is read-only; **Create user configuration** copies it
to `~/.config/picom.conf`, after which your copy is used and lyona's updates never
touch it. The controls observe external edits. Comments, unrelated settings,
and included files are preserved; the ten most recent edits retain recovery
backups. Invalid or read-only configurations show an explanation rather than
disappearing controls. Edits made while Picom is stopped take effect the next time
it starts. Valid configurations using syntax the editor cannot rewrite, such as
nested includes, still support startup, restart, and reload through Picom itself.

**Automatic** chooses GLX for an accelerated Intel/AMD renderer and XRender for
NVIDIA, software rendering, or unknown hardware. Failed automatic GLX startup
retries XRender once. An existing explicit backend is preserved; choose Automatic
to remove it. XRender, GLX, and experimental EGL remain selectable. The active
renderer matters, not an unused or passthrough GPU installed in the machine.

`PICOM_BACKEND` remains a session override. Unset it before selecting a different
backend in Settings. `DWM_PICOM_CONFIG=/absolute/path/picom.conf` can select a
custom configuration; an existing Picom `--config` argument is also respected.
Command-line opacity and `--corner-radius` overrides must be removed before editing them in
Settings.

```bash
dwm-settings-picom status
dwm-settings-picom restart
```

Restart and toggle affect only your compositor on the current display. Failed
configuration activation restores the prior files and attempts to recover the
previous compositor; the error identifies the backup and session log.
