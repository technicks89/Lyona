# lyona 2026.10.0-beta.6

Seventh beta of the Arch Linux line. This is a **pre-release**: the ISO
workflow publishes every release with `--prerelease`, and a beta is never
promoted to Latest.

Updates now work end to end. `lyona-update` checks an update without a false
mismatch, rolls back with the cursor themes, and keeps the shared data where
the system was installed. The panel's popups take the keyboard while a window
is open, and the window overview no longer lists the panel.

Also in this release:
- the image installer times its steps and names the first keys;
- every AUR build goes through one helper, with reviewed pins;
- the desktop starts fewer resident processes;
- Settings and `install.sh` say more plainly what they do.

`CHANGELOG.md` has the complete list.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-2026.10.0-beta.6.tar.gz` |
| Installer image | `lyona-2026.10.0-beta.6-x86_64.iso` |
| Checksums | `lyona-2026.10.0-beta.6-SHA256SUMS` |
| Signature | `lyona-2026.10.0-beta.6.sigstore.json` |

- **The signature** signs the source archive and the image. Check the image
  with `cosign` (`docs/src/install.md`).
- **The installer image** carries `iso_label=LYONA_2026_10_0_BETA6`.

## Updates (#280)

Found by a full install-and-update run in a VM:

- **No false mismatch.** Every `lyona-update apply` ended with "MISMATCH:
  privileged helper lyona-update-root" and asked you to roll back, after a
  good install. Its check filled in one of the four paths written into that
  helper.
- **Rollback works.** `lyona-update rollback` refused its own backup ("a path
  outside the managed install locations: usr/share/icons/..."): the update had
  reinstalled the helper for `/usr/local/share`.
- **The shared data stays put.** With `PREFIX` `/usr/local` (or `/usr`),
  `make install-system` now puts the cursor and GTK themes, the GRUB theme and
  the licenses in `/usr/share` by default, as `install.sh` always did, and the
  update helper installs with the paths it was installed with, recorded in
  `/etc/lyona-release`. Any other `PREFIX` keeps them inside it.
- **Stale copies go.** Earlier updates left copies of those themes under
  `/usr/local/share`, which is searched first, so they hid the current ones.
  The install removes lyona's own copies, only where lyona's license directory
  shows it installed there, and names each one; a theme you installed there
  yourself is kept.
- **The reason stays on screen.** After a failed update, the panel's popup
  showed "The installed release matches the channel." under "The update did
  not finish"; it now keeps the error.

## The desktop

- **Popups take the keyboard (#280).** With any window open, Escape, the arrow
  keys and typing went to that window, not to the window overview, the
  Control Center, the power menu or the other panel popups. A popup now asks
  for the focus; dwm gives it, and gives it back to your window when the popup
  closes.
- **The overview lists windows only (#280),** not the panel as a window called
  "quickshell".
- **Choosing a window switches to it (#280).** Enter in the overview, or a
  click on a running app in the panel, now focuses that window, on its own tag
  too. dwm used to only mark it urgent. An application asking for the focus
  for itself is still only marked urgent, so nothing steals it.
- **Each monitor's panel names its own window (#280),** where the second
  monitor's said "Desktop".
- **Closing a window goes back to the one you were on (#280),** not to the
  first tiled window; so does Escape in the launcher and the keybind viewer.
- **Windows without a themed icon** show the generic icon when the theme has
  one, else the app's initial, instead of an empty button.
- **The panel survives a shell reload (#280).** An update reloads the shell's
  configuration; its "reloaded" notice was taken for the bar, dwm and the shell
  raised the two over each other without end, and afterwards windows covered
  the panel until the next login.
- **Restart Quickshell** (Control Center, `Super`+`Shift`+`R`) works from a
  TTY or ssh too.
- **Fewer resident processes (#283-#287):** Bluetooth and media come through
  Quickshell's own services; Settings > System runs one watcher where it ran
  eight; the panel's state bridge starts about 80% fewer processes when a
  window's title changes; closed popups hold no lists; `dwm-status` is no
  longer started.
- **The volume keys** change the output the panel shows, through PipeWire or
  PulseAudio, instead of the ALSA Master control (#278).
- **Settings:** search finds "shortcut", "hotkey" and "keybind" (#293);
  Appearance > Compositor can let full-screen windows bypass Picom (#288);
  Defaults shows the AppImage handler (#276); Toolkit themes show as applied
  (#274).
- **Lock** reports failure when nothing locked the screen (#269).
- **dwm's runtime configuration** (`hotkeys.toml`, `themes.toml`,
  `window-rules.toml`, their reload) moved from `dwm.c` into `config.c`
  (#280), with no change in behaviour.

## Installing

- **The image installer** shows how long each step has run, how long it
  usually takes and the newest line of its log (#291), wrapped within the
  screen and lined up with it, and names the first keys to know (#295).
- **`install.sh`** leads its summary with what it changes on the system,
  asks about CachyOS just before the confirmation (#294), and ends with its
  warnings (#290).
- **The recommended profile** adds Thunar and NetworkManager (#292).
- **AUR builds** (`yay-bin`, `topgrade-bin`, the legacy NVIDIA drivers) go
  through `dwm-aur.sh`, with pinned commits and checksums, built as you within
  a time limit (#281).
- **QEMU/KVM installs** get the guest utilities again (#310).

## Upgrading from 2026.10.0-beta.5

- **The update:** with `lyona-update` (or Settings), or from a checkout with
  `git pull` and `./install.sh`.
- **The first update runs beta.5's code, once:** beta.5's helper does the
  install and beta.5's `lyona-update` checks it. This release is shaped so
  that check passes. Rollback with beta.5's backup works from this release's
  helper. Log out and back in afterwards, for the new `dwm`.
- **After `lyona-update`,** also run `./install.sh` from a checkout, or install
  the new packages yourself (Thunar and NetworkManager in the recommended
  profile). `lyona-update` installs lyona's own files, not packages.
- **`hotkeys.toml`:** bindings still at an earlier release's default move to
  this release's, after a backup; bindings you changed are kept (#273, #278).

## Qualification status

**Not tested on real hardware.** On the build host (Arch with the CachyOS
repositories, x86_64): the full suite, each step on its own, passed on the
release tree; the root-helper tests passed as root in a disposable container.

**In a VM** (QEMU/KVM, UEFI, standard VGA, no NVIDIA). The image was built three
times as the last fixes landed; each build was installed fresh:
- **The release tree's image** (SHA-256
  `9956f9f10da9bc5d12b88dd9c6edd2ec6a9bced471dd804f3f52686c3144bc32`): a fresh
  install (btrfs) reached the desktop, and all 96 desktop checks passed: the
  window functions, tags, closing a window back to the one before it, the
  popups and the overview by keyboard, hot reload of the three configuration
  files, and idle cost. The installer's step status wrapped within the screen.
- **The first build** (SHA-256
  `cd78abbdf455a7688386b1208d34cb2b8b8532eb5328af490a6321f83daba5f4`, before
  the close-focus and installer-status fixes): a fresh install (ext4) passed the
  same 96 checks.
- **Updates:** with this release's code, and from a fresh beta.5 install with
  beta.5's code, apply verified and rollback restored; an install with earlier
  updates had its stale theme copies removed.
- `docs/evidence/280-config-split.md` has the details.

**Not tested yet:** real hardware, legacy BIOS, NVIDIA, Wi-Fi installs, two
physical outputs (two monitors were tested as Xinerama screens and RandR
monitors), and a real run of the signing workflow.
