# Design: GTK and GSettings in lyona

Written 2026-10-12, while fixing #368. A survey only: nothing in this document
has been built. It records where lyona uses GSettings and GTK, what could be
replaced, and a recommendation, for a later decision.

GSettings was not the cause of #368. The desktop flashed because the tests
inherited the live session's display, D-Bus and GSettings. The #368 fix
isolates every test run, whatever the tests call. This document is about
whether lyona needs GSettings and GTK at all.

## GSettings: what lyona reads and writes itself

| Where | What it does | Replaceable? |
|---|---|---|
| `scripts/theme-apply.sh` (~590-594) | Writes `org.gnome.desktop.interface` `color-scheme`, `gtk-theme`, `cursor-theme`, `cursor-size` | Partly; see below. |
| `scripts/dwm-settings-power` (~320-330, 405, 513), `scripts/dwm-settings-provider` (~598) | Reads and writes light-locker's `apps.light-locker` `lock-after-screensaver` and `lock-on-suspend` | Yes, easily. |
| `scripts/dwm-settings-appearance` (`gsettings_value`, ~710) | Reads `org.gnome.desktop.interface` keys for the Appearance inventory | Yes. |
| `config/quickshell/appearance/AppearanceModel.qml` (~118) | Watches `$XDG_CONFIG_HOME/dconf/user` for changes made outside lyona | Yes, once the items above are gone. |
| `scripts/dwm-packages.sh` (`arch:theme`) | Installs `dconf`, the GSettings backend | Only while a key is still written; GTK apps want it anyway. |

### The theme keys

- **`color-scheme`** is the standard dark-mode channel. `xdg-desktop-portal-gtk`'s Settings portal reads it and exposes it to Firefox, Electron and Chromium apps, libadwaita/GTK4 apps and Flatpak apps. There is no non-GSettings source for that portal short of lyona implementing the portal itself. **Keep it.**
- **`gtk-theme`, `cursor-theme`, `cursor-size`** mostly repeat what lyona already gives GTK3 apps on X11 through XSETTINGS (`xsettingsd`, `$XDG_CONFIG_HOME/lyona/xsettingsd.conf`) and the GTK `settings.ini` files. GTK4/libadwaita ignores `gtk-theme`. Candidates for removal, after checking Steam, Firefox, Thunar and a Flatpak app still pick up the theme and cursor without them.

### light-locker

light-locker takes its settings on the command line as well as from GSettings:

```
--lock-after-screensaver=S   --lock-on-suspend / --no-lock-on-suspend
--late-locking / --no-late-locking   --lock-on-lid / --no-lock-on-lid
```

lyona could keep the lock settings in its own TOML (as it does for other
power settings) and start light-locker with these options from the session
autostart, restarting it when Settings > Power changes them. That removes
GSettings from `dwm-settings-power` and `dwm-settings-provider`.

### The Appearance inventory

`dwm-settings-appearance` reads the GTK theme and cursor back from GSettings to
show the current state. lyona already holds that state in
`$XDG_CONFIG_HOME/lyona/themes.toml` and `xsettingsd.conf`; reading those makes
the inventory reflect what lyona applied, not what something else last wrote.

**Result:** GSettings use shrinks from four places to one key (`color-scheme`).

## GTK applications lyona installs

From `scripts/dwm-packages.sh`:

| Group | GTK applications | Possible replacement | Assessment |
|---|---|---|---|
| `arch:desktop` | `mate-polkit` (polkit authentication agent) | A Quickshell agent with `Quickshell.Services.Polkit` (installed with Quickshell 0.3) | **Good candidate:** a themed, integrated password prompt, one less process and package. |
| `arch:desktop` | `blueman` (applet, pairing dialogs) | lyona's own Bluetooth window (`config/quickshell/controls/BluetoothWindow.qml`), extended to cover pairing and confirmation | Possible once pairing is covered; check passkey and confirmation flows first. |
| `arch:desktop` | `pavucontrol` (GTK4) | lyona's own audio controls; `pavucontrol-qt` for the advanced view | Low value: it is the advanced fallback. |
| `arch:desktop` | `light-locker` (locks through LightDM's greeter) | A Quickshell lock screen with `Quickshell.Services.Pam` | **Not recommended:** on X11 a client-side lock screen is weaker than light-locker's switch to the greeter's VT. |
| `arch:desktop` | `xdg-desktop-portal-gtk` | `xdg-desktop-portal-kde` or `-gnome` | Keep: needed for file pickers and the Settings portal; the alternatives pull in a larger desktop. |
| `arch:file-manager` | Thunar, `thunar-archive-plugin`, `file-roller`, `tumbler`, `gvfs` | pcmanfm-qt, Ark | Keep: Thunar is light and works well. |
| `arch:lightdm` | `lightdm-slick-greeter` | Other LightDM greeters | Keep: GTK is the usual choice for LightDM greeters. |
| `arch:media` | Celluloid (GTK4/libadwaita) | mpv alone (already installed) | Optional: Celluloid is only mpv's front end. |
| `arch:keyring` | `gnome-keyring` (prompts through GTK/gcr) | KeePassXC's Secret Service | Keep unless the keyring itself is reconsidered. |

### What stays GTK regardless

Steam, Firefox, GIMP, darktable and most applications users install
themselves are GTK. lyona's GTK theming (the `Lyona-*` GTK themes from
`scripts/lyona-gtk-theme`, `xsettingsd`, the GTK `settings.ini` files) has
to stay, or those applications lose the lyona look. Replacing lyona's own GTK
choices reduces the number of GTK processes, not the need for GTK theming.

## Recommendation

1. **Do (low risk):**
   - drop lyona's own GSettings use except `color-scheme`: light-locker through its command-line options, the Appearance inventory from lyona's files, no dconf watcher;
   - then test whether `gtk-theme` and the cursor keys can go as well.
2. **Consider:** replace `mate-polkit` with a Quickshell polkit agent.
3. **Don't:** replace GTK applications wholesale, or replace light-locker with a client-side lock on X11.

## If this goes ahead

Each item is a separate issue and branch:
- **light-locker options:** settings, autostart, migration of an existing `apps.light-locker` value, tests.
- **Appearance inventory from lyona's files.**
- **Polkit agent in Quickshell:** the security review that the AGENTS.md Desktop Settings Rules require, with the agent unprivileged and authorization still by polkit.
