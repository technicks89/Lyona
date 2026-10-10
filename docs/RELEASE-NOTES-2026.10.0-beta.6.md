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
- Settings and `install.sh` say more plainly what they do;
- and, in the published cut, the 2026-10-09 review's fixes (#317 to #328,
  below): a rollback that restores everything, a downgrade on its own prompt,
  `config.h` never compiled as root, and the panel declaring itself the bar.

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

## Added in the published cut (#317 to #328)

The published `v2026.10.0-beta.6` is `1bfafac`, a day after the first cut
(`34c8021`, 2026-10-09), with the fixes from the 2026-10-09 whole-repo review
(`docs/reviews/2026-10-09-whole-repo-review.md`). Beyond the lists above:

- **Rollback restores everything it backed up (#324).** `lyona-update
  rollback` restores `PREFIX/lib/lyona` and `PREFIX/share/lyona` whole, the
  polkit actions and the GTK themes, and the account's install record, where it
  restored only the commands and left the old commands sourcing the new shared
  code.
- **One install layout (#325).** The update and its root helper take `PREFIX`
  and `DATADIR` from `/etc/lyona-release`, so another layout is backed up,
  verified and restored where it was installed.
- **Updating from Settings (#326).** Cancelling the password prompt is a
  cancel, not a failure; the reason for a failed update stays visible; a
  successful update removes what it downloaded and built (about 25 MB a time).
- **`config.h` is never compiled as root (#327).** The root helper builds
  `dwm`, the one program that includes it, as `nobody`; an `#include` in
  `config.h` cannot read root-only files into the installed binary.
- **A downgrade has its own prompt (#327).** An older release is refused on the
  routine prompt and installed only through "Install an older lyona release",
  with its signature verified.
- **Image installer hardening (#328).** yay is built before the install's
  temporary passwordless sudo exists; a sudo rule left by a power-off is removed
  at the next boot; the live medium adds only the baseline CachyOS repository,
  so it is never partially upgraded, and the new system is raised to its CPU's
  level afterwards; the timezone lookup asks before sending your IP address.
- **Focus (#318).** A window closing by itself on the other monitor no longer
  takes or drops the keyboard focus.
- **A broken `hotkeys.toml` says so (#319).** One notification names the first
  problem and how many there are; a file cut off inside an array is refused
  whole, so a running session keeps its keys; an `exec` with more than 32
  arguments no longer loses the rest of the file.
- **The state bridge and the shell lifecycle (#320).** The bridge exits and is
  restarted when its watcher dies; retitling windows rebuild the state at most
  five times a second; the shell keys say how to get the shell back when it is
  not running.
- **The panel declares itself the bar (#322).** dwm takes as the bar only a
  dock that reserves space at the top or bottom of the screen. **Migration:** a
  panel of your own needs a non-zero `exclusiveZone` (a strut).
- **Window previews scaled by the X server (#323).** About a twentieth of the
  data read per preview, four times faster at 4K; `dwm-window-thumb` links
  libXrender.
- **Test hygiene (#321)** and **the documentation catch-up (#317)**: `man dwm`
  describes lyona's dwm, `--help` is complete, and the records match the
  evidence.

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
- **The published cut (2026-10-10):** an image built from `1bfafac` installed
  fresh in the same kind of VM, updated to a `beta.7` build and rolled back,
  refused an unsigned downgrade, took a signed one through the new prompt,
  failed a `config.h` that includes a private file in the root helper's
  `nobody` build, and reported a cancelled prompt as a cancel; Settings was
  opened and used for the downgrade. The strut-based bar and the XRender
  previews were checked there too. `docs/evidence/324-328-install-update-rollback.md`
  and `docs/evidence/322-323-bar-role-thumbnails.md` have the details.

**Not tested yet:** real hardware, legacy BIOS, NVIDIA, Wi-Fi installs, two
physical outputs (two monitors were tested as Xinerama screens and RandR
monitors), and a real run of the signing workflow.
