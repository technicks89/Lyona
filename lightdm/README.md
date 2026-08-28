# LightDM Slick Greeter - lyona

A modern Arch Linux LightDM login screen using Slick Greeter with the Tokyo
Night colour palette, a blurred background, and the MesloLGS NF font.

The lyona installer uses `slick-greeter`. The lyona LightDM install
target renders the matching `lightdm.conf`.

## Files

| File | Destination |
|------|-------------|
| `lightdm.conf` | `/etc/lightdm/lightdm.conf` |
| `slick-greeter.conf` | `/etc/lightdm/slick-greeter.conf` |
| `wallpaper.jpg` | `/usr/share/pixmaps/lyona.jpg` |
| `../assets/logo/lyona-icon.png` | `/usr/share/pixmaps/lyona-logo.png` |
| `gtk-theme/Lyona-TokyoNight/` | `/usr/share/themes/Lyona-TokyoNight/` |

## Install

The main `install.sh` handles this automatically. To apply manually:

```sh
sudo make install
```

The direct `make install` defaults match Arch Linux. Prefer the top-level
`install.sh` for a complete installation.

## Customisation

Edit `slick-greeter.conf` before running `sudo make install`:

- **background** — path to a wallpaper image
- **font-name** — any font already installed on the system
- **clock-format** — strftime-style format string
- **theme-name** — GTK theme for the panel (default `Lyona-TokyoNight`)
- **show-clock** / **show-hostname** — toggle status bar items
- **activate-numlock** — enable only when `numlockx` is installed

## The greeter theme

`gtk-theme/Lyona-TokyoNight/` is a small GTK 3 theme that imports Adwaita dark
for its metrics and assets, then repaints the surfaces in the Tokyo Night
palette. slick-greeter draws no colours of its own — its only built-in CSS
sets padding and makes the login box transparent — so the GTK theme named by
`theme-name` is what decides how the greeter looks. Keep the palette in sync
with `[theme.tokyonight]` in `config/themes.toml`.
