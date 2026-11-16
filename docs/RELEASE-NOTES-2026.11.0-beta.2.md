# lyona 2026.11.0-beta.2

Tenth beta of the Arch Linux line, and the second release for aarch64. This is
a **pre-release**: the ISO workflow publishes every release with
`--prerelease`, and a beta is never promoted to Latest.

It is the first release an aarch64 install can update to: from
2026.11.0-beta.1, `lyona-update` on Arch Linux ARM now has a release that lists
aarch64 to move to. Validating that update and its rollback on a virtual
machine and a Raspberry Pi is #490, after this release.

New in this release:
- fingerprint authentication for the login and lock screen, administrator
  prompts and `sudo`, in Settings > Fingerprint (#483);
- clipboard history on **Super+V**, off until you turn capture on (#469);
- title bars on floating windows, off by default (#496);
- Settings > Appearance > Layout: layout, master size and count, and a gap
  between tiled windows, per monitor and tag (#479);
- a keyboard layout pill in the panel, and the layout switch key in Settings >
  Input (#470, #473);
- joining a hidden Wi-Fi network from the panel (#471);
- window rules that open a window fullscreen or borderless fullscreen, or
  ignore its size hints, and always-on-top rules for overlays (#477, #497).

Fixed:
- screens that stay black after an idle blank, or after the monitors are
  turned off and on, because light-locker left its blanking windows up
  (#416);
- Settings could miss a wallpaper applied outside it (#444).

`CHANGELOG.md` has the complete list.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-2026.11.0-beta.2.tar.gz` |
| Installer image, x86_64 | `lyona-2026.11.0-beta.2-x86_64.iso` |
| Installer image, aarch64 (UEFI) | `lyona-2026.11.0-beta.2-aarch64.iso` |
| Raspberry Pi image | `lyona-2026.11.0-beta.2-rpi-aarch64.img.xz` |
| Checksums | `lyona-2026.11.0-beta.2-SHA256SUMS` |
| Signature | `lyona-2026.11.0-beta.2.sigstore.json` |
| Architecture markers | `lyona-2026.11.0-beta.2-architecture-x86_64`, `lyona-2026.11.0-beta.2-architecture-aarch64` |

- **The signature** signs the source archive and all three images. Check an
  image with `cosign` (`docs/src/install.md`).
- **The architecture markers** hold only their architecture's name;
  `lyona-update` reads them to know which architectures a release serves
  (#53).
- **The installer images** carry `iso_label=LYONA_2026_11_0_BETA2`.
- **All three images are built from the same commit, by one workflow run.**

The aarch64 targets and their status are unchanged from 2026.11.0-beta.1
(`SPEC.md` section 4).

## The desktop

- **Fingerprint (#483, `docs/FINGERPRINT.md`).** Settings > Fingerprint is
  listed only when fprintd finds a reader. Enroll and delete fingers, then turn
  fingerprint on for each use separately (any enrolled finger is accepted):
  the login and lock screen, polkit, or `sudo`. Each use adds one `sufficient`
  line to its PAM file, so the password always works, and turning it off
  restores the file byte for byte unless it was edited since (then only the
  two lines are removed). A line
  added by hand is shown as set up outside Lyona. A finger at the login does
  not unlock the keyring, and the switch says so. fprintd is installed only
  with `install.sh --with-fingerprint`.
- **Clipboard history (#469, `docs/CLIPBOARD-PRIVACY.md`).** Super+V opens a
  searchable list. Capture and saving to disk are each off until turned on.
  Password managers and copies marked secret are refused before any text is
  read; nothing runs while capture is off.
- **Title bars (#496).** `titlebars = 1` in `themes.toml` (with
  `titlebar_tags`) draws a strip above each floating window to drag it or close
  it. dwm draws it itself, with no new process.
- **Layout settings (#479).** The master size and count and the gap are saved
  per monitor and tag in `~/.config/lyona/layout.toml`, which dwm reloads when
  it changes; the Tile/Floating/Monocle choice applies live and is not saved
  (#517). The gap
  defaults to 0, and tiling at gap 0 is unchanged.
- **Keyboard (#470, #473).** With two or more layouts, a panel pill names the
  active one and a click switches. Settings > Input picks the switch key and
  its LED, and no longer lists power, sleep and lid buttons as keyboards.
- **The panel:** tags with windows are marked (#474), the clock can show
  seconds (#472), long titles scroll once (#499), running apps find their icon
  through the desktop entry (#498), and the weather keeps its last report when
  a refresh fails (#480).
- **Settings and System Health:** Default Apps lists Flatpak applications
  (#476); one **Check Dependencies** action replaces the two before it (#500);
  System Health shows warning and error counts separately and no longer reports
  the UEFI variable store as a storage error (#475, #500).

## Locking and blank screens (#416)

light-locker could leave its full-screen blanking windows up while reporting
itself inactive, leaving the screen black with nothing locked.
- The new `dwm-blank-watch` follows light-locker's `ActiveChanged` signal and,
  when blanking ends, restarts light-locker only if it is inactive with its
  windows still shown.
- The autorandr hook `60-lyona-locker` does the same after a layout change,
  such as monitors turned off and on.
- `dwm-blank-watch` logs each result to the journal
  (`journalctl -t lyona-locker`); the autorandr hook does not log.

A blanked or locked screen is never touched.

## Upgrading from 2026.11.0-beta.1

- **The update:** use `lyona-update` (or Settings), or from a checkout run
  `git pull` and `./install.sh`. **Log out and back in afterwards**: the
  keyboard pill, title bars, layout settings and window rule keys are in the
  new `dwm`, and `dwm-blank-watch` starts at login.
- **The first update runs beta.1's code, once.** beta.1's helper installs this
  release and beta.1's `lyona-update` checks it.
- **No new packages.** For fingerprint, install fprintd:
  `sudo pacman -S --needed fprintd`, or `install.sh --with-fingerprint`.
- **Your files:** an update adds the Super+V binding to `hotkeys.toml` when
  Super+V is free and your Super+R launcher line is still a shipped default
  (otherwise add the line from `docs/src/keybinds.md` yourself), and adds
  window rules for new shell windows (the hidden Wi-Fi prompt and the
  clipboard window) to `window-rules.toml` when no rule of yours names them,
  after a backup. `themes.toml` and other user files are otherwise kept.
- **Before a rollback to beta.1:**
  - turn fingerprint uses off in Settings first, since beta.1 has no
    Settings > Fingerprint to turn them off later (the PAM lines would stay,
    and the password still works);
  - beta.1 reads a `panel-widgets.conf` saved by this release (protocol 1.1)
    as unsupported and shows the default widgets; the first panel widget
    change you make on beta.1 replaces the file, and your beta.2 choices are
    lost (#520). Releases after beta.2 keep the file with each update and put
    it back on rollback;
  - a Settings > Input value saved by this release for a merged keyboard card
    may not apply on beta.1, which does not know merged cards;
  - beta.1's `dwm` ignores `layout.toml` and the new window rule keys.

## Known issues

- **#386 (closed):** the AMD Xorg crash on a layout change is attributed to
  xorg-server 21.1.25-1, fixed in 21.1.25-2. The rotation test on the RX 9070
  with xf86-video-amdgpu was not rerun. Reopen it if the crash returns.
- **Dell XPS 13 9345:** no sound; a black screen for about 6 s before the live
  installer starts; external displays, suspend and resume, and battery life
  are not covered.
- **Raspberry Pi 4:** Picom stays off at login, because the GPU gives it no GL
  context. The overview shows icon-and-title cards instead of previews.
- **Updates between two aarch64 releases** are not validated yet (#490).

## Qualification status

**Before publication:**
- The full suite (`make check`, every target) passed on GitHub's x86_64 and
  aarch64 runners (run 43768010248, at 5f9b8c8, whose tree is `main` at
  cafa4bd), with the display and update helper root tests and the clang
  build. This release commit changes only the version and documentation.
- **Fingerprint and the blank watcher on real hardware** (2026-11-15, a
  ThinkPad with AMD graphics and a Goodix 27c6:6594 reader, installed from
  cafa4bd): fingerprint login at LightDM, unlock of a manual lock, `sudo` and
  polkit prompts, and turning polkit and `sudo` on from Settings. An idle
  blank logged `locker-recover restarted` from the new watcher, and the screen
  came back with one light-locker running.

**Not tested yet:**
- **This release's own images:** none of the three images from this run has
  been installed yet.
- **Updates on aarch64:** `lyona-update` from beta.1 to this release, and the
  rollback, on a virtual machine and a Pi (#490).
- **x86_64 hardware:** NVIDIA and the legacy NVIDIA drivers, Wi-Fi installs,
  and the RX 9070 with xf86-video-amdgpu (#386).
- **Fingerprint:** readers other than the Goodix above; the login switch
  managed by Lyona (the test machine used a line added by hand).
- **aarch64:** everything marked experimental in `SPEC.md`.
