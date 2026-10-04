# lyona 2026.10.0-beta.3

Fourth beta of the Arch Linux line. This is a **pre-release**: the ISO
workflow publishes every release with `--prerelease`, and a beta is never
promoted to Latest.

It brings a smaller install image that boots the CachyOS kernel, and fixes for
the desktop session and Settings found after `2026.10.0-beta.2` (#229, #230,
#231). `CHANGELOG.md` has the complete list.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-2026.10.0-beta.3.tar.gz` |
| Installer image | `lyona-2026.10.0-beta.3-x86_64.iso` |
| Checksums | `lyona-2026.10.0-beta.3-SHA256SUMS` |
| Signature | `lyona-2026.10.0-beta.3.sigstore.json` |

- **The signature** signs the source archive and the image, as in beta.2.
  Check the image with `cosign` (`docs/src/install.md`).
- **The installer image** carries `iso_label=LYONA_2026_10_0_BETA3`.

## What is in this beta

### A smaller image that boots CachyOS

- **The image is expected to be about 700 MB smaller.** It no longer carries
  the desktop's 66 packages, which the live medium never used: the new system
  downloads every package it installs. It keeps only what the wizard runs:
  `gum`, `jq`, `curl`, `openssl`, `pciutils` and `plymouth`.
  - The install itself is unchanged, and takes as long as before.
- **Image installs boot `linux-cachyos` by default.** The stock Arch kernel
  stays in the boot menu, as the fallback if the CachyOS kernel does not boot.
  On an existing system, `--cachyos-kernel` still leaves the default alone.
- **The closing screen lists only what went wrong.** The GameMode re-login,
  the deferred display setup and the Picom tooltip rule are notes now. None of
  them was a fault.

### The desktop session

- **Restart Quickshell works.** It left no shell at all: the restart ran as a
  child of the shell it stopped, and died with it.
- **Your resolution is kept across logins.** Keep lasted only for the session
  unless you also chose "Use at next login". The kept layout is applied again
  at login, when exactly the same monitors are connected.
- **The wallpaper is redrawn** after a resolution or layout change, instead of
  staying drawn for the old size.

### Settings

- **Settings and System Health open below the panel,** which stays visible,
  instead of fullscreen over it.
  - **A wider effect:** dwm now centers every new floating window in the area
    below the bar. Dialogs open slightly lower and no longer overlap it.
  - **Fullscreen windows are unaffected:** a window that opens fullscreen
    keeps its monitor's full bounds.
- **Settings search finds what each section holds:** "weather", "battery",
  "wifi", "timezone" and others found nothing before.
- **The weather popup asks for a location** when none is set, with a field and
  a Set location button, instead of sending you to Settings.

## Installing from the image

1. Check the image (`docs/src/install.md`), write it to a USB stick, and boot
   it.
2. Run `lyona-install`, answer its questions, and confirm its summary.
3. When it finishes, read its notes, press Enter, and leave the stick in until
   the screen goes dark.

## Upgrading from 2026.10.0-beta.2

- **With `lyona-update`:** this is the first update whose signature beta.2's
  `lyona-update` checks, with `cosign`. Make sure it is installed
  (`sudo pacman -S --needed cosign`); without it, the update is refused.
- **From a checkout:** `git pull`, then `./install.sh`.
- **Your resolution:** choose it once more in Settings and press Keep. Earlier
  choices were not saved for the next login.
- **The CachyOS kernel:** existing installs keep their boot default. To boot
  `linux-cachyos` by default on systemd-boot, run
  `lyona-cachyos install-kernel --make-default linux-cachyos`.

## Qualification status

**Not tested on real hardware.** On the build host (Arch with the CachyOS
repositories, x86_64):
- **The full suite** (`scripts/run-tests`) passed on each branch before it was
  merged.
- **In Xvfb under this release's dwm,** Settings and System Health open below
  the panel.
- **In a throwaway Xvfb session:**
  - Restart Quickshell was checked by its test.
  - The wallpaper redraw ran once after a resolution change, and not at
    startup.

**Not tested yet:**
- **The image,** built by the release workflow and installed in a VM. That is
  the first test of an image with only six packages over `releng`, and of
  `linux-cachyos` booting by default.
- **The resolution kept across a real logout and login,** and the panel staying
  visible in a real session with Settings open.

Two tests are known to fail now and then without a fault: System Health under
Xvfb ("Control Center popup did not open") and the appearance inventory. Both
print what they saw when they fail.
