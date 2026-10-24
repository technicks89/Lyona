# lyona 2026.10.0-beta.7

Eighth beta of the Arch Linux line. This is a **pre-release**: the ISO
workflow publishes every release with `--prerelease`, and a beta is never
promoted to Latest.

The desktop keeps up on a busy machine. Keys typed straight after Super+R
reach the launcher, and an early Enter launches the match. Shortcuts, popups
and menus no longer lose the keyboard when events arrive in an unlucky order.
The shell is no longer restarted while it is still starting, and it comes back
after the X server dies. A portrait layout no longer crashes dwm at login.

Also in this release:
- shell menus work without a compositor;
- Wi-Fi connects quickly on 5 GHz, and Bluetooth is enabled at install;
- an installed system boots with the lyona splash, which also asks for an
  encrypted disk's passphrase;
- a failed update says why, and a downgrade is named as one;
- the update's root helper builds `config.h` as its own system user;
- the tests no longer touch the desktop they run from.

`CHANGELOG.md` has the complete list.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-2026.10.0-beta.7.tar.gz` |
| Installer image | `lyona-2026.10.0-beta.7-x86_64.iso` |
| Checksums | `lyona-2026.10.0-beta.7-SHA256SUMS` |
| Signature | `lyona-2026.10.0-beta.7.sigstore.json` |

- **The signature** signs the source archive and the image. Check the image
  with `cosign` (`docs/src/install.md`).
- **The installer image** carries `iso_label=LYONA_2026_10_0_BETA7`.

## Keyboard and focus

- **Keys typed after Super+R go to the launcher (#391, #443).** The launcher
  appears 30 to 50 ms after the key. Until now, what you typed in that time
  went to the window you were in, so an Enter in a terminal ran it. dwm now
  holds those keys and hands them to the launcher in order once it has the
  focus, or after one second if it never opens. A `hotkeys.toml` binding can
  ask for this with `hold_keys="WINDOW"`, and the default Super+R does.
- **An early Enter launches (#389).** An Enter pressed before the application
  list loaded did nothing. It now launches the best match as soon as the list
  arrives.
- **Shortcuts survive a keyboard change (#411).** A dwm key pressed as the
  keymap changed, for example the first key from a second keyboard, went to
  the focused window.
- **Popups give the keyboard back (#395).** After a quick popup closed on a
  busy machine, no window had the keyboard until you clicked.
- **Menus stay open (#397, #431).** A panel menu could vanish as it opened.
  Picom starting or stopping with a menu open could leave the menu the wrong
  size.
- **Open windows come forward (#413).** Opening Settings, System Health or the
  notification history while it is open on another tag now brings it to you.
- **Steam's menus stay open, and tray menus open again.** Right-clicking
  Steam's tray icon opens its menu in the panel's own style. An app with a
  window open no longer shows twice on the panel.

## The shell and the session

- **No restart while the shell starts (#394).** At login, or after an early
  Super+R, a shell that was nearly up could be killed and replaced. Now the
  key waits for it, and with no shell running, the key starts one.
- **The panel comes back after the X server dies (#448).** The next login had
  no panel, because it waited for the dead login's shell. The same fix ends
  what is left of a dead login, so XDG autostart applications such as Blueman
  start again.
- **Shell keys restart a stopped shell (#338).** When it cannot start, the
  message appears with `xmessage`.
- **Menus without a compositor (#384).** With Picom stopped, or on a machine
  where it cannot run, every menu blacked out the screen below the panel. The
  menus now draw correctly, and a click outside one still closes it.

## Displays

- **Portrait at login (#371, #387).** A kept layout that turned a screen to
  portrait crashed dwm at every login. A test now covers the path from login
  to the docked panel.
- **Previews recover (#369, #371, #372).** After an interrupted change,
  Settings > Displays and Input no longer stay stuck asking you to keep it.
  Rotating the screen Settings is on keeps Keep and Revert on screen.
- **AMD crashes (#386).** Settings stops Picom around its own layout changes,
  since a rotation under Picom crashed Xorg with xf86-video-amdgpu 25.0.
  autorandr now does the same, through a hook in `/etc/xdg/autorandr/`. A
  plain `xrandr` is not covered. Whether a current xorg-server still crashes
  is not yet tested (`docs/plans/386-amd-layout-crash.md`).
- **The greeter (#414)** shows the whole logo, and its top bar is one even
  shade.

## Updates

- **A failed update says why (#333).** It used to say "authentication
  required" for every failure. A system install that stopped part-way now
  names its backup and says to roll back.
- **A downgrade is named as one (#334).** Settings > System offers "Go back to
  VERSION", and only then passes `--allow-downgrade`.
- **Missing desktop packages (#399).** The warning, the notification and
  Settings now give the command that installs them.
- **The root helper (#336, #337)** builds dwm, the one program that includes
  your `config.h`, as the system user `lyona-build` instead of `nobody`. It
  refuses versions it cannot compare. It runs `make` from a fixed path.

## Installing

- **The Plymouth splash on the installed system.** The image's installs boot
  with the lyona splash, and an encrypted disk asks for its passphrase there.
  `docs/src/install.md` says how to turn it off. `install.sh` on an existing
  system does not add it.
- **Wi-Fi (#365).** The `network` packages add `wireless-regdb` and `iw`.
  Without them, every connection first timed out on 5 GHz. The image
  installer sets the Wi-Fi country from the timezone.
- **Bluetooth (#380)** is enabled on the new system, and by `install.sh`
  (recommended and full).
- **archinstall 4.5.** The installer writes archinstall 4.5's configuration
  forms.
- **USB boot.** The medium no longer copies itself into RAM at boot, which
  held the splash for most of a minute. Keep the stick plugged in until the
  install finishes.
- **`install.sh`** keeps a GTK theme you set yourself as `FILE.bak.<time>`
  before writing lyona's, and names it. One helper, `install-yay`, builds yay
  for both install paths (#339).
- **Fewer false System Health warnings** on a fresh install: autorandr's login
  entry, DNS without systemd-resolved, and a nearly full install stick.

## Tests

- **Tests no longer act on your desktop (#368, #404, #408).** A test run
  inside a session flashed the screen and changed the GTK theme. It could
  also replace your kept display layout or empty the Picom log. A run now
  gets its own display, bus, runtime, configuration, data, state and cache
  directories. It also drops the `DWM_*` and `LYONA_*` overrides of the shell
  you run it from. `make check-session-isolation` checks all of this.
- **Intermittent failures** found under load were traced to the product and
  fixed above, wherever the product was at fault. The deep dive into the
  rest continues in #447.

## Upgrading from 2026.10.0-beta.6

- **The update:** use `lyona-update` (or Settings), or from a checkout run
  `git pull` and `./install.sh`. Log out and back in afterwards for the new
  `dwm`.
- **The first update runs beta.6's code, once.** beta.6's helper installs this
  release and beta.6's `lyona-update` checks it.
  `tests/test-update-root-contract.sh` runs the previous release's helper
  against this tree, but no VM update from beta.6 to beta.7 has been run yet
  (see below).
- **New packages:** `lyona-update` installs lyona's own files, not packages.
  A system installed from beta.6 or earlier lacks three:
  `sudo pacman -S --needed wireless-regdb iw xorg-xmessage`.
  The update's own warning and Settings > System give this command too.
- **`hotkeys.toml`:** Super+R still at its shipped default gets
  `hold_keys="dwm launcher"`, after a backup. A Super+R you changed is kept;
  add `hold_keys` to it yourself if you want the held keys.
- **A new system account:** `make install-system` creates `lyona-build`
  through `systemd-sysusers` (`/usr/lib/sysusers.d/lyona-update.conf`).
- **autorandr:** the update installs the Picom hook in `/etc/xdg/autorandr/`,
  and `make uninstall` removes it.
- **If you ran the test suite inside a session before this release,** your
  GTK theme may still be a test theme. Apply your theme again from
  Settings > Appearance. A kept display layout the tests replaced has to be
  chosen again in Settings > Displays.

## Known issues

- **#386:** a layout change by a plain `xrandr` under Picom may still crash
  Xorg on AMD. The fixed xorg-server 21.1.25-2 is untested on that hardware.
- **#416:** screens can stay black after monitors are powered off and on,
  because light-locker leaves its blanking windows over them.
- **#444:** Settings can miss a wallpaper applied outside it while the
  appearance watch restarts.
- **#447:** the deep dive into intermittent test failures is still open.

## Qualification status

**Not tested on real hardware.**

What has been tested since beta.6, all in QEMU/KVM VMs (q35, x86_64,
standard VGA, no NVIDIA):
- **The wizard and the manual `archinstall` fallback** from the beta.6
  workflow image reached the desktop under UEFI, with btrfs and ext4
  (`docs/evidence/arch001-wizard-fallback.md`).
- **The archinstall 4.5 configuration** installed and booted under UEFI with
  LUKS and under legacy BIOS (`docs/evidence/arch001-archinstall-4.5.md`).
- **Legacy BIOS:** an image from `main` at `2b7d9cc` reached the desktop
  through the wizard (`docs/evidence/arch004-legacy-bios.md`).
- **LUKS:** an install with btrfs in LUKS reached the desktop
  (`docs/evidence/arch002-luks-desktop.md`).
- **The existing-system installer** ran on a stock Arch system that already
  had user data. That run found the GTK theme overwrite fixed above
  (`docs/evidence/arch003-existing-system-install.md`).
- **The X server dying (#448)** was reproduced and fixed in a VM by killing
  Xorg and logging in again.
- Each fix's own evidence is under `docs/evidence/`.

**The release tree:** the full suite, in an Arch Linux ARM container (aarch64,
Xvfb), passes apart from the checks that need an x86_64 Arch host. On GitHub's
x86_64 runners, the `make check` workflow runs it all.

**Not tested yet:**
- this release's own image: a fresh install, and an update from beta.6 to
  beta.7 with beta.6's updater, then a rollback;
- real hardware, AMD included (#386), NVIDIA and the legacy NVIDIA drivers,
  Wi-Fi installs, two physical outputs, and the Plymouth passphrase prompt on
  hardware.
