# ARM3-02: the Raspberry Pi image's first boot

ARM Sprint 3 item ARM3-02 (issue #13), on the ARM3-01 branch, so the first
pull request is a builder whose image boots to a desktop. Run 2026-10-26 on
the GB10 build host. The acceptance is a stubbed first boot that creates the
user, sets each answer and disables itself: `tests/test-rpi-firstboot.sh`
does that. The image's real first boot was also run, in a KVM virtual machine
(below), and found six faults, all fixed here. A first smoke boot on a Pi 4
(2026-10-27) reached the desktop and found a seventh, F-7, fixed after it.

## What the first boot does

`rpi/lyona-firstboot.sh`, from `lyona-firstboot.service`, as root on tty1,
before LightDM:

1. **This machine's own state:** the root partition grown to the end of the
   card or drive (when 16 MiB or more is left over), the pacman keyring made
   and Arch Linux ARM's keys added, the SSH host keys made, and the
   machine-id (systemd makes it; this is the fallback).
2. **The install medium's questions,** its own functions
   (`lyona-install.sh` loaded as a library, with `lyona-ui.sh` and
   `lyona-wifi.sh`, from the image's `/usr/local/src/lyona`): the network
   (Wi-Fi when there is none), keymap, user and password, hostname, timezone
   with the opt-in lookup, then a summary. **Change the answers**, or Esc at
   any question, asks them all again.
   - **Wi-Fi:** the medium's Wi-Fi uses iwd; a Pi runs NetworkManager. The
     same screens (a network from the scan, or a hidden one, and the
     passphrase) write a NetworkManager keyfile, as the medium's
     `wifi_carry_over` does, so the passphrase is in no process's arguments.
   - **The locale** is en_US.UTF-8, as on the install medium, which does not
     ask for it either; the plan listed it as a question.
3. **The answers applied:** `localectl set-keymap` (the console and X11),
   the hostname, the timezone with NTP, and the Wi-Fi country from the
   timezone, in the file the medium's postinstall writes. The user is
   created in `wheel`; a `%wheel ALL=(ALL:ALL) ALL` rule is written (checked
   with `visudo`), as archinstall's `sudo: true` does on the medium; the
   password goes to `chpasswd` on stdin.
4. **lyona's per-user half, as that user** (the maintainer's choice of
   2026-10-26): the source copied to `~/.local/src/lyona`, where `install.sh`
   keeps it; then `install.sh`'s home steps through the same scripts:
   - mybash;
   - the user folders;
   - the wallpapers, from `install.sh`'s own pinned repository and commit;
   - `configure-build.sh --non-interactive`, `make clean`, `make`;
   - `make install-user`, as `lyona-update` runs it;
   - the first-login keys.

   A step that needs the network and fails (mybash, the wallpapers) is a
   warning on the last screen, not a failure.
5. **Done:** the marker `/var/lib/lyona/firstboot-done`, and the unit
   disabled. LightDM waits for the marker (`lightdm-after-firstboot.conf`).

A run that stops part way starts again at the next boot. It records the user
it creates first, and the next start removes that user before asking again. A
failed step offers **Start again** or **Power off**.

The builder adds to the image: the script, the unit (enabled) and the LightDM
drop-in; `gum` and `zram-generator` (the map's `rpi-image` profile); the
console palette; the en_US.UTF-8 locale; and zram swap with zstd, as
archinstall sets up on the medium. `--check-root` checks each of them.

## The boot in a virtual machine

QEMU 8.2 has no Raspberry Pi 4 machine. So the image was booted on QEMU's
`virt` machine under KVM: a **copy** of its disk, made 16 GiB, with Arch
Linux ARM's `linux-aarch64` 7.3 and its modules added to the copy, and an
initramfs for it. The kernel was booted directly (`-kernel`), with the
image's own root (`root=PARTUUID=…-02`), virtio-gpu, a virtio NIC and a USB
keyboard. The wizard was answered through QMP: US keyboard, `tester`,
hostname `lyona-pi`, no lookup, Europe/Berlin.

This tests the first boot, the unit order, LightDM and the user's install.
It does not test the Pi's kernel (`linux-rpi`), its firmware, `config.txt`,
or the Pi's own devices.

The image: `lyona-2026.10.0-beta.7-rpi-aarch64.img.xz` (build 8),
848,295,708 bytes, SHA-256
`5616a4d8d946866f33d0e26eee90f8ef6f3e8999c22e9812898b0affceee6876`, 224 s to
build.

On build 8's image:
- **Boot:** straight to lyona's keyboard question; no systemd questions and
  no kernel messages over the screens.
- **Change the answers:** started the questions again.
- **Set up to the greeter:** 32 s. The root partition grew from 5,312 MiB to
  15.5 GiB.
- **The greeter:** lyona's, with `tester` and `lyona-pi`. The login reached
  the desktop: dwm, the panel with network, Bluetooth and volume, a
  downloaded wallpaper.
- **The terminal (Super+X):** `sudo -v` with the wizard's password; `id`
  gives uid 1000, in `wheel`; the hostname `lyona-pi`; `Europe/Berlin`;
  `systemctl --failed` lists none.
- **On the disk afterwards:**
  - the machine-id, SSH host keys and keyring;
  - `ieee80211_regdom=DE`;
  - the wheel rule;
  - mybash, the user folders, the wallpapers;
  - `install.state` (`LYONA_SOURCE=iso`);
  - `dwm`, `lyona-toml`, `dwm-xwatch` and `dwm-window-thumb` built in
    `~/.local/src/lyona`;
  - "applied theme 'tokyonight'";
  - the done marker, and the unit disabled.
- **The enabled units after the first boot are the image's:** NetworkManager,
  LightDM, Bluetooth, power profiles, timesyncd, and no `systemd-networkd` or
  `systemd-homed`.
- **The first run with the German layout** (build 6) set `de` for the
  console and X (`vconsole.conf`, `00-keyboard.conf`); build 8's US layout
  was not read back.

## Found booting the image, fixed here

The stubbed tests passed for each of these; only the real boot showed them.

- **F-1, systemd's own first-boot questions.** systemd's "Initial Setup"
  (`systemd-firstboot`) asked for the timezone, root password and more on the
  console, before lyona's wizard. It runs because the machine-id is
  `uninitialized`, which it must be so each Pi gets its own. It is now
  masked, and `--check-root` checks that.
- **F-2, gum crashed under the unit.** `gum filter` panicked (`makeslice: len
  out of range`) and the wizard restarted in a loop. When its answer is
  captured, gum draws on stderr. With `StandardError=journal` it had no
  terminal to size. The unit now has `StandardError=tty`; the wizard logs to
  `/var/log/lyona-firstboot.log`.
- **F-3, kernel messages over the wizard.** `linux-rpi`'s `cmdline.txt` has
  `console=tty1` and no `quiet`. The image now boots `quiet loglevel=3`, as the
  install medium does, and `--check-root` checks it.
- **F-4, systemd's first-boot presets.** At its first boot, systemd applies the
  presets to every unit (`preset-all`). Arch's end in `disable *`: LightDM,
  Bluetooth and power profiles were disabled, and `systemd-networkd` and
  `systemd-homed` enabled. The builder now writes
  `/etc/systemd/system-preset/10-lyona-image.preset` from the units the build
  enabled, ending in `disable *`, so the presets keep the image as built.
  `--check-root` checks it enables LightDM, NetworkManager and the first boot.
- **F-5, the theme step without its helper.** `make install-user`'s theme step
  failed: `lyona-toml` is built by `make`, which `install.sh` runs in the
  checkout first. The first boot now builds the user's copy the same way
  before `make install-user`.
- **F-6, the getty cancelled LightDM.** The unit started tty1's getty when the
  wizard ended, and Arch's `lightdm.service` conflicts with `getty@tty1`.
  LightDM's start was cancelled, and the greeter never came. The unit no
  longer starts the getty: LightDM takes tty1. The test fails if it does.

Also found and fixed while writing the test: `tests/test-rpi-firstboot.sh`
needs `TERM` as the unit sets it (`Environment=TERM=linux`). Without it, in
the CI container, `clear` failed. The test now runs the script with the
unit's `TERM`, and checks the unit sets it.

## The first boot on a Pi 4 (2026-10-27)

A smoke boot of build 8 on the maintainer's Raspberry Pi 4 (8 GB), written to
an SD card with `dd` from the `.img.xz` (its SHA-256 checked). It is not
ARM3-06's run: that is the whole checklist, on the final image.

- **The Pi's own boot:** the firmware booted `linux-rpi` (`uname -r`:
  `6.18.58-1-rpi`) to the wizard, and the first boot ran to the greeter. The
  login reached the desktop.
- **The root partition** grew to the card: 58G on `/dev/mmcblk0p2`, 4.2G
  used.
- **zram with zstd works on `linux-rpi`:** `/dev/zram0`, `zstd`, 1.9G, as
  swap. That answers the question the VM left (it ran another kernel).
- **`systemctl --failed`** lists none.
- **The user's install** took 44 s on the Pi ("Installing lyona for ...
  done in 44s"); the first boot ran from 10:06 to 10:08.
- **The journal's warnings** (`-p warning`) are the same on any lyona
  install, none from the image: the Thunar and Tumbler D-Bus service files'
  names, RTKit not installed (PipeWire uses its defaults), `systemd-homed`
  not running (the image keeps it off, F-4), `gkr-pam`, and the
  `BecomeMonitor` denial of the lock and power watchers' `dbus-monitor`,
  which then falls back to its match rules.

Found, two faults in the first boot's log:

- **F-7, the install profile not recorded** ("No install profile is recorded
  for this account; treating it as recommended"). On the install medium,
  `install.sh` records the profile with `lyona-reconcile-user --profile`;
  the first boot ran only `make install-user`, which reads the record. The
  account steps are the same for recommended and full today, so nothing
  differed, but the full image's account read as recommended. Fixed here:
  the builder records the profile it installs (`LYONA_INSTALL_PROFILE=full`
  in `/etc/lyona-iso-release`, and `--check-root` fails without it), and the
  first boot records it for the user before `make install-user`; a failure is
  a warning, as in `install.sh`. Not yet checked on a rebuilt image.
- **`config.h` copied as "customised"** for an account that changed nothing.
  `scripts/configure-build.sh` sets the font size with `s/(size=)…/g`, which
  also rewrites the emoji font's `pixelsize=14`, so every generated
  `config.h` differs from `config.def.h`, and `make install-user` copies it to
  `~/.config/lyona/config.h`. That is lyona's shared code, on x86_64 too:
  technicks89/Lyona#464. It comes here with a sync, before ARM3-06's image is
  built.

Not yet reported from the smoke boot: the HDMI resolution, Wi-Fi without
Ethernet, the time to the wizard, how the desktop responds, and a reboot.

## Tests

- **`tests/test-rpi-firstboot.sh`** (`make check-rpi-image`), with every
  command that touches the machine stubbed and the files under a private
  root:
  - **The unit:** tty1 for input, output and errors, `TERM=linux`, before
    LightDM and in place of tty1's getty, and not starting the getty after.
  - **A full first boot:** the partition grown, the keyring, the SSH keys and
    the machine-id. The keymap, hostname, timezone, NTP and Wi-Fi country.
    The user in wheel, the `%wheel` rule (mode 440, checked with `visudo`),
    and the password on `chpasswd`'s stdin and in no command's arguments or
    log. Mybash, the user folders, the wallpapers (from `install.sh`'s pins,
    without their `.git`), the build, then `make install-user` as the user,
    and the first-login keys. The done marker, and the unit disabled.
  - **A second start does nothing,** and a card the root already fills is
    not touched.
  - **An interrupted run's user is removed before the new one is made.**
  - **Starting the questions again:** Esc at the first question, and
    **Change the answers**, start them again and create no user.
  - **A failed step:** Power off leaves it not done, with its user recorded
    for the next start to remove. **Start again** restarts.
  - **Wi-Fi:** nmcli's terse scan with escaped `:` and `\` in the names. The
    security types. A WPA network's keyfile (mode 600) loaded and brought up,
    with the passphrase not in nmcli's arguments. A failed connection's
    profile removed and explained. An enterprise network explained, not
    tried.
- **`tests/test-rpi-image-builder.sh`**: 39 fault cases now, the first
  boot's included.
- **The tests fail on broken code:** with the unit's disable removed, the
  half-made user left, or the password passed to `chpasswd` as an argument,
  the first-boot test fails, naming the fault.
- **In the Arch Linux ARM CI container:**
  - `check-rpi-image`, `check-arch-packages`, `check-archiso`,
    `check-iso-install-aarch64`;
  - `check-shell`, `check-format` (both now cover `rpi/`);
  - `check-changelog-record`, `check-ci-parity`, `release-check`,
    `check-aur-policy`.
- **Lint:** shellcheck 0.10.0 and shfmt 3.10.0 find nothing.

## Seen, not changed

- **The wizard's header says "Arch Linux Installer"**, from `lyona-ui.sh`'s
  `show_logo`, which the install medium shares.
- **zram with zstd:** in the VM, on `linux-aarch64`, zram-generator said
  "algorithm "zstd" not recognised" and used the kernel's default; the 2 GiB
  zram device came up. Whether `linux-rpi` has zstd for zram is ARM3-06's to
  see.
- **Building in the user's copy** took 2 s on the GB10. On a Pi 4 it will
  take longer (ARM3-06 measures it).

## Not tested

- **The whole Pi 4 run:** ARM3-06. The smoke boot ran the Pi's kernel and
  firmware to the desktop; Wi-Fi (the NetworkManager path ran only stubbed)
  and HDMI are not yet reported, and F-7's fix has not booted on the Pi.
- **The Pi 5,** and NVMe.
- **Offline:** a first boot with no network, where mybash and the wallpapers
  are skipped with a warning (stubbed only).
- **Power loss part way:** stubbed only (an interrupted run's user removed).
