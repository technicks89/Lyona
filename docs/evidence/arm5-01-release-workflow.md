# ARM5-01: the release workflow for ARM images

ARM Sprint 5 item ARM5-01 (Lyona-ARM issue #18, then Lyona #489). Written
2026-11-12; the release run in Lyona, 2026-11-13, is under "The release run"
below. Per the amendment of
2026-10-27 (`docs/sprints/ARM64.md`, End state), this is the part that belongs
in Lyona-ARM: the workflow and `scripts/lyona-release`, checked with stubs. The
release run itself, and the acceptance (a pre-release with the x86_64, generic
aarch64 and Pi images, each checksummed and signed), happens in Lyona after the
merge.

## What changed

- `.github/workflows/build-iso.yml` is still one workflow with one run per
  release, so the x86_64 and aarch64 images come from the same commit, and the
  release is made only when every image built:
  - `build-iso` is unchanged (the x86_64 ISO, the version and tag check, the
    release archive check).
  - `build-aarch64-iso` and `build-rpi-image` run on `ubuntu-24.04-arm`, after
    `build-iso` (so a bad version fails before an hour of building), with a
    read-only token, no environment and no secret. Each builds the Arch Linux
    ARM container image (`scripts/ci-archlinuxarm-image.sh`, signature and
    checksum checked) and runs `scripts/ci-release-aarch64.sh iso|rpi` in it,
    privileged, with the checkout mounted.
  - `sign` attests the source archive and all three images, still the only job
    with the OIDC token and still running no repository code.
  - `release` needs all three builds and `sign`, and passes the aarch64 ISO and
    the Pi image to `scripts/lyona-release` with `--asset`, and
    `--architecture x86_64 --architecture aarch64`.
- `scripts/ci-release-aarch64.sh`: builds one image in the container. The ISO
  needs archiso 91, which Arch Linux ARM does not package, so it clones
  archiso and checks out the commit `v91` points at
  (`723da192226e1c9d5def9168f13332793c82a85e`), and refuses any other. It
  leaves one file in the output directory.
- `scripts/lyona-release`: `--asset PATH` (repeatable) uploads another image,
  checksummed in `SHA256SUMS` and, with `--bundle`, required to be signed;
  `--architecture ARCH` (repeatable, `x86_64` or `aarch64`) adds the asset
  `lyona-VERSION-architecture-ARCH`, unsigned and not in `SHA256SUMS`.
  `lyona-update` reads only those markers' names (#53,
  `docs/src/updating.md`). Each was an empty file until #494; each now holds
  its architecture's name, because GitHub refuses an empty upload (see "The
  release run").
- Names, as `scripts/build-lyona-arch-iso.sh` and `scripts/build-lyona-rpi-image.sh`
  already make them: `lyona-VERSION-x86_64.iso`, `lyona-VERSION-aarch64.iso`,
  `lyona-VERSION-rpi-aarch64.img.xz`.

## Checks

- `tests/test-release-helper.sh`: the extra images are published, checksummed
  and checked against the bundle (a bundle that leaves out the Pi image is
  refused with nothing uploaded); the markers hold their architecture's name,
  are published, and are not in `SHA256SUMS`; a missing image and an unknown architecture are refused; no
  `--architecture` makes no marker.
- `tests/test-release-workflows.sh` (needs PyYAML): the six jobs; the aarch64
  jobs run on the arm64 runner after `build-iso` with a read-only token, no
  environment and no secret; `sign` and `release` need every build; no job or
  step can be skipped or fail silently; the sign step's subjects include each
  image; the release step's `lyona-release` arguments; the release step refuses
  to run when either aarch64 image is missing. ShellCheck on every step script.
- ShellCheck on `scripts/ci-release-aarch64.sh` and `scripts/lyona-release`:
  clean. `shfmt` was not available on this machine; the Full suite's format
  check covers it.

## The release run (in Lyona, 2026-11-13)

`v2026.11.0-beta.1` was published as a pre-release on 2026-11-13 at 23:21 UTC:
https://github.com/technicks89/Lyona/releases/tag/v2026.11.0-beta.1. The third
run made it; the first two found two faults, both fixed before it.

| Run | Commit | Result |
| --- | --- | --- |
| [43505662704](https://github.com/technicks89/Lyona/actions/runs/43505662704) | 3104f16 (#492) | x86_64 ISO built; both aarch64 jobs failed in seconds: `scripts/ci-release-aarch64.sh` ran `git config` before its `pacman` installed git (`git: command not found`). Nothing published. Fixed in #493, with `tests/test-ci-release-aarch64.sh` |
| [43518050560](https://github.com/technicks89/Lyona/actions/runs/43518050560) | 0b044a4 (#493) | All three images built and were signed; `release` made the tag, then GitHub refused the first architecture marker, an empty file (`HTTP 400: Bad Content-Length`). `gh` removed its draft release; the tag, with no release, was deleted by hand. Fixed in #494: each marker holds its architecture's name |
| [43523332090](https://github.com/technicks89/Lyona/actions/runs/43523332090) | db24732 (#494) | Published |

The published run, all on GitHub's hosted runners (runner image 20261103.629):

| Job | Runner and container | Time |
| --- | --- | --- |
| `build-iso` | `ubuntu-latest` (x86_64), `archlinux:base-devel@sha256:996c3a1d...` | 22:56 to 23:07 (11 min) |
| `build-aarch64-iso` | `ubuntu-24.04-arm`, Arch Linux ARM container from `ArchLinuxARM-aarch64-latest.tar.gz` (signed by `68B3537F39A313B3E574D06777193F152BDBE6A6` on 2026-08-05, SHA-256 `42a4eeaa...`), archiso at `v91` (`723da192`) | 23:08 to 23:17 (9 min) |
| `build-rpi-image` | `ubuntu-24.04-arm`, the same container | 23:08 to 23:18 (10 min) |
| `sign` | `ubuntu-latest` | 23:18 to 23:19 |
| `release` | `ubuntu-latest` | 23:19 to 23:21 |

The Pi image took 10 minutes here against 1 h 29 min on the Pi 4, and neither
aarch64 job ran short of disk; the questions this file left open are
answered.

The release's assets:

| Asset | Bytes | SHA-256 |
| --- | --- | --- |
| `lyona-2026.11.0-beta.1.tar.gz` | 6,595,883 | `20efa2ef96036a8047237078b8a24042dc3df5b338b15690821ee4899a84d088` |
| `lyona-2026.11.0-beta.1-x86_64.iso` | 1,339,965,440 | `9d939847deaa6a5fd7ad394789b70b6f2c5cf67a4163f5f3cb4566f90ae139c3` |
| `lyona-2026.11.0-beta.1-aarch64.iso` | 973,287,424 | `82baf4a2b9b8053526bf0f37abe791aac1a193576efd41554d85baa329cfde91` |
| `lyona-2026.11.0-beta.1-rpi-aarch64.img.xz` | 857,759,340 | `1d051caf5fb586787a7306c8c89c101eb5e72d72d6ad900cba0e4b0718c1cf00` |
| `lyona-2026.11.0-beta.1-SHA256SUMS` | 405 | the four lines above |
| `lyona-2026.11.0-beta.1.sigstore.json` | 11,238 | the signature |
| `lyona-2026.11.0-beta.1-architecture-x86_64` | 7 | holds `x86_64` |
| `lyona-2026.11.0-beta.1-architecture-aarch64` | 8 | holds `aarch64` |

Checked after publication, from the downloaded assets:

- `SHA256SUMS` lists the source archive and the three images; the source
  archive matches it.
- The signature bundle's subjects are the same four files with the same
  digests, and `cosign verify-blob-attestation` with the identity
  `lyona-update` uses (`build-iso.yml` on `main`, GitHub's OIDC issuer)
  prints "Verified OK" for the source archive.
- The tag points at db24732, and the archive's `.lyona-commit` names the same
  commit.
- Both markers are published, hold their architecture's name, and are not in
  `SHA256SUMS`.
- The release is a pre-release, not a draft.

## lyona-update against this release (2026-11-14)

### Real updates

A real `lyona-update apply`, with the privileged install, updated an existing
install to 2026.11.0-beta.1 on both architectures:

- x86_64: the maintainer's CachyOS desktop (`uname -m` x86_64). Its
  `update.log` shows the run start at 13:24:38Z. It downloaded the archive,
  matched the checksum, verified the signature and built the release, then
  asked first. It backed up the live install (backup
  `20261114T132448Z-8938`, holding `system-files.tar`, `quickshell.tar`,
  `install.state`, `checkout.txt` and `SHA256SUMS`) and installed with
  authentication. "All managed files match the checkout", Quickshell
  restarted, and the run ended `complete apply 2026.11.0-beta.1`.
  `update.status` reads `outcome succeeded` (13:25:05Z), and
  `/etc/lyona-release` records `LYONA_VERSION=2026.11.0-beta.1`,
  `LYONA_COMMIT=db247325...` and `LYONA_SOURCE=tarball`.
- aarch64: the Snapdragon X laptop (Dell XPS 13 9345). The maintainer
  reports that the update passed there too. The laptop was reinstalled
  fresh afterwards (below), so its update log no longer exists.

### Checks against the live API

Run from this branch's `scripts/lyona-update` (the same as the release's), on
an x86_64 CachyOS host, against the live GitHub API. Each run had its own
`HOME` and XDG directories, a stub `lyona-version` reporting an install of
2026.10.0-beta.7 with release provenance, and `LYONA_UPDATE_ARCH` set to the
architecture under test. The aarch64 runs are that override on an x86_64
host, not an Arch Linux ARM machine.

| Command | x86_64 | aarch64 |
| --- | --- | --- |
| `check --channel stable --json` | `unknown`: nothing on stable, with the hint to run `set-channel preview` | `unknown`: "No aarch64 release has been published on the stable channel yet", with the same hint |
| `check --channel preview --json` | `behind`, offered 2026.11.0-beta.1 (commit db24732, checksum `20efa2ef...`, 6,595,883 bytes) | the same |
| `apply --dry-run` (channel seeded `preview`, since the installed version is a pre-release) | downloaded, checksum matched, `cosign` "Verified OK", unpacked, build passed, plan printed, `complete apply-dry-run` | the same; the archive passed the aarch64 check (`archarm` is in its `dwm-utils.sh`) |

The first aarch64 dry run stopped at "could not reach the update server": one
request for the release list failed. The rerun passed. Four timed requests
for the same list took about 0.13 s each (113,391 bytes), so the 15 s limit
was not the cause. The fault was transient and needs no code change.

`scripts/run-tests bash tests/test-lyona-update.sh`,
`make check-update-root-contract` and `make check-release-helper` pass.

These checks came on top of the real updates above. A fresh install from
this release's images records 2026.11.0-beta.1, the newest release, so
`check` reports it current until a newer pre-release is published.

## Fresh installs from this release's images (2026-11-14)

### x86_64 ISO in a QEMU/KVM VM

Run and reported by a Claude Code session on the maintainer's second machine
(an AMD Ryzen 5 3600 host running CachyOS). The VM is still available there
to check again.

- Image: the published `lyona-2026.11.0-beta.1-x86_64.iso`. Its SHA-256,
  `9d939847...ae139c3`, matches the release's `SHA256SUMS`.
  `/etc/lyona-iso-release` records version 2026.11.0-beta.1, commit db247325,
  and a build date of 2026-11-13T22:57:30Z.
- VM: plain `qemu-system-x86_64` (q35, KVM, `-cpu host`), with 4 vCPUs,
  4 GiB of RAM, a 40G virtio qcow2 disk and user-mode virtio-net. UEFI
  firmware (OVMF `OVMF_CODE.4m.fd`). QEMU std VGA (`bochs-drm`, 1280x800), so
  no NVIDIA GPU, and the wizard said the driver was not needed. The live
  medium started by direct kernel boot of the ISO's own kernel and initramfs,
  not through the ISO's UEFI menu. The installed system booted from the disk
  through its own GRUB.
- Install: the gum wizard, with keymap us, btrfs without LUKS and UEFI GRUB.
  The answers were changed once at the summary, for the tester's own timezone
  keystroke slip; the mirrors and Wi-Fi country then followed the corrected
  timezone. It took about 11 minutes from "Wipe and install" to the greeter.
  The postinstall steps took 3m12s.
- First boot: GRUB, then the LightDM slick-greeter, then the dwm and
  Quickshell desktop, with Picom and xsettingsd running. `systemctl --failed`
  listed nothing. The only `err` lines in the journal were the harmless TDX
  and `gkr-pam` messages. CachyOS kernel 7.3.4-1-cachyos and its
  repositories. `/etc/lyona-release` records
  `LYONA_VERSION=2026.11.0-beta.1`, `LYONA_COMMIT=db247325...` and
  `LYONA_SOURCE=iso`.
- Desktop checks: the 48-check battery from the beta.7 qualification passed
  48/48. It covers:
  - session processes and EWMH
  - layouts, focus and tags
  - the launcher, overview, control center, keybinds and power menu
  - Settings, with all 9 sections ready
  - hot reload of the three TOML files
  - SIGUSR1, killclient, and idle CPU
- Logout and login: 3/3 cycles came back to a working session.
- Settings > System shows 2026.11.0-beta.1 on the preview channel.
- `lyona-update check` exited 0: `state current`, installed and available
  both 2026.11.0-beta.1 with the same archive checksum. `apply` was not run,
  because nothing newer is published.
- The postinstall pacman log has mirror noise only: cdn77.cachyos.org
  returned 404 for some x86_64_v3 packages, and pacman fell back to another
  mirror.
- To run the checks over SSH, the tester added openssh, a key and a
  passwordless sudo rule after the first login. These were part of the test
  harness, not lyona.

### aarch64 ISO on the Dell XPS 13 9345 (Snapdragon X)

The maintainer installed it. Its state was read over SSH from this branch's
machine on 2026-11-14, eleven minutes after a boot.

- Image: the published `lyona-2026.11.0-beta.1-aarch64.iso`.
  `/etc/lyona-iso-release` records version 2026.11.0-beta.1, commit db247325,
  and a build date of 2026-11-13T23:09:38Z, from the aarch64 job of the
  release run.
- System: Arch Linux ARM (`ID=archarm`, `uname -m` aarch64). The device tree
  model is "Dell XPS 13 9345". Kernel `linux-aarch64` 7.3.4-1, booted by UEFI.
  btrfs on the NVMe disk (512M vfat ESP), with zram swap. The kernel command
  line carries the Snapdragon X arguments (`efi=noruntime clk_ignore_unused
  pd_ignore_unused arm64.nopauth cma=128M`, among others).
- `/etc/lyona-release` records `LYONA_VERSION=2026.11.0-beta.1`,
  `LYONA_COMMIT=db247325...`, `LYONA_SOURCE=iso` and
  `LYONA_INSTALL_DATE=2026-11-14T13:33:57Z`.
- Boot: `graphical.target` was reached 3.9 s after the kernel started
  (1.1 s kernel, 2.8 s userspace). `systemctl --failed` listed nothing.
  LightDM, dwm, Quickshell (the managed `shell.qml`, `--no-duplicate`), the
  network monitor and Picom (`--backend xrender`) were running, all near
  idle at 0.0% CPU. The display is `msm_dpu` with the internal eDP panel
  connected at 2560x1600, plus two DP connectors.
- `err` lines in the journal: Qualcomm firmware and driver messages at
  probe. These were pmic-glink device links, fastrpc and qrtr endpoints
  (error -12), a qcom-apm command timeout and a missing `dmic-sample-rate`
  device-tree entry, plus wpa_supplicant's nl80211 multicast note and
  `gkr-pam`. They are as recorded for this laptop in `arm6-06-xps13-9345.md`
  (not re-compared line by line). The journal's timestamps for this boot
  read Nov 13 01:55, before the clock was set (`efi=noruntime` leaves no EFI
  real-time clock); the clock was correct by the time of the reading.
- `lyona-update check` exited 0: `state current`, installed and available
  both 2026.11.0-beta.1 (db24732), with archive checksum `20efa2ef...`, on
  the preview channel that a pre-release install starts on. The install has
  no update log and no backups: no `apply` has run on it.
- Not checked on this install: the desktop checks run on the x86_64 VM, Wi-Fi
  and Bluetooth use, audio, suspend, external monitors, the battery and the
  ISO's checksum (the downloaded file was not on the laptop).

## Not tested

- The x86_64 ISO has been installed only in a QEMU/KVM VM with UEFI. Not
  tested on it: real hardware, BIOS boot, the ISO's own UEFI boot menu, LUKS,
  ext4, NVIDIA or other GPUs, Wi-Fi, Bluetooth, audio, suspend, multiple
  monitors and the online timezone lookup.
- The aarch64 ISO was installed only on the XPS 13 9345, and only its boot
  and install state were read (above). Nothing records an install of the
  Raspberry Pi image, or of the generic aarch64 ISO on its VM targets. Each supported aarch64
  target's earlier validation used an image built from the ARM branch
  (`docs/evidence/arm2-05-generic-image.md`, `arm6-06-xps13-9345.md`,
  `arm3-06-raspberry-pi.md`).
- The signature was verified for the source archive only, as `lyona-update`
  checks it; the images' digests were compared with the bundle's subjects, not
  verified with `cosign` one by one.
- No `lyona-update rollback` is recorded here, on either architecture. The
  Snapdragon X update's log is not attached. No update has run on the generic
  image's VM or the Raspberry Pi 4, or on an install from this release's
  images. ARM5-02 (#490) asks for an update and a rollback on its targets.
