# S15-05: updates and the login keyring in a live session

Sync Sprint 15 S15-05, issue `#218`. **Status: partly run.** S15-01 to S15-04 are
covered by their own tests, against stubs, under Xvfb. What follows is what was
run on a real machine, and what still needs a live session.

## Run on a real machine (2026-10-02)

The machine was an Arch (CachyOS) install, kernel `7.2.5-1-cachyos`, with
`pacman-contrib` 1.13.1, `gnome-keyring` 1:50.0, and `lightdm` 1:1.33.1. Every
command below is read-only.

| Check | Result |
| --- | --- |
| `lyona-update-indicator check` counts pending packages with the real `checkupdates` | Passed: `provider system available 51`, in under a second |
| The same check without Flatpak installed | Passed: `provider flatpak unavailable 0 Flatpak is not installed`, not an error |
| `lyona-update-indicator watch-network` subscribes to the real NetworkManager on the system bus | Passed: `network-event ready` |
| `dwm-diagnostics --format health-tsv` reports the installed keyring | Passed: `ok dependency-package-gnome-keyring` |
| Arch's LightDM PAM stack loads the keyring module | Passed: `/etc/pam.d/lightdm` has `-auth optional pam_gnome_keyring.so` and `-session optional pam_gnome_keyring.so auto_start` |

## Still to run in a live session

Each check here changes the machine, or needs a fresh install, so none was run.

| Check | Status |
| --- | --- |
| A `recommended` install on a clean Arch VM gets `gnome-keyring` | not run |
| After a LightDM password login, the login keyring is unlocked (`secret-tool store` then `secret-tool lookup` without a prompt) | not run |
| Removing `gnome-keyring` shows the System Health warning; reinstalling clears it | not run |
| The panel icon shows the real count, hides once updated, and a real reconnect (Wi-Fi off and on) triggers a check | not run |
| The shell stays near idle with the icon shown, on more than one screen | not run |
| **Update packages** runs `yay -Syu` (and, without `yay`, `sudo pacman -Syu`) in a real terminal, tiled and floating | not run |
| Declining the plan at the prompt reports "Not updated" | not run |
| Closing the terminal mid-update reports that it closed early | not run |
| **Update Flatpak apps** with real Flatpak updates in both installations | not run (Flatpak is not installed on the machine above) |
| `flatpak remote-ls --updates --columns=application,branch` prints one row per update and no header when not attached to a terminal | not run against a real Flatpak; the tests use a stub that assumes it |
| An install from the live medium builds Topgrade after its sudoers file is removed, and `topgrade --version` prints the newest release in a new shell (S15-06) | not run; a real build (of 17.12.1, when it was pinned) passed in an isolated home on 2026-10-02 |

Record, for each run:
- the machine, or the VM and its image;
- the display manager;
- the terminal emulator;
- anything that went wrong.

Not covered at all: display managers other than LightDM (SDDM and GDM ship
their own PAM stacks), and terminals other than Alacritty, kitty, st and xterm.
