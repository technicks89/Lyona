# ARCH-005: the 2026.10.0-beta.7 image, a fresh install and an update from beta.6

The release workflow's `2026.10.0-beta.7` image, installed fresh through the
wizard to the desktop; and the beta.6 image installed the same way, then
updated to beta.7 with beta.6's own updater, rolled back, and updated again.
This closes the first item of the release notes' "Not tested yet" list. Real
hardware is still untested.

## Images and machine

- **beta.7:** `lyona-2026.10.0-beta.7-x86_64.iso`, SHA-256
  `0a63f0292ecb0baebfe4788316939a72e6b32a5ce5658fcab3fcc67b244eb834`, verified
  against the release's `SHA256SUMS`. `/etc/lyona-iso-release` on the medium:
  version `2026.10.0-beta.7`, label `LYONA_2026_10_0_BETA7`, commit
  `e1c92e9b3945f2d6b0c4b11dd3d0dc566b46355c`, built `2026-10-24T14:44:18Z`.
  The medium carries archinstall 4.5-1, linux 7.2.11.arch1-1, gum 2.0.2-1.
- **beta.6:** `lyona-2026.10.0-beta.6-x86_64.iso`, SHA-256
  `1c1722b6d0b6cd400e45d09a8fddaa571598e17343b119b0505d41ae4ef13a84` (the same
  image as `arch001-wizard-fallback.md`), commit `1bfafac`.
- **Machine:** QEMU 11.1.2 with KVM, q35, x86_64, 4 vCPUs, 4 GiB, UEFI
  (OVMF), a standard VGA adapter at 1280x800, no NVIDIA GPU, a 40 GiB virtio
  disk, user-mode networking. One VM per image.
- **How:** each medium was booted from its own kernel and initramfs with a
  serial console added, so the wizard's log (`/var/log/lyona-install.log`)
  could be read from a root shell on `ttyS0` while the wizard itself ran on
  `tty1`, driven with QEMU's `send-key` and checked with `screendump`. The
  installed systems were then booted from the disk alone. For the checks,
  `openssh` was installed on each installed system from a terminal in the
  session, with a key and a passwordless sudo rule for the test user; nothing
  else was changed by hand.

## The wizard, both images

Every answer was the default or the first choice: keymap `us`, the one disk
(`/dev/vda`), btrfs without encryption, user `lyona`, hostname `lyona`, the
online timezone lookup accepted (it found `America/New_York`), mirrors in the
United States, no NVIDIA question (none detected), then "Wipe /dev/vda and
install". The summary screen showed every answer. beta.7's summary also shows
the Wi-Fi country (`United States (US)`, from the timezone).

| Image | archinstall | postinstall | Total of the steps |
|---|---|---|---|
| beta.7 | 59 s | 2 m 11 s (12 steps; `install.sh --profile full` 54 s) | 3 m 10 s |
| beta.6 | 1 m 01 s | 2 m 01 s (10 steps) | 3 m 02 s |

Both rebooted on their own after the closing screen, with no warning listed,
and booted to LightDM. Seen in both logs, none of them a failure:

- `cdn77.cachyos.org` answered 404 for a few `x86_64_v3` packages; pacman
  dropped that mirror for the transaction and took the packages from the
  next one.
- pacman's "Refreshing PackageKit" hook fails inside the chroot ("The name is
  not activatable"), as there is no system bus there.
- beta.7 only: `/etc/plymouth/plymouthd.conf` was already in place when the
  `plymouth` package was installed, so pacman left the package's copy as
  `plymouthd.conf.pacnew`.

## The fresh beta.7 install

- `/etc/lyona-release`: version `2026.10.0-beta.7`, commit `e1c92e9b...`,
  source `iso`; `dwm -v` says `dwm-2026.10.0-beta.7`; the Control Center and
  Settings -> System show the same. `lyona-update check`: `current`, on the
  `preview` channel.
- Boot: `linux-cachyos` 7.3.0-4, the `plymouth` hook before `autodetect`,
  `splash` on the command line through `/etc/default/grub.d/90-lyona-splash.cfg`,
  and Plymouth started at boot (journal). `lightdm`, `bluetooth` and
  `power-profiles-daemon` enabled; no failed units.
- `/etc/modprobe.d/lyona-regdom.conf` sets `ieee80211_regdom=US` (#365).
- The 48-check desktop battery of the #447 deep dive (session processes,
  EWMH, tags, tiling, floating, monocle, the launcher, overview, Control
  Center, keybinds, power menu, every Settings section, hot reload of
  `hotkeys.toml`, `window-rules.toml` and `themes.toml`, SIGUSR1, close
  focus, idle CPU): **48 of 48**, with dwm, Quickshell and Picom each at 0
  CPU ticks over 10 s idle.
- Three logout and login cycles through the shell's own action: after each
  logout only the user manager's services remained (PipeWire, WirePlumber,
  the keyring, dconf); no dwm, Quickshell or Picom. Each login came back with
  the panel.
- **#448:** `kill -9` of Xorg from the session, then a login at the greeter:
  the dead login was gone from `loginctl`, and the new session had dwm,
  Quickshell and Picom, with the panel shown.

## beta.6 to beta.7 with beta.6's updater

On the fresh beta.6 install, before the update: `lyona-update check` said
`behind`, beta.7 available. A Super+F11 binding was added to the user's
`hotkeys.toml`, and the package list, the enabled units and every file under
`/usr/local` were recorded.

- **`lyona-update apply`** (beta.6's code, over ssh, so the sudo path): it
  downloaded `lyona-2026.10.0-beta.7.tar.gz`, verified the checksum and the
  Sigstore signature, built with the user's `config.h`, warned that
  `xorg-xmessage wireless-regdb iw` are not installed (as the release notes
  say), asked for confirmation (`--yes` given on the second run), backed up
  the live install, installed through `lyona-update-root`, created the
  `lyona-build` user, reported "All managed files match the checkout", and
  restarted Quickshell. The panel stayed; "Update complete" was shown at the
  next login. `/etc/lyona-release` became `2026.10.0-beta.7`, source
  `tarball`, commit `unknown`; `lyona-update check`: `current`.
- **The user's files:** the Super+F11 binding was kept. `hotkeys.toml` was
  rewritten once by the release reconciliation, which moved the Super+R
  binding to this release's default (`hold_keys="dwm launcher"`, #391) and
  kept the previous file as `hotkeys.toml.bak.<time>`, saying so in the log.
  `themes.toml` and `window-rules.toml` were untouched.
- After logging out and in, `dwm -v` was `dwm-2026.10.0-beta.7`, and the same
  48-check battery passed **48 of 48**.
- **`lyona-update rollback --yes`:** restored beta.6 in 2 s (`/etc/lyona-release`
  back to beta.6, source `iso`, the ISO commit; `dwm -v` beta.6 after a
  relogin; `check` says `behind` again). Packages and enabled units were
  identical to the record taken before the update. Under beta.6's dwm the
  migrated `hotkeys.toml` (with `hold_keys`) still loaded: Super+F11 ran its
  command and Super+R opened the launcher.
- **`lyona-update apply --yes` again:** the same steps, a second backup, and
  after a relogin `dwm-2026.10.0-beta.7` with `check` `current`. Both backups
  are listed by `rollback --list`.

## Findings

- **A rollback leaves a command beta.7 added.** After the rollback,
  `/usr/local/bin/install-yay` (new in beta.7, #339) was still installed; it
  was the only difference under `/usr/local` from the pre-update record. The
  guide says a rollback restores the system half of the backup, and it did;
  it does not remove files the newer release added. ARCH-003's acceptance
  asks for "the exact pre-upgrade state". Harmless here (the script only
  installs yay), but a newer release's helper left on an older system is the
  kind of thing a rollback exists to undo.
- **A rollback keeps the migrated `hotkeys.toml`.** The rollback restored
  the backed-up Quickshell config and the system files; the user's
  `hotkeys.toml`, rewritten by beta.7's reconciliation (Super+R with
  `hold_keys`), stayed as beta.7 left it, with beta.6's version beside it as
  `hotkeys.toml.bak.<time>`. That follows the updating guide, which names the
  Quickshell config and the data directory as the only user files a rollback
  restores, and beta.6's dwm read the migrated file without complaint; still,
  a rolled-back system carries one file of the newer release's making.
- **A tarball update records no commit.** `/etc/lyona-release` and
  `lyona-update check` show `unknown` for the installed commit after an
  update, where the ISO install recorded the release commit. The source
  archive carries no commit stamp for the installer to copy.
- The `.pacnew` and the PackageKit hook message above are cosmetic.

## Not covered here

Real hardware, NVIDIA and the legacy NVIDIA drivers, Wi-Fi installs, two
physical outputs, LUKS and legacy BIOS with this image (both were qualified
on the beta.6 image), the Plymouth passphrase prompt, and the Settings
update button (the update was run from a terminal over ssh, which takes the
sudo path rather than polkit).
