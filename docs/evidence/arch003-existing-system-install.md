# ARCH-003: `install.sh` on an existing Arch system

Qualifies the existing-system installer against a stock Arch install that
someone already lives in, per `SPEC.md` section 5.5 and ARCH-003's acceptance:
"`install.sh` on a real pre-existing Arch system does not lose or silently
overwrite user data or configuration outside its documented, owned paths."

## Machine

QEMU 11.1.2 with KVM, q35, x86_64, UEFI (OVMF), 4 GiB, a 40 GiB virtio disk,
a standard VGA adapter, no NVIDIA GPU. Stock Arch from
`archlinux-2026.10.01-x86_64.iso` (`pacstrap` of `base`, `linux`, GRUB,
NetworkManager, PipeWire, zram), kernel 7.2.11-arch1-1, as a copy-on-write
overlay so each run started from the same disk.

## What was seeded

For the user `lyona` (`wheel`):
- **Files:** documents, music, pictures and an SSH key.
- **Shell and X:** `.bashrc` with an alias, `.bash_profile`, an `.xinitrc`
  that runs `xterm`, and `.Xresources`.
- **lyona's own file:** a `~/.config/lyona/hotkeys.toml` binding Super+X to
  `xterm`.
- **Other applications:** alacritty, picom, GTK 3 (`Adwaita-dark`), a
  `mimeapps.list` sending `video/mp4` to VLC, an autostart entry, a launcher
  entry, starship and fastfetch.
- **Permissions:** `~/.config` at 700 and `~/.local/share` at 750.

For the system:
- SDDM installed and enabled as the display manager.
- `pacman.conf` with `Color` and a comment, and GRUB with `GRUB_TIMEOUT=7` and
  an extra kernel parameter.
- A keyboard `xorg.conf.d` file, an `/etc/environment` entry and a sudoers
  file.

## Runs, 2026-10-19

`install.sh --non-interactive --profile full --skip-topgrade`, as the user,
from a copy of the tree. As with the image wizard, a temporary passwordless
`sudo` rule was present while it ran. `/etc`, the whole home directory,
enabled units, packages and `grub.cfg` were compared before and after.

**Run 1, `main` at `2b7d9cc`:** exit 0 in 51 s.

Unchanged, every seeded file and setting except the GTK theme:
- The user's files, `hotkeys.toml`, `.xinitrc` and the other applications'
  configuration.
- `pacman.conf`, the xorg file, the sudoers file and `/etc/environment`.
- The directory permissions and the user's groups.

Changed, and named in the summary first:
- **Shell files:** `.bashrc`, `starship.toml` and the fastfetch config became
  mybash links, each original kept as `.bak.<time>`.
- **GRUB:** `/etc/default/grub` was backed up, then gained only `GRUB_THEME`;
  `GRUB_DISABLE_BOOTNEXT` went to a drop-in. The timeout and kernel command
  line were untouched.
- **Services:** `bluetooth` and `systemd-timesyncd` were enabled.
- **AppImages:** `mimeapps.list` gained the AppImage handler, since none was
  set. The `video/mp4` choice was kept.

SDDM stayed the display manager. After a reboot, logging in through SDDM to
the `lyona` session reached the desktop, and Super+X opened `xterm`: the
user's binding.

**The finding:** in `~/.config/gtk-3.0/settings.ini`, `theme-apply.sh`
replaced the user's `gtk-theme-name=Adwaita-dark` with `Lyona-tokyonight` and
added cursor keys. No copy was kept, and the summary did not mention it.

**Run 2, the same system again:** exit 0. Nothing changed but
`/etc/lyona-release` and the install state file.

**Run 3, the fix, on a fresh copy of the seeded system:** `install.sh` now
keeps a GTK settings file that sets a theme, cursor or dark preference as
`FILE.bak.<time>` on the first install for an account, and says so in the
summary:
- The summary said "GTK theme: lyona's theme and cursor replace yours in
  `~/.config/gtk-3.0/settings.ini` (previous files kept as `.bak.<time>`)".
- `settings.ini.bak.<time>` holds `gtk-theme-name=Adwaita-dark`.
- A second run named nothing and kept no second copy.

## Not covered here

- Interactive runs (the summary's confirmation, `sudo` prompts) and the
  `core` and `recommended` profiles.
- An existing LightDM or GDM, and real hardware.
- The closing hint, "or start with: startx", runs the user's own `.xinitrc`,
  here `xterm`, not lyona. Noted, not changed.
