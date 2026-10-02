# Control Center

The Control Center is a single-card anchored Quickshell menu for launching
applications, panel settings, system health, quick actions, appearance
settings, power management, and keybind discovery.

**Open:** <kbd>Super</kbd> + <kbd>F1</kbd>, or run `dwm-controlcenter` from a
terminal.

The popup opens from the panel logo. Applications, Power, Settings, System
Health, Keybinds, and System Info are available directly from the main menu.
Bar Widgets, Quick Actions, Appearance, and Power Settings replace the menu
contents in the same card and provide a Back control. Press <kbd>Esc</kbd> or
click outside the card to close it from any page.

The main menu also has a **Window layout** row of three buttons, Tile, Floating and
Monocle, for people who do not know the layout keybindings. The button for the current
layout is highlighted and follows the keyboard, so pressing <kbd>Super</kbd> + <kbd>T</kbd>
or <kbd>Super</kbd> + <kbd>F</kbd> moves the highlight. Layouts are per tag, and the row
acts on the tag and monitor that currently have focus. The buttons are disabled when dwm
does not report its layout (an older dwm build).

The Utilities section opens the unified Settings application directly. Phase
1 Settings is a read-only capability overview with section search and
keyboard/mouse navigation. It can also be opened with `dwm-settings open`.

The Utilities section also shows the installed lyona version, and — only when
a newer release is available on the configured channel — an **Update
available** row naming it. Both open Settings -> System. There is no update
action in Control Center itself: applying an update is a multi-minute
privileged operation that restarts Quickshell, and does not belong behind a
one-click row next to the volume slider. See [Settings](./settings.md) and
[Updating and Rollback](./updating.md).

---

## Network Popover

The panel network indicator opens a Quickshell network popover. It shows active
NetworkManager connections, scans visible Wi-Fi networks, and connects to open
or WPA personal networks directly. Successful Wi-Fi connections are saved as
NetworkManager profiles, so they reconnect normally in later sessions.

Hidden SSIDs and enterprise Wi-Fi are handled through the optional
`nm-connection-editor` fallback when it is installed.

## Bluetooth Popover

The panel Bluetooth indicator opens a compact device manager. It can power the
adapter on or off, scan for devices, pair and trust a new device, connect a
paired device, and disconnect a connected device through `bluetoothctl`.

## Panel Widgets

The Bar Widgets page can show or hide the workspace, volume, Bluetooth,
network, power, calendar and weather widgets. Those choices are stored in the
project-owned `~/.config/lyona/panel-widgets.conf` state and apply to every
monitor and future Quickshell session. Settings Appearance exposes the same
shared controls and can restore the defaults: everything on except the weather.

### Calendar

Click the panel clock to open a month calendar.

- **Keys:** the arrows move a day or a week, Page Up and Page Down a month, and
  Home returns to today.
- **Closing:** Escape or a click outside closes it.
- **Off:** with the Calendar switch off, the clock does nothing when clicked.
- **IPC:** `quickshell ipc --path ~/.config/quickshell/shell.qml call calendar
  toggle` opens it from a hotkey too.

### Weather

The weather is off until you turn its Bar Widgets switch on and set a location
in Settings, Appearance, Weather.

- **What is sent:** the shell then asks Open-Meteo for the current temperature,
  at most every 30 minutes, and only while the widget is on. No account or key
  is needed. The location you typed is sent to Open-Meteo and nothing else is;
  your position is never guessed from your IP address.
- **Units:** they follow your locale (Fahrenheit in the US and a few other
  regions) unless you choose Celsius or Fahrenheit there.
- **When it fails:** the panel shows "Unavailable" and tries again later.
- **The helper:** the panel uses `lyona-weather`, which keeps its settings in
  `~/.config/lyona/weather.conf` and its cache in `~/.cache/lyona/weather/`,
  both private to you.

The redesigned panel retains the
active-window title, status segments, and system tray, and shows all nine dwm
tags (workspaces). Hovering icon-only panel controls displays a text tooltip.

The panel, popovers, and control-center cards use fully opaque colors. Their
palette follows the active theme in `themes.toml` and updates when that file is
changed.

---

## Modules

### System Health

System Health opens as a separate full-screen dashboard on the current
monitor. It starts two read-only scans: session checks run immediately, and a
privileged scan completes current-boot journal, kernel, system-service, and
drive checks. If cached or `NOPASSWD` sudo access is available, the scan runs
without a prompt. Otherwise the running polkit agent requests graphical
authorization for the root-owned `${PREFIX}/libexec/lyona/dwm-system-health-root`,
under its own action (`com.lyona.system-health.manage`, "Authentication is
required to read system logs and repair system services"). That helper accepts
only the privileged scan and the listed service repairs. Cancelling the prompt
leaves a partial report and marks its coverage as incomplete.

The dashboard groups checks into:

- Boot and kernel errors from `journalctl`, with `dmesg` as a fallback
- Failed user and system services, one service per row
- Memory, pressure, load, swap, filesystem space, and inode use
- Local routing, resolver, and NetworkManager state
- X11, D-Bus, dwm, Quickshell, Picom, audio, and managed configuration
- Required commands, libraries, terminals, and package-database consistency
- Available battery, thermal, and SMART drive-health data

Use **Issues Only** to hide passing checks. Expand any card to see bounded
evidence; the dashboard counts the complete matching log set even when only a
sample is displayed. It does not contact an external service to test Internet
connectivity and does not scan previous boots.

Boot-journal and kernel-error cards with matching entries include **Copy** and
**Export**. Copy sends the card's readable bounded evidence to the X11
clipboard with `xclip`. Export saves the same content in the user's home
directory as a private timestamped file, such as
`boot2026-07-09-143000.txt` or `kernel-errors2026-07-09-143000.txt`. Existing
files are never overwritten.

Repair buttons always require confirmation. Each failed service row offers
Start, Stop, Restart, Disable, and Enable. User units are managed with
`systemctl --user`; system units request administrator authorization through
polkit. An action is accepted only while that exact service remains failed.
The dashboard can also restart known desktop/audio components, launch the
interactive dependency installer, restart NetworkManager or Bluetooth, and
repair the detected time-synchronization provider.

Installing the health helper in a root-owned system path remains recommended:

```bash
make
sudo make install-system
```

A checkout's copy of a helper is never elevated. If
the installed helper is unavailable, cached or `NOPASSWD` sudo can still run
the validated root-owned system commands. Polkit authorization requires the
root-owned installed helper.

### Quick Actions

| Action | Description |
|--------|-------------|
| Restart Picom | Restart the compositor through `dwm-settings-picom`, which picks the backend for this GPU |
| Restart Quickshell | Reload the managed Quickshell shell |
| Reload Wallpaper | Randomize from `~/Pictures/backgrounds/` |
| Restart NetworkManager | `sudo systemctl restart NetworkManager` |
| Run Dependency Check | Opens `check-deps.sh` in a terminal |
| Install Missing Deps | Runs `install.sh` in a terminal |
| Wallpaper Folder | Open `~/Pictures/backgrounds/` in the file manager |
| GTK Settings | Launch `nwg-look` for GTK theming |

### Appearance

| Action | Description |
|--------|-------------|
| Select Theme | Pick from all themes defined in `themes.toml` |
| Randomize Wallpaper | Random image from `~/Pictures/backgrounds/` |
| Open Wallpaper Folder | Open folder in file manager |
| GTK Theme Settings | Launch `nwg-look` for GTK theming |

### Power Settings

The Power Settings card retains the existing persisted screen-DPMS and
auto-lock controls. Each feature can be enabled or disabled and assigned a
5-minute, 10-minute, 15-minute, 30-minute, or 1-hour timeout.

Both are **on by default**. After 10 minutes idle the screen turns off, and the
desktop locks 5 seconds later; moving the mouse in those 5 seconds cancels without
a password. Turning either off, or picking another timeout, is saved in
`~/.config/lyona/power.conf` and wins over the default. A choice you saved before
this default changed is kept. The lock uses light-locker, which locks through
LightDM (Lyona's display manager). In a `startx` session the screen still turns off,
but the automatic lock needs LightDM.

The full Settings Power page also shows battery, external-power, profile,
suspend, and lid capabilities. Its Lock, Log Out, Suspend, Reboot, and Shutdown
buttons use the same shared root QML action model and confirmation policy as
the panel Power menu. Denied or failed actions remain attributed to the
surface that requested them.

### Defaults and Startup Applications

Settings -> Defaults manages browser, terminal, file-manager, and selected MIME
handlers through versioned XDG records. Restore Previous is offered only while
the recovery image still matches the state written by the last action.

File-type choices include installed handlers such as sxiv and Feh even when
their desktop entries use `NoDisplay=true` to stay out of launcher menus.
Disabled entries and handlers whose executables are missing remain excluded, and
the browser, file-manager and terminal roles still hide menu-hidden entries.

The same page lists effective XDG autostart entries and their vendor or user
origin. Enable, disable, and reset create or update user overrides for the next
login; vendor desktop files are never edited. Changes to the locker,
compositor, or polkit agent require explicit confirmation.

### Keybind Viewer

Displays all bindings from `hotkeys.toml` in a searchable Quickshell list. Same
as pressing <kbd>Super</kbd> + <kbd>/</kbd>.

---

## Running from Terminal

```bash
dwm-controlcenter
```

The script is a compatibility wrapper around the Quickshell IPC target:

```bash
quickshell ipc --path "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml" call controlcenter toggle
```

Open or refresh System Health directly through its IPC target:

```bash
quickshell ipc --path "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml" call systemhealth open
quickshell ipc --path "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml" call systemhealth refresh
```

The diagnostic helper can also produce its structured snapshot in a terminal:

```bash
dwm-system-health scan-user
```
