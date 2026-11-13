# lyona 2026.11.0-beta.1

Ninth beta of the Arch Linux line, and the first release for aarch64. This is
a **pre-release**: the ISO workflow publishes every release with
`--prerelease`, and a beta is never promoted to Latest.

lyona now runs on Arch Linux ARM. This release carries two aarch64 images
beside the x86_64 one:
- a **generic aarch64 install image** for UEFI machines: virtual machines,
  Snapdragon X laptops and other aarch64 machines;
- a **Raspberry Pi image** for the Pi 4 and Pi 5.

`install.sh` also accepts an existing Arch Linux ARM system. The port was
developed in its own repository and merged in #488. Each target's status is
in `SPEC.md` section 4 and under "aarch64 targets" below.

Also in this release:
- the shell's scale follows a high-density panel, so it is no longer tiny
  next to the other apps on a laptop or 4K screen (#481);
- Wi-Fi connected from the panel can roam between a network's access points
  and bands again (#484);
- System Health finds a pacman lock left behind by an interrupted update, and
  removes it (#467);
- updates and rollbacks no longer crash the shell, record the release's
  commit, and remove what a rolled-back release added (#456, #457, #460, #461);
- updates keep your `configure-build.sh` answers without a stale `config.h`
  (#464).

`CHANGELOG.md` has the complete list.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-2026.11.0-beta.1.tar.gz` |
| Installer image, x86_64 | `lyona-2026.11.0-beta.1-x86_64.iso` |
| Installer image, aarch64 (UEFI) | `lyona-2026.11.0-beta.1-aarch64.iso` |
| Raspberry Pi image | `lyona-2026.11.0-beta.1-rpi-aarch64.img.xz` |
| Checksums | `lyona-2026.11.0-beta.1-SHA256SUMS` |
| Signature | `lyona-2026.11.0-beta.1.sigstore.json` |
| Architecture markers | `lyona-2026.11.0-beta.1-architecture-x86_64`, `lyona-2026.11.0-beta.1-architecture-aarch64` |

- **The signature** signs the source archive and all three images. Check an
  image with `cosign` (`docs/src/install.md`).
- **The architecture markers** hold only their architecture's name.
  `lyona-update` reads their names to know which architectures a release
  serves (#53). Every earlier release has
  none and counts as x86_64 only.
- **The installer images** carry `iso_label=LYONA_2026_11_0_BETA1`.
- **All three images are built from the same commit, by one workflow run.**
  The aarch64 images are built natively, in an Arch Linux ARM container on
  GitHub's arm64 runner.

## aarch64 targets

| Target | Image | Status |
| --- | --- | --- |
| QEMU/KVM and libvirt virtual machines on an aarch64 host, UEFI | Generic aarch64 image | Supported |
| Dell XPS 13 9345 (Snapdragon X Elite) | Generic aarch64 image | Supported, no sound |
| Other Snapdragon X laptops with a mainline device tree | Generic aarch64 image | Experimental |
| Other aarch64 UEFI machines | Generic aarch64 image | Experimental |
| Raspberry Pi 4 Model B | Raspberry Pi image | Supported |
| Raspberry Pi 5 | Raspberry Pi image | Experimental |
| An existing Arch Linux ARM system | `install.sh` | Experimental |

NVIDIA GB10 and N1X machines, and 32-bit ARM, are not supported.
`docs/src/install.md` ("Install on ARM (aarch64)") says which image to use
and how to write it. `docs/src/troubleshooting.md` has an ARM section.

What differs on aarch64:
- **Packages:** packages come from Arch Linux ARM's repositories and mirrors.
  CachyOS and the gaming profile are x86_64 only.
- **Booting the generic image:**
  - It boots UEFI only, with Secure Boot off.
  - On a Snapdragon X laptop it picks the device tree at boot: from the
    firmware's DMI table on the XPS 13 9345, otherwise from the tree the
    medium booted with. The installed system keeps that tree, and keeps
    booting after a kernel upgrade.
- **The Raspberry Pi image** is written to an SD card. On first boot, before
  the login screen, a wizard on tty1 grows the root partition to the card,
  then asks for the keyboard, Wi-Fi (when there is no network), the user and
  password, the hostname and the time zone.

## The desktop

- **The interface scale follows the panel (#481).** With no DPI saved, the
  login now derives one from the panel's density: 150 on a 13-inch 2560x1600
  laptop, 125 on a 13-inch 1920x1200 one. An ordinary monitor stays at 96. A
  DPI saved in Settings, or set in your own Xresources, is untouched.
- **Wi-Fi roams again (#484).** Connecting from the panel saved the clicked
  access point's BSSID in the profile. That stopped NetworkManager from
  using the network's other access points or bands, and failed with
  `ssid-not-found` when that one radio stopped answering. See "Upgrading"
  for profiles saved before this release.
- **A stale pacman lock (#467).** A pacman killed mid-update leaves
  `/var/lib/pacman/db.lck`, and every later update fails with "unable to
  lock database". System Health now warns when the lock is older than the
  current boot, and "Remove the stale lock" removes it after polkit asks.
- **Suspend in the power menu** is offered only once logind has said the
  system can suspend. It is not shown at all where it never can, as on a
  Pi 4.
- **The gaming packages** include GOverlay, a window for configuring MangoHud
  (#466).
- **Settings > Input** no longer fails a keyboard-layout preview now and then
  with status 141 (#485).

## Updates

- **The shell survives updates (#461).** Every install, update and rollback
  replaced `~/.config/quickshell` under the running shell, and Quickshell
  0.3.2 often crashed, leaving its crash dialog on the desktop. The new tree
  is now swapped in at once, and the managed shell no longer reloads its own
  files.
- **The runtime check after an update or rollback** checks the restarted
  shell instead of the old one (#460). A correct rollback no longer reports
  "found 2" Quickshell processes.
- **A rollback removes what the release added (#456)**, such as a new
  command. Before, it restored the replaced files but left the new ones.
- **The release's commit** is recorded in `/etc/lyona-release` after an
  update (#457), where it used to read `unknown`.
- **Build answers (#464):** `make install-user` keeps your
  `configure-build.sh` answers in `~/.config/lyona/build.conf`, and each
  update builds that release's own `config.def.h` with them. Before, a
  stale `config.h` copy was kept as if you had customised it.
- **On aarch64,** `lyona-update` only installs a release that lists aarch64.
  This is the first such release.

## Tests

- `check-window-thumb-xvfb` no longer fails now and then on a loaded machine
  (Lyona-ARM #50). The full suite also runs on aarch64, on GitHub's arm64
  runner.

## Upgrading from 2026.10.0-beta.7

- **The update:** use `lyona-update` (or Settings), or from a checkout run
  `git pull` and `./install.sh`. Log out and back in afterwards for the new
  `dwm`.
- **The first update runs beta.7's code, once.** beta.7's helper installs
  this release and beta.7's `lyona-update` checks it.
  `tests/test-update-root-contract.sh` runs the previous release's helper
  against this tree. beta.7's shell still reloads its own files, so this
  release's install stops it before replacing them, and starts it again
  after.
- **No new packages** on x86_64, but for GOverlay in the gaming profile:
  `sudo pacman -S --needed goverlay` if you use it.
- **The interface scale may change.** On a dense panel with no saved DPI,
  the shell now starts at 125 or more. To keep the old size, run
  `dwm-settings-display dpi-set 96` once, or set it in Settings.
- **Wi-Fi profiles saved from the panel before this release** keep their
  pinned access point. Remove the pin with
  `nmcli connection modify NAME 802-11-wireless.bssid ""`. They are not
  changed automatically, because a pin set by hand looks the same.
- **`~/.config/lyona/config.h`:** one that holds only `configure-build.sh`
  answers, as every fresh install's did, becomes `build.conf` on the first
  update. The old file is kept as `config.h.bak.<time>`. A `config.h` you
  edited is kept as before.

## Known issues

- **#386:** a layout change by a plain `xrandr` under Picom may still crash
  Xorg on AMD.
- **#416:** screens can stay black after monitors are powered off and on,
  because light-locker leaves its blanking windows over them.
- **#444:** Settings can miss a wallpaper applied outside it while the
  appearance watch restarts.
- **#447:** the deep dive into intermittent test failures is still open.
- **Dell XPS 13 9345:**
  - no sound;
  - the live image shows a black screen for about 6 s before the installer
    starts;
  - external displays, EL2, suspend and resume, and battery life are not
    covered.
- **Raspberry Pi 4:** Picom stays off at login, because the GPU gives it no
  GL context. The overview shows icon-and-title cards instead of window
  previews.
- **Updates between two aarch64 releases** are not validated yet (#490).

## Qualification status

**Before publication:**
- The full suite (`make check`, every target) passed on GitHub's x86_64 and
  aarch64 runners on the merged tree (run 43485589658, at 711d2a2, which is
  `main` at de77aaa). The changes after it, #491 and this release commit, are
  covered by CI.
- Each aarch64 target marked supported was installed and reached the desktop
  with an image built from the ARM branch. Its evidence is under
  `docs/evidence/`:
  - virtual machines: `arm2-05-generic-image.md`;
  - XPS 13 9345: `arm6-06-xps13-9345.md`;
  - Raspberry Pi 4: `arm3-06-raspberry-pi.md`.
- `install.sh` on Arch Linux ARM: `arm1-06-install-sh.md`, in a KVM virtual
  machine.

**Not tested yet:**
- **This release's own images:** the first build of the aarch64 images by
  the release workflow, on GitHub's arm64 runner, is this release's run.
  None of the three images from this run has been installed yet.
- **Updates on aarch64:** `lyona-update` against real releases (#490).
- **x86_64 hardware:** real hardware, AMD included (#386), NVIDIA and the
  legacy NVIDIA drivers, Wi-Fi installs, and two physical outputs.
- **aarch64:** everything marked experimental above.
