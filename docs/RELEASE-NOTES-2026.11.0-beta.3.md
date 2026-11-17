# lyona 2026.11.0-beta.3

Eleventh beta of the Arch Linux line, and the third release for aarch64. This
is a **pre-release**: the ISO workflow publishes every release with
`--prerelease`, and a beta is never promoted to Latest.

This release works through the six-agent review of beta.2 (#515-#535). It also
records the first validated update between two aarch64 releases: beta.1 to
beta.2, on a Dell XPS 13 9345 and a Raspberry Pi 4 (#490).

New in this release:
- the panel from the keyboard: **Ctrl+Alt+Tab** moves the keyboard onto the
  panel, and every panel item has an accessible name (#534);
- a **Title bars on floating windows** switch and **Reset to Default** in
  Settings > Appearance > Layout (#530);
- **Skip xclip** in clipboard history, so `pass -c` and `gopass` copies are not
  kept (#535);
- enrolling a finger asks for the administrator password while any
  fingerprint use is on (#535);
- choosing the adapter for a hidden Wi-Fi network when there are several
  (#534).

Fixed:
- fullscreen in dwm: a window could lose its tile, the monitor it was sent to,
  or its own mode when swallowed (#533);
- saving one layout value in Settings reset every unsaved Super+H/L and
  Super+I/D change (#515);
- a failed clipboard source left the Capture switch on, so a click turned
  capture off and deleted the saved history (#516);
- a rollback lost the panel's widget choices (#520);
- Settings > Fingerprint disappeared when the reader was gone, with a use
  still on (#522);
- after an update, Settings said only "Update complete" when a logout was
  needed (#521).

`CHANGELOG.md` has the complete list.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-2026.11.0-beta.3.tar.gz` |
| Installer image, x86_64 | `lyona-2026.11.0-beta.3-x86_64.iso` |
| Installer image, aarch64 (UEFI) | `lyona-2026.11.0-beta.3-aarch64.iso` |
| Raspberry Pi image | `lyona-2026.11.0-beta.3-rpi-aarch64.img.xz` |
| Checksums | `lyona-2026.11.0-beta.3-SHA256SUMS` |
| Signature | `lyona-2026.11.0-beta.3.sigstore.json` |
| Architecture markers | `lyona-2026.11.0-beta.3-architecture-x86_64`, `lyona-2026.11.0-beta.3-architecture-aarch64` |

- **The signature** covers the source archive and all three images. Check an
  image with `cosign` (`docs/src/install.md`).
- **The architecture markers** hold only their architecture's name.
  `lyona-update` reads them to know which architectures a release serves
  (#53).
- **The installer images** carry `iso_label=LYONA_2026_11_0_BETA3`.
- **All three images are built from the same commit, by one workflow run.**

The aarch64 targets and their status are unchanged from 2026.11.0-beta.2
(`SPEC.md` section 4).

## The desktop

- **The panel from the keyboard (#534, `docs/src/keybinds.md`).**
  - **Ctrl+Alt+Tab** moves the keyboard onto the focused monitor's panel,
    starting at the logo.
  - **Tab** and the arrow keys move between the logo, tags, clock, running
    apps, tray icons and pills. A focus ring and the item's tooltip show
    where you are.
  - **Enter** or **Space** does what a click does. **Up** and **Down** on the
    volume pill change the volume. The **Menu** key opens a tray icon's menu.
  - **Escape** gives the keyboard back to the window. A popup opened from the
    panel gives the keyboard back to the panel when it closes.
  - dwm now gives a bar the keyboard when the bar asks for it, but only while
    the bar says it takes input.
- **Panel accessibility (#534).** Every pill, tag, running app and tray icon
  has an accessible role and name. Screen readers can press the clickable
  ones. The keyboard layout pill's tooltip names the layout a click switches
  to.
- **Settings > Appearance > Layout (#530).**
  - A **Title bars on floating windows** switch and the tags they show on,
    instead of editing `themes.toml` by hand.
  - **Reset to Default** for the tag shown.
  - Monitors are named by their output (`DP-1, tag 1`).
  - The limits for master size, count and gap are checked to agree between
    dwm, the helper and the sliders.
- **Fullscreen in dwm (#533).** dwm now tracks a window's fullscreen mode as one
  state with a fixed table of moves, instead of three flags. Fixed:
  - a window could leave fullscreen at the monitor's size;
  - a tiled window left fullscreen overlapping the windows tiled meanwhile;
  - a window went back to the first monitor after being sent to another one
    while fullscreen;
  - Super+J/K moved focus out of one kind of fullscreen;
  - a swallowed window inherited the terminal's fake fullscreen.

## Privacy and security (#535)

- **Clipboard history:** **Skip xclip**, off by default, refuses copies owned
  by `xclip` or `xsel`, also when another program forked them. Passwords that
  `pass -c` or `gopass` copy are then not kept. See
  `docs/CLIPBOARD-PRIVACY.md` for what else saved history can contain.
- **Fingerprint:**
  - While any fingerprint use is on, enrolling a finger asks for the
    administrator password. It is a polkit rule,
    `/etc/polkit-1/rules.d/50-lyona-fingerprint-enroll.rules`, kept by
    `lyona-fingerprint-pam`. The update brings the rule in line with the uses
    already set.
  - A finger enrolled outside Settings is shown in Settings > Fingerprint
    until you acknowledge or delete it.
  - `docs/FINGERPRINT.md` names the trade-offs: fingerprint for `sudo`,
    polkit covering Lyona's own administrator actions, no lockout after
    failed attempts, and match-on-chip readers.

## Upgrading from 2026.11.0-beta.2

- **The update:** use `lyona-update` (or Settings), or from a checkout run
  `git pull` and `./install.sh`. **Log out and back in afterwards**: the
  fullscreen fixes and the panel keyboard focus are in the new `dwm`.
  Settings now says so after the update (#521).
- **The first update runs beta.2's code, once.** beta.2's helper installs this
  release, and beta.2's `lyona-update` checks it.
- **No new packages.**
- **Your files:**
  - An update adds the **Ctrl+Alt+Tab** binding to `hotkeys.toml` when no key
    of yours uses that chord and your Super+Alt+F1 Control Center line is
    still the shipped default. Otherwise, add the line from
    `docs/src/keybinds.md` yourself.
  - Each update now keeps `panel-widgets.conf` with its backup, and a rollback
    puts it back (#520).
  - Other user files are kept.
- **Before a rollback to beta.2:**
  - the enroll rule stays in `/etc/polkit-1/rules.d/`, so enrolling still asks
    for the administrator password. Remove the file to undo that;
  - beta.2's `dwm` ignores Ctrl+Alt+Tab focus requests, so the key does
    nothing there. Remove its line from `hotkeys.toml` if you like;
  - the backup made by this update holds `panel-widgets.conf`, so the panel's
    widgets come back as they were.

## Known issues

- **#386 (closed):** the AMD Xorg crash on a layout change is attributed to
  xorg-server 21.1.25-1, fixed in 21.1.25-2. The rotation test on the RX 9070
  with xf86-video-amdgpu was not rerun. Reopen it if the crash returns.
- **Dell XPS 13 9345:** no sound, and a black screen for about 6 s before the
  live installer starts. External displays, suspend and resume, and battery
  life are not covered.
- **Raspberry Pi 4:** Picom stays off at login, because the GPU gives it no GL
  context. The overview shows icon-and-title cards instead of previews.
- **The panel from the keyboard:** if the pointer rests over a different
  window when a popup closes, dwm's focus-follows-mouse can give that window
  the keyboard instead of the panel.

## Qualification status

**Before publication:**
- **Updates on aarch64 (#490, `docs/evidence/arm5-02-updates-on-aarch64.md`):**
  `lyona-update` check, apply, rollback and apply again from beta.1 to beta.2
  passed on the generic image (on a Dell XPS 13 9345) and on a Raspberry Pi 4.
- **Fullscreen (#533), on real hardware** (2026-11-16, x86_64, two monitors,
  installed from 9309946): all seven checks passed. They covered a terminal
  swallowing mpv and feh, browser and video fullscreen, fake fullscreen then
  F11, a game with a windowed fullscreen rule, a fullscreen window sent to the
  other monitor, and Super+J/K while fullscreen.
- **The full suite** passed on GitHub's x86_64 and aarch64 runners at 9309946
  (run 43966689984), with the clang build and the update and display helper
  root tests.
- **The panel from the keyboard (#534)** passed `make
  check-panel-keyboard-xvfb` (real dwm, shell and keys in Xvfb) and the focus,
  bar and panel Xvfb tests locally.

**Not tested yet:**
- **The full suite on this release commit**, which adds #534 and the release
  changes on top of 9309946.
- **#534 in a real session:** screen readers, two monitors, and the hotkeys
  migration on an existing `hotkeys.toml`.
- **This release's own images:** none has been installed yet.
- **x86_64 hardware:** NVIDIA and the legacy NVIDIA drivers, Wi-Fi installs,
  and the RX 9070 with xf86-video-amdgpu (#386).
- **Fingerprint:** readers other than the Goodix 27c6:6594, and the enroll
  rule on real hardware.
- **aarch64:** everything marked experimental in `SPEC.md`.
