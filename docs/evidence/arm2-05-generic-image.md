# ARM2-05: the generic image on three virtual machines

ARM Sprint 2 item ARM2-05 (issue #11). Run 2026-10-25 on the build host of
ARM2-01 to ARM2-04 (`docs/evidence/arm2-04-mirrors-keyring.md`), an NVIDIA
GB10 (DGX Spark).

The plan named UTM and Parallels on Apple Silicon beside QEMU/KVM. There is no
Mac to run them on (the maintainer has the GB10 and a Raspberry Pi 4, which
does not use this image), so on 2026-10-25 the plan was changed to three
configurations on the GB10: they vary what UTM and Parallels would have varied
(the display device, how the medium is attached, the firmware's boot order),
and UTM and Parallels are not tested. All six installs (ext4 and btrfs on each
configuration) reached a working desktop with no step of the installer's
done by hand, and passed every check below.

## The medium

| | |
| --- | --- |
| Source | `main` at `e8a8640` (after #52), unmodified |
| Build host | NVIDIA GB10 (DGX Spark), its Ubuntu 24.04 based OS; the `lyona-archlinuxarm:base-devel` container (Arch Linux ARM), `--privileged`; archiso v91 checkout |
| Command | `LYONA_RELENG_DIR=... LYONA_MKARCHISO=... scripts/build-lyona-arch-iso.sh --arch aarch64`, as `docs/RELEASING.md` gives it; about 3 minutes |
| Image | `lyona-2026.10.0-beta.7-aarch64.iso`, 1,439,434,752 bytes, SHA-256 `9c24cca205840e24a29bce09565aa38357a2258d75d79bfe5a20df477db35aa8` |
| Stamp | `/etc/lyona-iso-release`: `LYONA_ISO_COMMIT=e8a86402d98e9acdf0a4c7c45fd111bd07371f6c` |

The first build failed: see F-1.

## The three configurations

All three: QEMU 8.2.2 with KVM, the `virt` machine, 8 vCPUs (`-cpu host` or
libvirt's `host-passthrough`), 8 GiB, AAVMF 2024.02, UEFI without Secure
Boot, a fresh 32 GiB virtio disk and fresh firmware variables for each
install, USB keyboard and tablet, user-mode virtio network. Mesa's software
renderer in each; Picom chose the `xrender` backend.

| | 1. QEMU/KVM | 2. Another display path | 3. libvirt |
| --- | --- | --- | --- |
| How it is made | `qemu-system-aarch64` by hand | `qemu-system-aarch64` by hand | `virt-install` 4.1.0 into libvirt 10.0.0's user session, with its defaults |
| Display, and the kernel's driver | virtio-gpu, `virtio-gpu` | `bochs-display`, `bochs-drm` (Xorg: `modesetting`) | libvirt's default, virtio-gpu |
| The medium | USB stick, no `bootindex` | SCSI CD (virtio-scsi), no `bootindex` | SCSI CD, libvirt's `<boot dev='cdrom'/><boot dev='hd'/>` (QEMU `bootindex`) |
| CPUs | pinned to the Cortex-X925 cores | pinned to the Cortex-X925 cores | not pinned: Cortex-X925 and A725 |
| Sound | Intel HDA to a WAV file, for the disk boots | Intel HDA to a WAV file | none (libvirt's default) |
| Other | | | a TPM (swtpm), a guest-agent channel, a serial console |

Configuration 3 kept libvirt's defaults but two:
- **Secure Boot off:** libvirt's default firmware has it on and refuses the
  medium (F-4).
- **Networking:** a user-mode virtio NIC with an SSH port forward, through
  `--qemu-commandline`, in place of libvirt's session NIC, which can forward
  no port without passt (not installed).

## How it was driven

- **The installer:** the medium's own wizard and postinstall, which matched
  `main` by SHA-256. The wizard's questions were answered from a file by a
  stand-in for `gum` (ARM2-03's), the same answers a person would give:
  - US keyboard, `/dev/vda`, the filesystem;
  - a user and password, hostname `lyona-arm`;
  - Europe/Berlin, Arch Linux ARM's mirrors in Germany;
  - wipe and install.

  Nothing else was typed or fixed during an install.
- **SSH:** into the live medium, and for the checks into each installed
  system. Root's `authorized_keys` got a test key, and `sshd` was started for
  that boot only (it is installed, not enabled). This is the only change made
  to the installed systems besides the checks below.
- **Input and screenshots:** keys, clicks and screenshots through QMP
  (configuration 3: `virsh qemu-monitor-command` and `virsh screenshot`).

## The installs

| Configuration | ext4: archinstall, postinstall | btrfs: archinstall, postinstall | First boot |
| --- | --- | --- | --- |
| 1. QEMU/KVM | 2 m 00 s, 4 m 15 s | 1 m 47 s, 3 m 52 s | Rebooted on its own through `Boot0008 "lyona"` to the greeter |
| 2. bochs-display, CD | 1 m 51 s, 4 m 16 s | 1 m 56 s, 4 m 06 s | The same, the CD still attached: the firmware started `Boot0008 "lyona"`, not the CD |
| 3. libvirt | 2 m 03 s, 4 m 30 s | 2 m 03 s, 4 m 25 s | libvirt stopped the machine at the install's reboot (`on_reboot=destroy` for the install boot, as virt-install does with `--noautoconsole`); `virsh start` booted `Boot0004 "lyona"` to the greeter |

In configuration 3, the firmware kept the `lyona` entry the postinstall
added and dropped the CD's, which was no longer in libvirt's boot order. So
the `bootindex` case ARM2-03 found (entries outside QEMU's boot order deleted)
does not remove the installed system's entry when the disk is in the boot
order, as libvirt puts it.

All six systems:
- **Installed state:** `LYONA_SOURCE=iso` at `e8a8640`, the wizard's line
  "Using 3 Arch Linux ARM mirrors in DE, then mirror.archlinuxarm.org.", and
  the mirrorlist de3, de, de4, then `mirror.archlinuxarm.org`. All 17
  postinstall steps passed.
- **Network and locale:** NetworkManager active and systemd-networkd off,
  `LANG=en_US.UTF-8`.
- **Units:** none failed.

Their postinstall logs show, as expected:
- pacman's "Refreshing PackageKit" hook failing inside the chroot ("The name
  is not activatable"), as on x86_64 (`arch005-beta7-image-qualification.md`);
- mkinitcpio skipping the `microcode` hook ("architecture 'aarch64' not
  supported"): there is no CPU microcode to load on aarch64;
- `libfakeroot internal error: payload not recognized!` while building
  `yay-bin`, which then built and installed.

The only error in any journal after login is LightDM's `gkr-pam: unable to
locate daemon control file`.

## The desktop (ARM1-06's checks)

The same checks on all six systems:

| Check | 1. QEMU/KVM | 2. bochs-display | 3. libvirt |
| --- | --- | --- | --- |
| Log in at the greeter: dwm, the panel, Picom (`xrender`) | Pass | Pass | Pass |
| Launcher (Super+R) starts an application | Pass (Firefox) | Pass (Firefox) | Pass (Firefox) |
| Terminal (Super+X) | Pass | Pass | Pass |
| Overview with Picom: window previews | Pass | Pass | Pass |
| Overview without Picom: icon and title cards, no crash | Pass | Pass | Pass |
| Settings: all 9 panes open | Pass | Pass | Pass |
| System Information names the CPU | "Arm Cortex-X925" | "Arm Cortex-X925" | "Arm Cortex-X925 + Arm Cortex-A725" (unpinned vCPUs), 8 logical |
| Network: connected, in the panel and Settings | Pass | Pass | Pass |
| Audio: a sound plays; the volume key works | Pass: the capture has it (peak 9800 of 32767); 40% to 50%, in the panel | Pass, the same | No sound device: Settings shows "Dummy Output" |
| Reboot, log in again, no failed units | Pass | Pass | Pass |
| `lyona-update check` | `current` (F-2) | `current` | `current` |

Bluetooth reports "BlueZ daemon is unavailable" on all three: there is no
adapter.

## Update and rollback

On each system:
1. `lyona-update check`;
2. `lyona-update apply --yes` in the desktop's terminal, with the polkit
   prompt on screen, answered with the user's password;
3. `lyona-update rollback`, confirmed with `y` and the polkit prompt.

The installed lyona files (118, all under `/usr/local`) were checksummed
before the apply, after it and after the rollback.

| | All six systems |
| --- | --- |
| `check` | `current`: installed `2026.10.0-beta.7` (`e8a8640`), available `2026.10.0-beta.7` (`e1c92e9`, upstream Lyona) |
| `apply` | Exit 0 in about a minute: downloaded, digest and signature checked, built, backed up, installed, "All managed files match the checkout". **11 files replaced by upstream's**, and none left that knows `archarm` (F-2) |
| `rollback` | All 118 files restored exactly; `iso` and `e8a8640` again; System Health's package check "ok" again (checked on five; not re-run on configuration 1 btrfs). On two of the six (configuration 1 btrfs, configuration 3 btrfs), the runtime check then reported "expected one Quickshell process, found 2" (F-3) |

There was no newer build to update to: the image is at `main`'s version, and
Lyona-ARM publishes no releases. The plan's "an update from the image's
release to the next build" is not possible until it does (ARM5-01, ARM5-02).

## Found

- **F-1, rsync.**
  - The first build stopped after the package layer and the splash, with
    `rsync: command not found`.
  - The builder embeds the checkout with `rsync`, which archiso does not
    depend on (its README's requirements don't list it). `docs/RELEASING.md`
    didn't mention it either, on either architecture.
  - **Fixed here:** the builder checks for `rsync` before it stages anything,
    in `--profile-only` too, and `docs/RELEASING.md` lists it.
  - `tests/test-arch-iso-builder.sh` runs the builder with a `PATH` that has
    no rsync, and expects that message and nothing staged. It failed on the
    builder without the check.
- **F-2, updates come from upstream Lyona (#53).**
  - `lyona-update`'s release repository is a constant: upstream Lyona, which
    has no Arch Linux ARM support.
  - On all six systems, the apply replaced 11 Lyona-ARM files with upstream's,
    among them `dwm-utils.sh`, `dwm-packages.sh`, `dwm-settings-picom` (#32's
    Pi 4 handling) and the root helper.
  - Afterwards, no installed file mentioned `archarm` (three had). On the
    configuration 1 ext4 system:
    - `dwm-utils.sh` gave `DISTRO_FAMILY=unknown`;
    - System Health reported "Arch Linux is required for package validation";
    - Settings' discovery reported the platform family `unknown`.
  - `/etc/lyona-release` read `LYONA_COMMIT=unknown`, `LYONA_SOURCE=tarball`:
    upstream's #457, fixed after its beta.7.
  - `check` called the install `current` because the version numbers match,
    though the trees differ.
  - The rollback undid all of it. Left for ARM5-01 and ARM5-02, as decided for
    this item: the update and rollback work as designed, and the fault is
    where the update comes from.
- **F-3, the runtime check races the shell restart (technicks89/Lyona#460).**
  - After two of the six rollbacks, `lyona-install-verify.sh` reported
    "expected one Quickshell process, found 2", though the rollback was
    complete and one shell ran.
  - The cause:
    - the restart the check asks for runs detached and returns at once;
    - so the old shell answers the verifier's IPC probe;
    - and `pgrep -xc quickshell` also counts the `quickshell kill` command
      the restart is running.
  - Sampling every 50 ms after a restart showed the old shell beside a
    short-lived `quickshell` process, then the old one alone, then the new
    one, three times out of three.
  - The code is upstream's, unchanged, so the issue is there.
- **F-4, Secure Boot.**
  - libvirt picks the first firmware descriptor that matches, here
    `40-edk2-aarch64-secure-enrolled.json` (`AAVMF_CODE.ms.fd`: Secure Boot
    with Microsoft's keys).
  - With it, the firmware refused the medium: `failed to load Boot0001 "UEFI
    QEMU QEMU CD-ROM" ...: Access Denied`, then "No bootable option or device
    was found". The image's boot loader is not signed, on either architecture.
  - Nothing in the docs said to turn Secure Boot off.
  - **Fixed here:** `docs/src/install.md`'s boot step says so, for firmware
    and for libvirt and virt-manager (with the `virt-install` option).
  - Signing the image is not in scope (`SPEC.md` has no Secure Boot
    requirement).

Seen, not faults of this change, recorded for follow-up:
- **Appearance on a new system:** a fresh install's Settings > Appearance says,
  in the warning colour, "Selected appearance is only partially applied". No
  wallpaper has been chosen yet, and `dwm-settings-wallpaper` reports
  `partial` then, by design. It reads like a fault on a new system; x86_64 is
  the same.
- **The rollback's progress popup:** during the rollback's `[y/N]` question,
  its headline read "Restarting the desktop shell", over "Verifying backup",
  before anything was restored.
- **btrfs layout:** the btrfs installs have no subvolumes: `/` is the top of
  the filesystem (`subvolid=5`). The wizard gives archinstall `"btrfs": []` on
  both architectures, and nothing in `SPEC.md` asks for a subvolume layout.
- **Settings > System:** it took more than 4 seconds to appear the first time
  it was opened (it asks GitHub for the release), and appeared at once after.

## Not tested

- **UTM and Parallels** on Apple Silicon, and their display devices (Apple's
  paravirtual GPU, Parallels' own). There is no Mac. Configuration 2 is the
  nearest stand-in here: a framebuffer device that is not virtio-gpu.
- **Update to a newer build:** an update to a newer build than the image's
  needs a Lyona-ARM release (F-2).
- **Sound under libvirt:** its default machine has none. Sound was checked in
  configurations 1 and 2.
- **Other paths:** LUKS since ARM2-04 (ARM2-03 ran ext4 with LUKS), Secure
  Boot (the medium is unsigned, F-4), and real hardware: the GB10 itself is
  ARM-4, deferred, and the Pi 4 is ARM-3, with its own image.
- **Hardware not in these VMs:** virgl (3D acceleration), more than one
  display, Wi-Fi, Bluetooth.
- **x86_64:** an x86_64 install with ARM2-04's keyring wait and mirror-name
  check.
