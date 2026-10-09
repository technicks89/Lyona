# Configuration

lyona keeps user configuration under
`${XDG_CONFIG_HOME:-$HOME/.config}/lyona/`. **Customise lyona with these files.**
They are read at runtime, **live-reload on save**, belong to you alone, and survive
every update and rollback unchanged. No recompile is needed.

| File | Purpose |
|------|---------|
| `hotkeys.toml` | All keybindings, including the tag keys |
| `themes.toml` | Colors, themes, border size |
| `window-rules.toml` | Per-app window rules: tag, floating, terminal swallowing, always on top, monitor |
| `power.conf` | Control Center screen blanking and auto-lock choices |

If one of these files cannot be used (a typo, an empty file, nothing dwm can bind),
dwm tells you with a "dwm: bad config" notification. At login it falls back to the
shipped default for that file; when you save a broken file while dwm is running, it
keeps the configuration it already had until the file is fixed.

The shipped defaults are read-only, in `/usr/share/lyona/config/` (under your
`PREFIX` for another install location). They are replaced on every update, so
change your own copy in `~/.config/lyona/`, never these.

## Window rules

`window-rules.toml` holds one rule per line, and every matching rule applies, in
order. Find a window's class, instance and title with
`xprop | grep -E "WM_CLASS|WM_NAME"`.

```toml
rules = [
  { class="Gimp",    isfloating=1 },
  { class="firefox", tags=2 },
  { class="kitty",   isterminal=1 },
]
```

Fields: `class`, `instance`, `title` (omit to match anything), `tags` (1-9; 0 or
omitted follows the current tag), `isfloating`, `isterminal`, `alwaysontop`,
`noswallow` (`1`/`true` or `0`/`false`), and `monitor` (-1 for any). A rule needs at
least one of `class`, `instance` or `title`; one with none would match every window,
so dwm skips it and says so in its log.

---

## config.h (compile-time options)

A few options are compiled into dwm and have no TOML equivalent yet: the bar font,
the tag names, the layouts, the default master size and count, the refresh rate, the
window icon size, the floating-toggle shrink and whether the bar is shown. These live
in `config.h`, your copy of `config.def.h` in the checkout, which `make` creates if it
does not exist.

```bash
$EDITOR config.h
./scripts/dev-sync-install.sh
```

`dev-sync-install.sh` rebuilds dwm, updates the installed commands, shared code,
shipped defaults and managed Quickshell configuration when needed, verifies parity,
and reports whether the dwm session must be restarted. When a session restart is already required, it activates
Quickshell there so the tray host starts before tray clients. Use
`./scripts/dev-sync-install.sh --check` for a non-mutating audit.

**How updates treat `config.h`.** `lyona-update` (and the Settings update pane)
builds each release with your own
`${XDG_CONFIG_HOME:-$HOME/.config}/lyona/config.h`, and falls back to a checkout's
`config.h` when you run `./scripts/lyona-update` from one. With neither, a release
builds from its `config.def.h`. `make install-user` (run by `install.sh`) copies a
customised checkout `config.h` there once, and never overwrites one that is already
there; it does not copy an unchanged default, which would only go stale.

When a release adds a compile-time option, merge it into your copy from the
release's `config.def.h`; if the build fails, `lyona-update` names the `config.h` it
used and leaves the live install untouched. dwm is installed once for the whole
machine, so the person who runs the update decides these options for everyone. Keep
personal choices in the TOML files above, which are per user and always survive an
update.

| Setting | Description |
|---------|-------------|
| `fonts[]` | Font family and size used in the bar |
| `tags[]` | Tag names |
| `layouts[]` | Available layouts (switch with the keys, or the Control Center's layout row) |
| `mfact`, `nmaster` | Default master area size and count |
| `refresh_rate` | Match your monitor (default 60; set 120 for high-refresh) |
| `FLOATSHRINKPCT` | How far a window shrinks when toggled to floating (default 85%) |
| `ICONSIZE`, `SHOWWINICON` | Window icon size, and whether it is shown |
| `MODKEY` | The modifier the tag keys in `hotkeys.toml` use: `Mod4Mask` = Super, `Mod1Mask` = Alt |

---

## hotkeys.toml — Live Keybinds

Add or change bindings without recompiling. Save the file and they apply instantly.

```toml
[vars]
terminal = "alacritty"
webapp   = "webapp-launch"

keys = [
  { mod="SUPER",       key="x",  desc="Terminal",    func="spawn", exec=["$terminal"] },
  { mod="SUPER SHIFT", key="f",  desc="Firefox",     func="spawn", exec=["firefox"] },
]
```

The default binding launches Alacritty directly. The `dwm-terminal` helper is
available to delegated tools that need a terminal selection fallback; it also
prefers Alacritty and opens the emulator directly by default. Explicit
arguments such as `dwm-terminal -e command` retain their direct execution
contract.

Thunar's seeded **Open Terminal Here** action launches Alacritty directly in
the selected directory, matching the normal `Super` + `X` default. Existing
Thunar custom actions are preserved during installation and upgrades.

Set `DWM_TERMINAL` to choose another emulator for `dwm-terminal`. Herdr is an
optional layer: install it explicitly, set `DWM_HERDR=1`, and run
`dwm-terminal`. Set `DWM_HERDR_COMMAND` to select a different Herdr binary.

Default applications use freedesktop settings. Run `dwm-default-apps browsers`
to list browser desktop files, `dwm-default-apps set-browser firefox.desktop`
to set the default browser, or `dwm-default-apps set-mime <mime> <desktop-id>`
for other file types.

Display profiles are optional files under
`${XDG_CONFIG_HOME:-$HOME/.config}/lyona/display-profiles`. Use
`dwm-display-profile template` to print the format, `dwm-display-profile list`
to show profiles, and `dwm-display-profile apply <name>` to run the profile
through `xrandr`.

For persistent Xorg configuration, run `dwm-display-setup`. The interactive
wizard detects connected outputs and their exact advertised timings, then asks
for resolution, refresh rate, rotation, absolute position, and the primary
display. It checks whether the active Xorg driver exposes compatible TearFree
support or the NVIDIA Full Composition Pipeline and enables only the compatible
default. The proposed layout is applied as a live preview and automatically
restored unless it is confirmed. Advanced calls may pass
`--force-full-composition-pipeline off` to disable the NVIDIA default; forcing
it on with an incompatible kernel or Xorg driver is rejected.

Accepted layouts are installed as the isolated managed fragment
`/etc/X11/xorg.conf.d/90-lyona-display.conf`; existing Xorg files are not
replaced. Each change creates a versioned backup. Use
`dwm-display-setup rollback` to restore the newest backup, or
`dwm-display-setup status` to inspect the managed file and current layout.
Advanced users can pass an existing display-profile file to
`dwm-display-setup generate`, `preview`, or `install`.
For noninteractive session changes, `dwm-display-setup capture` prints the
current complete RandR profile, `dwm-display-setup validate <profile>` checks a
profile with `xrandr --dryrun`, and `dwm-display-setup apply <profile>` changes
the current X11 layout after validation.

The Settings Displays page uses the same profile grammar and validation through
`dwm-settings-display`. Named profiles remain user-owned under the XDG path.
Installing one persistently requires explicit confirmation and authorization;
only the root-owned helper under `${PREFIX}/libexec/lyona/` may update the
managed Xorg fragment. Legacy profiles that omit complete position or rotation
state remain usable with `dwm-display-profile`, but Settings will not preview or
install them until they are resaved as a complete layout.

Per-device input values kept in Settings are stored in
`${XDG_CONFIG_HOME:-$HOME/.config}/lyona/input-settings.conf`. The
event-driven input provider uses a hardware serial or path when available,
re-resolves that identity before every change, and skips a disconnected device
rather than applying its settings to another XInput ID. Session startup runs
`dwm-settings-input apply-saved` and starts an event-driven, debounced hotplug
replay so returning devices regain saved values. Repeating the apply is safe.
The replay watcher is scoped to the owning dwm process and exits at logout,
including when dwm was launched through `startx`.

Power settings are managed from Control Center -> Power. Out of the box
the screen turns off after 10 minutes idle and the desktop
locks: lyona sets light-locker to lock 5 seconds after the screen blanks and on
suspend, and starts it. Changing anything there writes `power.conf`, which is
then authoritative and persists screen DPMS state, display-off timing, and
automatic idle and suspend locking. Startup reapplies it (or the defaults)
before background session services are launched. Manual locking remains
available when automatic locking is disabled. The screen locker runs only
while automatic locking is enabled or for the duration of an explicit manual
lock, so DPMS display-off events remain independent from locking. External
`loginctl lock-session` requests are forwarded to `dwm-lock` by an
event-driven session listener. Until `power.conf` exists, lyona never stops or
disables a locker it did not start.

### Modifier Syntax

Use space-separated modifiers: `"SUPER"`, `"SUPER SHIFT"`, `"SUPER CTRL"`, `"SUPER CTRL SHIFT"`.

### Available Functions

| `func` | Parameters | Description |
|--------|-----------|-------------|
| `spawn` | `exec=[...]` or `cmd="..."` | Run a program |
| `killclient` | — | Close focused window |
| `zoom` | — | Promote/demote master |
| `focusstack` | `i=1` or `i=-1` | Focus next/prev window |
| `movestack` | `i=1` or `i=-1` | Reorder in stack |
| `incnmaster` | `i=1` or `i=-1` | Change master count |
| `setmfact` | `f=0.05` or `f=-0.05` | Resize master area |
| `setcfact` | `f=0.25` / `f=-0.25` / `f=0.00` | Resize window slot |
| `setlayout` | `layout_idx=0/1/2` | 0=tile, 1=float, 2=monocle |
| `togglefloating` | — | Float/tile window |
| `fullscreen` | — | True fullscreen |
| `togglefakefullscreen` | — | Fullscreen with bar |
| `togglebar` | — | Show/hide bar |
| `focusmon` | `i=1` or `i=-1` | Focus monitor |
| `tagmon` | `i=1` or `i=-1` | Send window to monitor |
| `view` | `ui=-1` = all tags | Switch tag |
| `quit` | — | Exit dwm |

### Tag Bindings

Tag bindings auto-generate all four variants (switch, toggle-view, move, toggle-tag):

```toml
tag_keys = [
  { key="1", tag=0 },
  { key="2", tag=1 },
]
```

---

## Notes on XDG Autostart

Recommend using Flatpak to install programs on startup:

```sh
flatpak install flathub io.github.flattool.Ignition
```

or you can create your own .desktop file in ~/.config/autostart/

`set-refresh.desktop` Example:

```ini
[Desktop Entry]
Type=Application
Exec=xrandr --output HDMI-0 --primary --mode 1920x1080 --pos 0x0 --rotate normal --rate 120 --output DP-0 --off --output DP-1 --off --output DP-2 --off --output DP-3 --off --output DP-4 --off --output DP-5 --off
Hidden=false
X-GNOME-Autostart-enabled=true
Name=Set Refresh
```
