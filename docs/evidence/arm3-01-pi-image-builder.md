# ARM3-01: the Raspberry Pi image builder

ARM Sprint 3 item ARM3-01 (issue #12). Built 2026-10-26 on the GB10 (DGX
Spark) build host of ARM Sprint 2. The acceptance is the builder producing an
image whose root filesystem passes the static checks: it does. Booting it is
not part of this item (see "Not tested").

## Decisions taken for it (2026-10-26)

- **A-5: one image, `linux-rpi`.** The Raspberry Pi kernel, 6.18.58, which the
  Pi firmware boots directly, for the Pi 4 and the Pi 5. Arch Linux ARM's own
  Pi tarball (`ArchLinuxARM-rpi-aarch64`) ships mainline `linux-aarch64` and
  U-Boot instead, which the Pi 4 ran for #32 (7.2.10). `linux-rpi-16k` (Pi 5
  only) is not used: there is no Pi 5 to measure it on.
- **The root filesystem is `pacstrap`ed**, not unpacked from that tarball. The
  tarball is a moving `latest` file (last changed 2026-08-05, 850 MB), served
  over HTTP, with an MD5 and a signature; and it ships `linux-aarch64`, U-Boot
  and the default `alarm`/`alarm` and `root`/`root` logins, all of which the
  image would remove. `pacstrap` installs only the dependency map's new
  `rpi-image` profile, each package checked against Arch Linux ARM's keyring.
- **lyona's system half is installed at build time; the per-user half at
  first boot.** `install.sh` refuses to run as root and installs for the user
  running it, and the image has no user. So it runs as a temporary build user
  (`lyona-image-build`), as the install medium's postinstall runs it as the
  new user, and that user is removed afterwards. Nothing `install.sh` writes
  system-wide names its user, except the gamemode group, which is x86_64
  only. The first-boot wizard (ARM3-02) runs the per-user half as the new
  user, from the copy of the source at `/usr/local/src/lyona`.
- **The full profile, as on the install medium**, not the plan's recommended
  one: only full installs a display manager (see F-3).

## The build

| | |
| --- | --- |
| Source | `main` at `e3cb1e3` (after #63), with this change uncommitted. The stamps read `e3cb1e3`: the builder records `git rev-parse HEAD`, as the ISO builder does, and does not mark an uncommitted tree |
| Build host | NVIDIA GB10 (DGX Spark), its Ubuntu 24.04 based OS, kernel 7.0.0-1019-nvidia; the `lyona-archlinuxarm:base-devel` container (Arch Linux ARM, pacman 7.1.0), `--privileged`, with `arch-install-scripts rsync dosfstools mtools e2fsprogs xz git` |
| Command | `scripts/build-lyona-rpi-image.sh --output /work/out` |
| Time | 222 s (build 4; builds 2 and 3: 219 s, 217 s), the download of 630 packages included |
| Image | `lyona-2026.10.0-beta.7-rpi-aarch64.img.xz`, 847,262,748 bytes, SHA-256 `0668da5efd937dc0cf736264b75ad2f75916a317f15bfddc36b57523544fb17d`; 5,828 MiB written out |
| Layout | MBR, disk identifier random per build (`0xcd083a19`); partition 1 at 4 MiB, 512 MiB FAT32 `LYONA_BOOT`, bootable; partition 2, 5,312 MiB ext4 `lyona-root`, 3.9 GB used |
| Kernel and firmware | `linux-rpi` 6.18.58-1, `raspberrypi-bootloader` 20261021-1, `firmware-raspberrypi` 20260311-1; device trees for the Pi 4, 400, CM4, Pi 5, 500 and CM5 in `/boot` (70 MB) |
| Desktop | 630 packages: Xorg 21.1.25, Mesa 26.2.5, Picom 13, Quickshell 0.3.2, LightDM 1.33.1 and slick-greeter, NetworkManager 1.58.1, `yay-bin`, `topgrade-bin` |
| Boot | `cmdline.txt`: `root=PARTUUID=cd083a19-02 rw rootwait console=serial0,115200 console=tty1 fsck.repair=yes`; `fstab` mounts both partitions by PARTUUID, which holds on SD, USB and NVMe alike. `config.txt` is `linux-rpi`'s (`vc4-kms-v3d`); what the desktop needs is ARM3-03 |

The image fits an 8 GB card. The first boot is to grow the root partition to
the card (ARM3-02).

## What was checked

On build 4's image itself, decompressed, its SHA-256 checked, its partitions
mounted read-only through loop devices at their offsets in the container:

- **`--check-root` on the image:** "nothing personal is left, and lyona is
  installed". That is:
  - no user (no UID 1000-59999, `/home` empty), so the wizard's first user is
    UID 1000; root's password locked; no NOPASSWD rule;
  - `/etc/machine-id` `uninitialized`; no D-Bus machine-id, systemd random
    seed or SSH host keys;
  - no pacman keyring and an empty package cache;
  - lyona's `/etc/lyona-release` (`LYONA_SOURCE=iso`), `/usr/local/bin/dwm`,
    the source at `/usr/local/src/lyona` (19 MB, root-owned),
    `/etc/lyona-iso-release` (`LYONA_ISO_KIND=rpi-aarch64`);
  - `kernel8.img`, and `cmdline.txt` naming the root by PARTUUID;
  - NetworkManager enabled, LightDM the display manager, `graphical.target`
    the default.
- **Enabled besides:** Bluetooth, power-profiles-daemon,
  NetworkManager-wait-online, systemd-timesyncd. `dwm.desktop` is the only
  X session.
- **A scan for leftovers:** no file in `/etc` or `/var` names the build user;
  no private key, `secring.gpg` or SSH host key in `/etc`, `/var` or `/root`;
  `/var/log` is 96 KB; and the image has no `%wheel` sudo rule (ARM3-02 must
  give the new user sudo).
- **`make check-rpi-image`** (`tests/test-rpi-image-builder.sh`):
  - the package list is the map's `rpi-image` profile, empty on x86_64, with
    no U-Boot, mainline kernel or 16K kernel;
  - the step order: yay built before the build user's sudo exists, install.sh
    only while it does, Topgrade after it is gone, the user removed and the
    root checked before the image is made;
  - the refusals: an x86_64 host, and as a normal user, before anything is
    made; a bad version; a boot partition under 128 MiB;
  - `--check-root` on a clean fixture, and 27 fault cases, one at a time.
- **The test fails on a broken builder:** with the machine-id check removed,
  the sudo rule left in place, the `/etc/passwd-` check removed, or the
  NetworkManager check loosened, it fails each time, naming the fault.
- **On aarch64, in the Arch Linux ARM CI container:** `check-rpi-image`,
  `check-arch-packages`, `check-archiso`, `check-shell`, `check-format`,
  `check-changelog-record`, `check-ci-parity`, `release-check`,
  `check-aur-policy`.
- **Lint:** shellcheck 0.10.0 (`-S warning`) and shfmt 3.10.0 find nothing in
  the builder, its test and `dwm-packages.sh`.

## Found while building, fixed here

- **F-1, pacstrap's keyring and machine-id.** In the first try, `pacstrap`
  left a pacman keyring in the root with a **private key**
  (`private-keys-v1.d`, `secring.gpg`): every Pi written from the image would
  share it. systemd's install also generated a machine-id. The builder
  removes both; the keyring is initialised at first boot (ARM3-02), and
  `--check-root` fails on either.
- **F-2, PackageKit's pacman hook.** Topgrade's `pacman -U` failed at its last
  step, "Refreshing PackageKit": the hook asks PackageKit over D-Bus, which a
  chroot does not have, and pacman fails the transaction. The install
  medium's postinstall hits the same hook and only warns
  (`arm2-05-generic-image.md`). The builder masks that one hook with an
  `/etc/pacman.d/hooks` file of the same name (`alpm-hooks(5)`) for the build,
  and removes the mask; `--check-root` fails if it is left.
- **F-3, no display manager with the recommended profile.** `install.sh`
  installs LightDM, wallpapers and user folders with the full profile only
  ("No display manager found; skipping display-manager installation for
  recommended profile"). The image uses full, as the install medium does; on
  aarch64 that adds LightDM and its greeter, qt6ct, rsync, autorandr,
  system-config-printer and arch-audit (gaming is x86_64 only).
- **F-4, NetworkManager and Bluetooth off.** In an image install
  (`LYONA_SOURCE=iso`), `install.sh` leaves NetworkManager and Bluetooth to the
  image's own step, which is the postinstall's on the medium. Build 2's image
  had both installed but neither enabled: a Pi would have booted without a
  network. The builder now does what the postinstall's last block does (the
  map's network profile, NetworkManager, LightDM, power profiles, Bluetooth,
  only lyona's session), and `--check-root` fails without NetworkManager,
  LightDM or the graphical target.
- **F-5, the shadow backups.** A scan of build 3's image found the build user
  in `/etc/passwd-`, `group-`, `gshadow-`, `subuid-` and `subgid-`, the copies
  `useradd` and `userdel` keep. `--check-root` did not look at them: run on
  build 3's image after it was extended, it failed on all five. The builder
  removes them; build 4 has none.

## For ARM3-02 and ARM3-03

- The first boot must: grow the root partition; generate the machine-id, the
  SSH host keys and the pacman keyring (`pacman-key --init`, `--populate
  archlinuxarm`); create the user with sudo (there is no `%wheel` rule); run
  lyona's per-user half as that user from `/usr/local/src/lyona` (`make
  install-user` and the home steps: mybash, wallpapers, user folders, which
  need the network or a copy made at build time); set the Wi-Fi country from
  the timezone; then start LightDM.
- The PARTUUID is the same on every card written from one image, as Raspberry
  Pi OS's is until its first boot changes it.
- `config.txt` and the boot splash are ARM3-03's.

## Not tested

- **Booting the image:** not on a Pi, and not emulated. This host's QEMU (8.2)
  has no `raspi4b` machine, and the image has no first boot yet, so it cannot
  reach a desktop (ARM3-02). The boot files are `linux-rpi`'s own.
- **The Pi 5,** at all (there is none), and NVMe boot.
- **Writing it:** with Raspberry Pi Imager or balenaEtcher, and to an actual
  8 GB card.
- **The x86_64 refusal on an x86_64 host:** the test stubs `uname`.
- **A build on another host,** or the GitHub arm64 runner.
