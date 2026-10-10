# #280: dwm's runtime config in config.c, tested in a VM

Issue `#280`, branch `dwm-config-c`: the source tests search the files dwm is
built from instead of `dwm.c` by name (step 1), then the runtime TOML loading,
inotify watch and reload move from `dwm.c` into `config.c` behind `rtconfig.h`.
EWMH stays in `dwm.c` for now.

## Build

- `make clean all`: no warnings (gcc, `-std=c99 -pedantic -Wall`). clang with
  `-Wextra` also reports nothing for `config.c`, `util.c` and `rtconfig.h`.
- `config.o` exports only the six `runtime_config_*` functions and the six
  `rt_*` tables: `runtime_config_setup`, `_load`, `_fd`, `_poll`,
  `_mark_reload_pending`, `_take_pending`.
- No new dependency. `dwm.c` is 5357 lines (from 6243), `config.c` 886.
- The same tarball built the same `dwm` twice in the VM (through
  `lyona-update` and through `install.sh`): SHA-256 `2d609f53...`.

## Full suite (2026-10-09)

Each of the 146 steps of `make check` was run on its own through
`scripts/run-tests`, with its exit status recorded. Eight failed. Seven of them
also fail on a clean `main` worktree (`ddd33dc`), in `stage_helpers`
(`tests/lib.sh`, from `812eb82`), which takes `$lyona_lib/..` and
`$lyona_lib/dwm-xwatch` for libraries to stage:

- check-quickshell-controlcenter, check-quickshell-settings-xvfb,
  check-quickshell-large-surfaces-xvfb, check-quickshell-health-xvfb,
  check-phase5-optional-components, check-quickshell-state,
  check-installed-helper-paths.

The eighth, check-install-preservation, passed on `main` and failed here: its
fixture made `drw.o dwm.o util.o tomlparser.o` by name, so `install-system`
stopped at the missing `config.o`. It now makes one object per `SRC` entry,
and passes.

## The VM

| | |
| --- | --- |
| Image | `lyona-2026.10.0-beta.5-x86_64.iso` from `out/` (built 2026-10-07, installs `fb7e28c`), SHA-256 `83cedd08...` |
| VM | QEMU 11.1.2, KVM, q35, 4 GB, 4 CPUs, OVMF (UEFI, no Secure Boot), `-vga std` 1280x800, virtio disk 32 GB, user networking |
| Install | The image wizard (us, btrfs, no encryption), driven with QEMU monitor `sendkey` |
| Branch build | `make release` of this working tree, installed with `lyona-update apply --file` and with `install.sh --non-interactive --profile full --skip-topgrade` from an extracted checkout |

The checks ran over SSH against the logged-in LightDM session (`:0`), with a
small X client that maps a window of a chosen `WM_CLASS`. The same 82 checks
ran on the image's beta.5 `dwm` first, then on this branch's: all 82 passed on
both, with the same results.

- **Session:** dwm, Quickshell and Picom run; the shipped defaults are found
  under `/usr/local/share/lyona/config`; 90 keys, 6 buttons, the theme and 16
  rules load; dwm holds its inotify descriptor; no config errors in the log.
- **EWMH:** `_NET_SUPPORTED` names the atoms in use; 9 desktops and names; the
  WM check window; `_DWM_MONITOR_DESKTOPS` and `_DWM_SELECTED_MONITOR`.
- **Tags:** view, previous tag, send (the view follows the window, as `tag()`
  does), toggletag on and off, toggleview, view all.
- **Windows:** manage, focus, tiling, focusstack, zoom, mfact, nmaster,
  movestack, float (shrinks to `FLOATSHRINKPCT`) and back, full screen and
  back, a client's own `_NET_WM_STATE` full-screen request, fake full screen,
  float and tile layouts, togglebar, Super+drag move, Super+right-drag resize,
  killclient.
- **hotkeys.toml:** an edit adds Super+F12, which works; a half-written file is
  reported ("invalid config - kept the previous config") and the keys in use
  survive it; an atomic replace (`mv`) reloads; the removed key stops working.
- **window-rules.toml:** a new rule sends a window to tag 5, floating at its own
  size; a rule that matches nothing is logged and skipped, and an ordinary
  window is not caught by it; the original rules come back.
- **themes.toml:** `borderpx` follows an edit, for open and new windows, and
  `theme-apply.sh` runs; switching the active theme reloads; a Settings preview
  (`dwm-settings-theme preview`) and its revert reach dwm.
- **SIGUSR1** reloads all three files. **Idle:** dwm used 0 CPU ticks in 10 s.

On the branch build only:

- **Two monitors** (two RandR monitors on the one screen, `xrandr
  --setmonitor`): dwm splits the tags 1-4 / 5-9, one panel per monitor; a new
  window opens on the selected monitor; Super+Shift+period and comma move it
  across and back, its tag with it; Super+comma and period move the selection.
  Back to one monitor: one panel, the tag checks pass again.
- **Menus:** the launcher, Control Center, keybind viewer (54 keys: the 90
  less the 36 tag keys), window overview and power menu open.
- **Lock** (`dwm-lock`): locked, unlocked at the greeter, the same dwm
  process carried on. **Super+Ctrl+Shift+q** ends the session.

## Found in the first run, and fixed (beta.6)

Each was checked against `main` (`ddd33dc`) first, then fixed with a test that
fails without the fix:

- **Every `lyona-update apply` ended with "MISMATCH: privileged helper
  lyona-update-root".** The helper now carries only `@PREFIX@` and reads the rest
  of its layout from `/etc/lyona-release`, which `stamp-system` records.
- **`lyona-update rollback` refused its own backup** (`usr/share/icons/...`): updates
  installed the shared data under `/usr/local/share`. The helper installs with its
  recorded layout, `DATADIR` defaults to `/usr/share` for `PREFIX` `/usr` and
  `/usr/local`, and a restore also accepts the old `PREFIX/share` locations.
- **The panel was a window in the overview**; the state bridge leaves docks out.
- **Popups had no keyboard with a window open.** A popup asks for the focus
  (`requestActivate`), dwm gives it to a viewable override-redirect window and
  hands it back when the popup goes.
- **The update popup lost its reason** to the next channel check (`outcomeMessage`).
- **Seven suite steps** failed in `stage_helpers` (only `*.sh` are libraries now).

## Found in the second run, and fixed

- **Overview Enter and the panel's running apps did not switch windows:** dwm
  answered `_NET_ACTIVE_WINDOW` only with urgency. A pager request (source 2) now
  switches; an application's own request is still only urgent.
- **The second monitor's panel named no window:** dwm publishes
  `_DWM_MONITOR_WINDOWS`.
- **A window class with no themed icon** drew an empty button, then Qt's
  missing-image checkerboard; now the generic icon or the class's initial.
- **A shell reload took the bar away.** Quickshell's reload notice is a dock too:
  dwm took it for the bar on every ConfigureNotify, the two were raised over
  each other without end (79 ticks in 2 s, measured), and when the notice went
  windows covered the panel until the next login. A monitor keeps one bar; a
  waiting dock is promoted when the bar goes.
- **Restart Quickshell did nothing from a TTY or ssh:** Qt's locale warning went
  to stdout and broke `quickshell list --json`.
- **A rollback named the wrong version:** backups took it from the release being
  installed, not the live one.
- **Stale theme copies under `/usr/local/share`** shadowed the current ones; the
  install removes lyona's own (where its license directory shows it installed
  there).
- **A SIGUSR1 reload waited for the next X event** to apply (no flush before
  `select()`).
- From the code review: `focusin()` kept a focused popup's keyboard;
  Settings > System shows the update outcome; a border change re-tiles every
  monitor; the emergency keys are a compile-time table in `dwm.c` (no write to a
  `const` member).

## The beta.6 runs (2026-10-09)

| | |
| --- | --- |
| Image | `lyona-2026.10.0-beta.6-x86_64.iso`, built from this branch, SHA-256 `cd78abbdf455a7688386b1208d34cb2b8b8532eb5328af490a6321f83daba5f4` |
| Build host | Arch Linux, kernel 7.2.9-1-cachyos, archiso 91-1, squashfs-tools 4.6.1-2 (releng copy with `-Xbcj x86` only) |
| VM | QEMU 11.1.2, KVM, q35, 4 GB, 4 CPUs, OVMF 202608 (UEFI), `-vga std` 1280x800, virtio disk 32 GB |
| GPU and driver path | QEMU standard VGA; no NVIDIA GPU, so no driver question |

- **Fresh install from the beta.6 image** (ext4): boots to LightDM; the first
  login shows "Welcome to lyona" (#295); `/etc/lyona-release` records the layout;
  nothing under `/usr/local/share`.
- **Every check** on it: 96 of 96 on the final build (session, EWMH, tags, the
  window functions, the popups taking and returning the keyboard, Enter in the
  overview, the bridge, hot reload of all three files, SIGUSR1, idle). dwm's RSS
  stayed flat over three more passes.
- **Updates with beta.6's own code:** apply with no MISMATCH, rollback, apply
  again; `install.sh` from the branch keeps an edited `hotkeys.toml`.
- **beta.5 to beta.6** (fresh beta.5 image install, beta.5's updater and helper):
  apply verifies, rollback restores beta.5.
- **An install with earlier updates** (its helper baked for `/usr/local/share`):
  the update named and removed the 12 stale copies, verified, and rolled back.
- **A shell reload** with a window open: the bar stays, windows stay below it,
  dwm used 0 ticks in 10 s. **Restart Quickshell** under a C locale restarts it.

The full suite, each step on its own: 150 of 151 on the final tree, and the one
failure (`check-lyona-update`, the backup label stopping an update under
`set -e`) fixed and passing.

### Closing focus and the installer's status (rebuilt image)

- Closing a window focuses the window focused before it (`unmanage()` takes it
  from `m->stack`), where it focused the master: tested in
  `check-dwm-activate-xvfb`, and in the VM for the launcher and the keybind
  viewer.
- The installer's step status: at the screen's left edge, wrapped within it
  (the step and its progress bar in two lines at most, the newest log line in
  three), pacman's last redraw without escape remains, an ASCII spinner, the
  cursor hidden. Wrapped by characters in Bash, not by `fold`, which counts the
  bar's block characters as bytes. Tested in `check-install-step-timing`.

The image rebuilt with both: `lyona-2026.10.0-beta.6-x86_64.iso`, SHA-256
`145c6a80e288dd5a920a417edcd941dfc0b0490e4adbde2621474ea59a7b499e`, same host
and VM as above. A fresh install (btrfs) showed the status under the summary
box with the log line wrapped, booted to LightDM and passed all 96 checks, the
close-focus ones among them. On that install the step name with its progress
bar was still cut at the column's width, not wrapped.

Rebuilt again with the step name wrapped: SHA-256
`9956f9f10da9bc5d12b88dd9c6edd2ec6a9bced471dd804f3f52686c3144bc32`. A fresh
install (btrfs) showed "(step 8/9) Running install.sh --profile full as
tester..." and its progress bar wrapped to a second line under the spinner, the
log line below it; it booted to LightDM and passed all 96 checks. The checks need
`xorg-xwininfo` and a `dbus-monitor` for notifications, neither part of lyona;
both were added to the VM for the run.

The full suite on the final tree, each step on its own: 151 of 151, none
skipped. The review fixes that followed (the legacy theme cleanup and its
backup, `dwm-xwatch` watching `_NET_WM_WINDOW_TYPE`, the step timing) landed
while it ran; the steps they touch were run again after it, with the new
`check-dwm-xwatch-xvfb`, and pass. `check-update-root-backups` skips outside a
container, so it ran as root in an `archlinux:base-devel` container: it passes,
and fails without the backup fix.

## Not tested

- Real hardware, legacy BIOS, an NVIDIA GPU, two real outputs.
- Moving `~/.config/lyona` away and back in a running session: the session's
  helpers re-create the directory at once, so the test could not control it;
  `make check-dwm-config-fallback` covers the parent watch.
