# Troubleshooting

## An AppImage does not open or start

Opening an AppImage uses `lyona-appimage`. If it says the file is not an
AppImage it can read, the file is unsupported or unreadable: not a type-2 x86
AppImage (very old type-1 ones are not supported), or damaged or truncated, for
example by an interrupted download. Run it from a terminal to see why it
stopped:

```sh
lyona-appimage open ~/Downloads/Some.AppImage
lyona-appimage list
```

An AppImage that is in the launcher but does not start usually needs
`libfuse.so.2`: install `fuse2` (`sudo pacman -S fuse2`; the recommended
desktop includes it). Remove one with `lyona-appimage remove NAME`. Prefer Gear
Lever? Run `install.sh` with `--with-gearlever`, or `install-gearlever`.

## Gear Lever does not open

Gear Lever requires Flatpak's document portal. If launching it prints a
`bwrap: Can't find source path /run/user/.../doc/by-app/...` error, the portal
process has outlived its FUSE mount. Repair the current user session with:

```sh
systemctl --user restart xdg-document-portal.service
flatpak run it.mijorus.gearlever
```

The recommended and full installers include Flatpak and the GTK portal; Gear
Lever, from Flathub for the user, only with `--with-gearlever` (#260). To repair only the
application setup from an installed lyona checkout, run:

```sh
install-gearlever
```

It refuses a `flathub` remote that has signature verification disabled, is
disabled, or points at an unofficial URL, and says which. Fix or remove that
remote (`flatpak remote-modify`, `flatpak remote-delete --user flathub`) and run
it again; `dwm-flatpak-setup --user` checks the remote on its own.

Run the dependency checker first — it covers most common issues:

```bash
dwm-diagnostics
```

Or use the [Control Center](./control-center.md) → **System Health**.

---

## dwm Won't Start

**Black screen / returns immediately to login:**
- Run `dwm-diagnostics` and resolve any required X11/session failures.
- Preview required packages with `./install.sh --dry-run --profile core`.
- Check `.xinitrc` exists and ends with `exec dwm`
- Run `startx` from a TTY to see error output in the terminal

**`dwm: cannot open display`:**
- You must launch dwm from a TTY, not an existing X session
- If using a display manager, ensure `dwm.desktop` is in `/usr/share/xsessions/`

---

## No Status Bar / Quickshell Missing

- Install the recommended desktop layer: `./install.sh --profile recommended`
- Verify the managed config exists: `ls ~/.config/quickshell/shell.qml`
- Run manually: `quickshell --no-duplicate`
- Check fonts: `fc-list | grep -i meslo`

---

## Terminal Won't Open (`Super`+`X`)

- Run `alacritty` from an existing shell to inspect its error directly
- Install Alacritty with `sudo pacman -S alacritty`
- Confirm the fixed terminal in `config/hotkeys.toml`:
  ```toml
  [vars]
  terminal = "alacritty"
  ```

Herdr is an optional terminal workspace, not a graphical terminal emulator.
Install it explicitly and use `DWM_HERDR=1 dwm-terminal` to run it inside
Alacritty. The default `Super`+`X` binding remains plain Alacritty.

## Browser Won't Open (`Super`+`B`)

- Run `dwm-default-apps status` to inspect the current default browser
- Run `dwm-default-apps browsers` to list installed browser desktop files
- Set one with `dwm-default-apps set-browser firefox.desktop`
- Open Settings -> Defaults to inspect provider details, candidates, and the
  Restore Previous action
- Ensure `xdg-utils` is installed so `xdg-settings`, `xdg-mime`, and `xdg-open`
  are available

## Startup Application Change Failed

- Open Settings -> Defaults and inspect the entry origin, effective state, and
  detail. Malformed or conditional vendor entries are intentionally not
  rewritten.
- Changes apply at the next login; Settings does not start or stop the
  application in the current session.
- A stale-revision error means the entry changed after it was displayed. Use
  Refresh and retry.
- Reset to vendor removes only the managed user override. Existing vendor
  desktop files are never edited.

---

## Themes Not Applying

- Confirm `themes.toml` is at `~/.config/lyona/themes.toml`
- Check the `[active]` section has a valid theme name
- Manually trigger: `kill -USR1 $(pidof dwm)`
- Run `theme-apply.sh` directly to see any errors

---

## Keybinds Not Working

- Check `~/.config/lyona/hotkeys.toml` for mistakes. A file dwm cannot use raises a
  "dwm: bad config" notification: at login dwm falls back to the shipped defaults, and
  when you save a broken file while running it keeps the keys you already had. dwm
  names each entry it skips (an unknown key or function, a tag outside 0-8) on its
  standard error: the terminal you ran `startx` from, or your display manager's
  session log (for LightDM, `~/.xsession-errors`).
- Verify the key name is correct (use `xev` to find X11 key names).
- If neither your file nor the shipped default can be loaded, only two keys work:
  Super+x opens a terminal and Super+Shift+q quits dwm.

---

## Multi-Monitor Issues

- Tags not syncing across monitors: run `dwm-diagnostics`
- Cursor doesn't follow focus: verify cursor warp is enabled in `config.h` (`cursorwarp = 1`)
- Persistent resolution or positioning: run `dwm-display-setup detect`, then
  `dwm-display-setup`. The wizard previews changes before writing Xorg config.
- Bad persistent layout: run `dwm-display-setup rollback`, then log out and
  back in. From a TTY, remove
  `/etc/X11/xorg.conf.d/90-lyona-display.conf` if Xorg cannot start.
- TearFree is enabled only when the active Xorg driver exposes a compatible
  option or RandR property. Unsupported drivers are left unchanged.
- NVIDIA Full Composition Pipeline is enabled in generated persistence only
  when the relevant output uses the NVIDIA kernel driver and an NVIDIA Xorg
  provider is available, including supported hybrid configurations. Run
  `dwm-display-setup capabilities` to inspect the detected fallback before
  saving a layout.
- Display layout profiles: run `dwm-display-profile dir` and
  `dwm-display-profile template` to create optional `xrandr` profiles

---

## NVIDIA / Suspend Issues

- Black screen on wake: run `scripts/nvidia-suspend-test.sh` to diagnose
- DPMS/screensaver issues: use Control Center -> Power, or run
  `scripts/disable-powersaving` to disable blanking and DPMS for the current
  session

---

## A Bluetooth device's battery is not shown

Settings > Power and the Control Center list the batteries UPower reports. Most
wireless mice and keyboards on a USB receiver (for example Logitech's) report
theirs through the kernel. Some Bluetooth devices report a battery only when
BlueZ's experimental battery provider is on, which lyona does not change for
you. To turn it on, set `Experimental = true` under `[General]` in
`/etc/bluetooth/main.conf`, then `sudo systemctl restart bluetooth`. Check what
UPower sees with `upower --dump`.

## Picom / Compositor

Picom is part of the lyona desktop: the window overview's previews need it.
dwm and the panel work without it; the overview then shows icon-and-title cards.

### Picom does not start

At login, a notification says "Picom could not start" (with the path of its
log) or "Picom is not installed". It is shown once. To see why:

```bash
dwm-settings-picom status
dwm-settings-picom start
```

`start` prints the reason and the log path. Common causes: an old or broken GPU
driver, or a virtual machine without 3D acceleration. Choose **XRender** in
**Settings > Appearance > Compositor**: it needs no GPU acceleration. If it is not
installed: `sudo pacman -S picom`. Start Picom with `dwm-settings-picom start`, not
`picom` alone: lyona's default configuration leaves the backend for the helper to
choose, and Picom 13 does not start without one.

### Stopping Picom

**Control Center > Restart Picom** restarts it. To stop it while troubleshooting,
run `dwm-settings-picom stop`: window previews are off until it starts again, and
it starts again at the next login.

### Artifacts

Restart picom via the Control Center (**Quick Actions → Restart Picom**) or:
```bash
dwm-settings-picom restart
```

If artifacts persist, choose XRender or GLX in **Settings > Appearance >
Compositor**. EGL is experimental. Automatic selection uses the active renderer
and retries XRender if automatic GLX startup fails. Existing configuration choices
and `PICOM_BACKEND=glx` or `PICOM_BACKEND=egl` session overrides remain respected.

Run `dwm-settings-picom status` to see the configuration path and effective
backend. The controls remain available while Picom is stopped. Configuration
errors and concurrent edits are reported without silently replacing your choices;
activation errors identify a recovery backup and session log.

---

## Still Stuck?

- Open an issue: [github.com/technicks89/Lyona/issues](https://github.com/technicks89/Lyona/issues)
- Run the full check: `bash scripts/check-deps.sh`
