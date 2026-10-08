# lyona 2026.10.0-beta.5

Sixth beta of the Arch Linux line, and the first since beta.4. This is a
**pre-release**: the ISO workflow publishes every release with `--prerelease`,
and a beta is never promoted to Latest.

It fixes three security issues in lyona's update path and root helpers. The
install image now:
- connects to Wi-Fi;
- uses your keyboard layout for the passwords;
- lets you change an answer or retry a failed base install;
- downloads from mirrors near you.

Installs are faster, and the install image goes straight from the boot splash
to the installer. On the desktop, AppImages open without Gear Lever's
runtimes, peripheral batteries are shown, Picom is part of the desktop, time
sync is on, and Firefox is the default browser. Running `install.sh` again
keeps your `~/.bashrc` and your time settings. `CHANGELOG.md` has the complete
list.

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

## Security

Three advisories, published with this release:

- **GHSA-x538-46gg-v37h: the update helper verifies signatures itself.**
  - **Before:** `lyona-update` checked a release's signature as you, but its
    root helper installed any tarball whose checksum the caller passed, behind
    the routine "install a lyona system update" prompt.
  - **Now:** the helper checks the signature on its own copy, against lyona's
    release workflow, which is fixed in the helper.
  - **Unsigned installs:** a release from before signing, or an offline
    `--sha256` file, asks through a different prompt that says the signature
    was NOT verified.
- **GHSA-xfhv-7h9c-m966: release signing has its own job.**
  - **Before:** the job that builds the image held the signing token.
  - **Now:** a separate job, which runs none of the repository's code, signs
    what the build made. The build container is pinned by digest.
- **GHSA-c897-2mjw-fwhh: the root helpers stay out of your files.**
  - **The display helper** runs as root with root's own `HOME`, and gets a
    root-owned copy of your X authority, read with your permissions.
  - **The System Health helper** checks every library its tool loads before
    running it as root.

**The update-helper fix takes effect from the update after this one.**
Upgrading from beta.4 to beta.5 still runs beta.4's helper, once.

## The install image

### Wi-Fi (#237)

- **The wizard offers Wi-Fi** when there is no wired connection and the
  machine has a Wi-Fi card: **Connect to Wi-Fi**, **Retry**, or **Continue
  without internet**.
- **Networks are listed** strongest first, with signal strength and security,
  plus **Other (hidden network)**. Open and WPA personal networks are
  supported; enterprise (802.1X) and WEP are listed with the reason they
  can't be used.
- **The passphrase stays private.** It goes only into iwd's own profile, never
  onto a command line or into the install logs.
- **The new system stays online:** it gets a NetworkManager profile for the
  same network.
- **A chip with no driver on the image is named.** Some Broadcom chips need
  `broadcom-wl`; install over a cable or USB tethering instead.

### Keyboard layout and passwords (#265)

- **The layout applies at once.** Before, the disk-encryption and user
  passwords were typed in a US layout, and the same keys then gave other
  characters at the LUKS prompt and at login. On a French or German keyboard,
  the disk would not unlock.
- **The password prompts name the layout** ("Password (keyboard: fr):").
- **The list is searchable,** with names for the common layouts, then every
  console keymap. Swedish, Turkish and Slovenian now use real keymaps
  (`sv-latin1`, `trq`, `slovene`); before, they were listed as names that
  aren't keymaps.

### Going back, and recovering (#266)

- **Change an answer:** the summary can change any one answer instead of
  cancelling. A new keyboard layout asks for the passwords again.
- **Cancel comes first** on the summary, so Enter alone never wipes the disk.
- **Esc goes back** in the timezone and country lists, instead of ending the
  installer.
- **A failed `archinstall`** shows the recovery menu (Retry, View full log,
  Exit to shell), with what state the disk is in. **Retry** runs it again with
  your answers.
- **The passwords file for `archinstall`** is removed however the run ends.

### Faster installs (#245-#250)

- **Mirrors near you:** the installer asks to use your timezone's country, or
  another, and ranks those mirrors by speed before downloading. It downloads
  10 packages at a time, up from 5.
- **One kernel and one initramfs:** `linux-cachyos`, installed by
  `archinstall`. There is no fallback image, and `grub-mkconfig` runs once.
  `docs/src/install.md` shows how to add `linux-cachyos-lts` or the fallback
  image back.
- **One pacman transaction** for every package, the gaming ones included.
- **Topgrade** comes from the AUR's `topgrade-bin`, in seconds instead of a
  multi-minute cargo build. No Rust toolchain is installed for it.
- **The MesloLGS Nerd Font** comes from the repositories (5.7 MiB) instead of
  a 112 MB download.
- **Both installers time each step,** and the image install's log ends with a
  table of where the time went.

### Straight from the splash to the installer

The root console no longer flashes by between the splash and the installer,
and the first screen appears before the network check.

## The desktop

### AppImages without Gear Lever's runtimes (#260)

- **The first open asks.** Opening an AppImage (from Thunar, or the browser's
  downloads) asks **Add and run**, **Add only** or **Cancel**, with where it
  was downloaded from. Closing the question cancels, and nothing is moved.
- **Adding** moves the file to `~/Applications` and puts it in the launcher,
  with its own name and icon, read from inside it, never by running it.
- **Opening it again** just starts it.
- **`fuse2` and `squashfs-tools`** come with the recommended desktop, so
  classic AppImages run.
- **Gear Lever** (about 1.7 GB of Flatpak runtimes) is opt-in with
  `install.sh --with-gearlever`. An installed Gear Lever is kept.

### Notifications with buttons (#260)

A notification that comes with buttons shows them, up to three, and stays
until one is pressed or it is closed.

### Peripheral batteries (#243)

- **Settings > Power** lists the batteries of wireless mice, keyboards,
  headsets and controllers that UPower reports, and so does the Control
  Center's power page.
- **A coarse level shows as a word.** A device that reports only "Full" or
  "Low" shows that word, not a made-up percentage.
- **Below 15%,** a peripheral sends one notification.

### Picom is part of the desktop (#244)

- **Required for previews:** the overview's window previews need Picom, so the
  recommended and full profiles require it.
- **Lean default configuration:** no shadows, fading, blur or animations.
- **Backend:** the backend is chosen for your graphics card.
- **When Picom can't start,** the desktop still starts and says why once.

### Time sync, Firefox and GRUB

- **Time sync is on.** `install.sh` turns on `systemd-timesyncd` when nothing
  else keeps the clock. If you turn it off later, it stays off: running the
  installer again no longer turns it back on (#258, #268).
- **Firefox** is installed in the recommended and full profiles, and a new
  account gets it as the default browser (#240).
- **The GRUB menu** no longer lists every firmware boot entry (#239).

### Fixed

- **Running `install.sh` again no longer throws away your `~/.bashrc`
  edits.** It updated the mybash checkout, which those files link into, by
  deleting it. Now it updates the checkout in place and leaves it alone if you
  changed it (#267).
- **An install no longer fails** when the CachyOS repositories are part way
  through a Qt update.

## Installing from the image

1. Check the image (`docs/src/install.md`), write it to a USB stick, and boot
   it, with UEFI or a legacy BIOS.
   - **On a Mac,** hold Option at startup and choose **EFI Boot**.
2. The installer starts on its own. Without a wired connection, choose
   **Connect to Wi-Fi**. Choose your keyboard layout first; the passwords are
   typed with it.
3. Answer the questions. Use **Change an answer...** on the summary if
   needed, then confirm.
4. When it finishes, read its notes, press Enter, and leave the stick in until
   the screen goes dark.

## Upgrading from 2026.10.0-beta.4

- **The update:** with `lyona-update` (or Settings), or from a checkout with
  `git pull` and `./install.sh`.
- **After `lyona-update`,** also run `./install.sh` from a checkout, or install
  the new packages yourself. `lyona-update` installs lyona's own files, not
  new packages, and doesn't change per-user defaults:
  - `fuse2` and `squashfs-tools`, and the AppImage handler:
    `sudo pacman -S --needed fuse2 squashfs-tools`, then
    `xdg-mime default lyona-appimage.desktop application/vnd.appimage`;
  - Firefox, and Topgrade from `topgrade-bin`;
  - time sync.
- **Picom** now ships its own lean configuration, used when you have none of
  your own. To keep the package's shadows and fading, copy
  `/etc/xdg/picom.conf` to `~/.config/picom/picom.conf`.
- **Topgrade built with cargo** stays in `~/.cargo/bin` until you remove it;
  `install-topgrade` offers to.
- **Kernels:** existing installs keep their kernels and fallback images.
- **The Wi-Fi, keyboard, recovery and mirror changes** are in the install
  image only.

## Qualification status

**Not tested on real hardware.** On the build host (Arch with the CachyOS
repositories, x86_64):
- **The full suite** (`scripts/run-tests`) passed on `main` with all of this
  release's changes, the three security fixes included.
- **The root-helper tests** (update, display, System Health) passed as root in
  a disposable container, with a real `cosign`.
- **GitHub checks:** CodeQL and the desktop smoke test passed on the security
  PRs.

**In a VM** (QEMU/KVM, UEFI, standard VGA, no NVIDIA), from an image built
before the security fixes:
- **Keyboard (#265):** with French chosen, LUKS-encrypted btrfs, the same keys
  unlocked the disk at boot and logged in at LightDM, to the desktop.
- **Recovery and navigation (#266):** Esc in the lists, Change an answer, and
  Retry after `archinstall` was killed mid-install all worked.
- **The install timing work** was measured in VM installs
  (`docs/evidence/250-install-step-timing.md`).
- **AppImages** were tested in a VM install and in a nested X session
  (`docs/evidence/260-appimages.md`).

**Not tested yet:**
- **A real release run of the new signing workflow.** This release is the
  first. If the sign or release job fails, nothing is published.
- **The security fixes in an installed system:** an update from this release
  showing the two different prompts, and a display change through Settings
  with the copied X authority.
- **Hardware and paths:** a Wi-Fi install on real hardware, legacy BIOS, ext4,
  NVIDIA, and layouts other than French in a VM.

Three tests are known to fail now and then without a fault: System Health
under Xvfb ("Control Center popup did not open"), the appearance inventory,
and the Quickshell idle-watchers measurement, which can read just over its
0.5% limit on a busy machine.
