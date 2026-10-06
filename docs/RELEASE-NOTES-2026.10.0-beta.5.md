# lyona 2026.10.0-beta.5

Sixth beta of the Arch Linux line. This is a **pre-release**: the ISO
workflow publishes every release with `--prerelease`, and a beta is never
promoted to Latest.

The install image now offers Wi-Fi when there is no wired connection (#237),
installs Firefox as the default browser (#240), and goes straight from the
boot splash to the installer. The GRUB menu no longer lists every firmware
boot entry (#239), and Topgrade can update what cargo installed (#238).
`CHANGELOG.md` has the complete list.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-2026.10.0-beta.5.tar.gz` |
| Installer image | `lyona-2026.10.0-beta.5-x86_64.iso` |
| Checksums | `lyona-2026.10.0-beta.5-SHA256SUMS` |
| Signature | `lyona-2026.10.0-beta.5.sigstore.json` |

- **The signature** signs the source archive and the image. Check the image
  with `cosign` (`docs/src/install.md`).
- **The installer image** carries `iso_label=LYONA_2026_10_0_BETA5`.

## What is in this beta

### Wi-Fi in the installer (#237)

- **The wizard offers Wi-Fi** when there is no wired connection and the
  machine has a Wi-Fi card: **Connect to Wi-Fi**, **Retry**, or **Continue
  without internet**. Before, the only way was to drop to a shell and run
  `iwctl`.
- **Networks are listed** strongest first, with signal strength and security,
  plus **Other (hidden network)**.
  - **Supported:** open and WPA personal networks.
  - **Not supported:** enterprise (802.1X) and WEP networks. They are listed,
    and choosing one says why it can't be used.
- **A wrong passphrase** says so and shows the list again.
- **The passphrase stays private.** It is written only to iwd's own profile,
  readable by root only. It never appears on a command line or in the install
  logs.
- **The new system stays online.** It gets a NetworkManager profile for the
  same network, so its first boot is connected.
- **A Wi-Fi chip with no driver on the image** is named. Some Broadcom chips,
  such as those in older Macs, need `broadcom-wl`, which the image doesn't
  carry; install over a cable or USB tethering from a phone instead.

### Straight from the splash to the installer

- **No root console flashes by.** Before, tty1 showed the login banner, an
  automatic-login line and the Arch install guide text for a moment between
  the splash and the installer.
- **The first screen appears at once.** The installer draws its logo before
  it checks the network. That check used to leave the console blank for a few
  seconds when offline.
- **The Arch install guide text** still appears on other consoles, such as
  tty2.

### Firefox (#240)

- **Firefox is installed** in the recommended and full profiles, image
  installs included. Before, SUPER+B had no browser to open.
- **A new account gets it as the default browser,** for web links and HTML
  pages only. Images, audio and video stay with sxiv and Celluloid.
- **An existing system keeps its browser.** When the default browser is
  another one that is installed, Firefox is not added.

### GRUB menu (#239)

- **No more "(EFI BootNext)" entries.** GRUB 2.16 added a top-level entry for
  every firmware boot entry, such as the firmware's own boot manager and a DVD
  drive. The menu is now **Arch Linux**, **Advanced options for Arch Linux**
  and **UEFI Firmware Settings**.
- **How:** `lyona-grub-theme apply`, which the installers run, writes
  `GRUB_DISABLE_BOOTNEXT=true` to `/etc/default/grub.d/90-lyona-menu.cfg`.
  `/etc/default/grub` is not edited for it.
  - **`lyona-grub-theme remove`** deletes that file.
  - **Your own `GRUB_DISABLE_BOOTNEXT`** in `/etc/default/grub` is kept, and
    a file at that path that isn't lyona's is never replaced.

### Topgrade updates cargo packages (#238)

- **cargo-update is installed** beside rustup, from Arch's `extra`
  repository. Topgrade's Cargo step needs it, and skipped that step without
  it, so nothing installed with `cargo install`, Topgrade included, was ever
  updated.
- **Beside a `cargo` from rustup.rs,** which no package provides, it is left
  out: pacman would add a second Rust toolchain. Run
  `cargo install cargo-update` there instead.

## Installing from the image

1. Check the image (`docs/src/install.md`), write it to a USB stick, and boot
   it, with UEFI or a legacy BIOS.
   - **On a Mac,** hold Option at startup and choose **EFI Boot**.
2. The installer starts on its own. Without a wired connection, choose
   **Connect to Wi-Fi**. Then answer its questions and confirm its summary.
3. When it finishes, read its notes, press Enter, and leave the stick in until
   the screen goes dark.

## Upgrading from 2026.10.0-beta.4

- **With `lyona-update`,** or from a checkout with `git pull` and
  `./install.sh`, as for beta.4.
- **Firefox and cargo-update** are installed by `./install.sh` with the
  recommended and full profiles.
- **Existing installs that boot with GRUB** lose the "(EFI BootNext)" entries
  when `./install.sh` runs `lyona-grub-theme apply`, or with
  `sudo lyona-grub-theme apply CyberRe`.
- **The Wi-Fi and splash changes** are in the install image only.

## Qualification status

**Not tested on real hardware, and not yet installed from a beta.5 image.**
On the build host (Arch with the CachyOS repositories, x86_64):
- **The full suite** (`scripts/run-tests`) passed on the Wi-Fi, Firefox,
  cargo-update and GRUB changes (#241).
- **The Wi-Fi step** was tested against a stand-in for iwd. Emulated Wi-Fi
  isn't practical in QEMU, so it needs a Wi-Fi-only machine.
- **The splash handoff** was checked in the staged image profile only. It
  needs a boot to confirm nothing shows between the splash and the
  installer.

**Not tested yet:**
- **A Wi-Fi install** on real hardware, including a hidden network and the
  first boot's connection.
- **The GRUB menu** on a UEFI install from this image.
- **Real hardware,** LUKS on legacy BIOS, ext4, and the NVIDIA drivers under
  GRUB.

Two tests are known to fail now and then without a fault: System Health under
Xvfb ("Control Center popup did not open") and the appearance inventory. Both
print what they saw when they fail.
