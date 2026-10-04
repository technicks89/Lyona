# lyona 2026.10.0-beta.2

Third beta of the Arch Linux line, and the first **signed** release. This is a
**pre-release**: the ISO workflow publishes every release with `--prerelease`,
and a beta is never promoted to Latest.

It fixes what the 2026-10-03 whole-repo review found (Sync Sprint 16,
`docs/sprints/SYNC-SPRINT-16-REVIEW-FIXES.md`), and why the `2026.10.0-beta.1`
image never reached a desktop. `CHANGELOG.md` has the complete list.

## Artifacts

| Artifact | Name |
| --- | --- |
| Source archive | `lyona-2026.10.0-beta.2.tar.gz` |
| Installer image | `lyona-2026.10.0-beta.2-x86_64.iso` |
| Checksums | `lyona-2026.10.0-beta.2-SHA256SUMS` |
| Signature | `lyona-2026.10.0-beta.2.sigstore.json` |

- **The signature** signs the source archive and the image. The release
  workflow made it through Sigstore, with no key to keep, before it published
  anything. Check the image with `cosign` (`docs/src/install.md`).
- **The installer image** carries `iso_label=LYONA_2026_10_0_BETA2`.

## What is in this beta

### Signed releases

- **`lyona-update` checks each release's signature** with `cosign` before it
  unpacks it (decision D-31). A release whose signature is missing, or not
  made by lyona's own release workflow on `main`, is refused.
- **Offline installs:** `apply --file` downloads the signature, or takes it
  with `--bundle FILE`. With no network, `--sha256` installs on the checksum
  you give, and says the signature was not checked.

### The image installs to a desktop

The `2026.10.0-beta.1` image installed, then failed at the login screen.
Installing it in a VM found that and six more faults, all fixed:
- the LightDM config was deployed before the tool it needs was built;
- the `yay` build hung on a question nothing could answer;
- the image's scripts lost their executable bit;
- the first package update failed before the CachyOS key was trusted;
- the gaming packages failed on a Vulkan driver conflict (`mesa-git`);
- Gear Lever failed inside the installer, and now installs at first login.

The wizard also:
- **asks yes or no** about the timezone it detected, else lets you search the
  list;
- **gives root no password,** and locks it; you administer with `sudo`;
- **lists anything that did not go as chosen** on its last screen, and keeps
  the log on the new system.

### Keys

- **Super+Shift+Q** (log out) and **Super+Ctrl+Shift+R** (reboot) now ask
  first, in the power menu. Quitting dwm at once moved to
  **Super+Ctrl+Shift+Q**.
- New installs only: an existing `hotkeys.toml` keeps its keys.

### Less idle work

- **One window watcher:** the shell follows every window through one new
  helper, `dwm-xwatch`, instead of one process per window.
- **Window previews** fetch an image in a few round trips, not hundreds.
- **Several watchers** stop polling or back off.

## Installing from the image

1. Check the image (`docs/src/install.md`), write it to a USB stick, and boot
   it.
2. Run `lyona-install`, answer its questions, and confirm its summary.
3. When it finishes, read its notes, press Enter, and leave the stick in until
   the screen goes dark.

## Upgrading from 2026.10.0-beta.1

- **From the image:** an install of the `beta.1` image never reached a working
  login. Install this image afresh.
- **On an existing system:** from a checkout, `git pull`, then `./install.sh`.
  It installs `cosign`.
- **With `lyona-update`:** the `beta.1` `lyona-update` does not check
  signatures, and has not been tested updating to this release. If you use it,
  install `cosign` afterwards (`sudo pacman -S --needed cosign`), or the next
  update is refused.
- **The new keys** reach an existing `hotkeys.toml` only if you copy them from
  `/usr/local/share/lyona/config/hotkeys.toml`.

## Qualification status

**Not tested on real hardware.** Tested in a QEMU/KVM virtual machine with
UEFI (OVMF), a standard VGA adapter and no NVIDIA GPU, from images built on the
build host (Arch, CachyOS repositories):
- **Three installs**, each finding the faults fixed before the next. The last
  completed with no help to a working desktop: LightDM, dwm, the managed
  shell, the launcher, the power menu's confirmations, `yay` and Topgrade.
- **Gear Lever's install at first login** was checked on that system. The
  change that sends an image install there was made after that image, so it
  is tested only by the suite.
- **The signature check** was run against a real Sigstore bundle: the right
  file verified, and a tampered file, another workflow or another repository
  was refused. No lyona release had been signed yet, so the release
  workflow's signing step is untested until this release is published.

**The full suite** (`scripts/run-tests`) passed. Two tests are known to fail
now and then without a fault: Settings responsiveness and System Health under
Xvfb.
