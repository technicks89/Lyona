# #369: display preview recovery

Issue `#369`: Settings > Displays looped on "Keep these display settings?"
after an interrupted preview, and no display change could be made from
Settings. Validated on 2026-10-13 with the uncommitted branch
`fix/display-preview-369` (based on `main` at `a0a661f`).

## Static and unit tests (dev host, through `scripts/run-tests`)

All pass:
- `tests/test-dwm-display-setup.sh`, including the #369 cases:
  - the recorded session and watchdog, where the PID is the watchdog itself;
  - Settings on a nested display leaving another server's live preview alone;
  - a restarted server, through status and through the watchdog;
  - a dead watchdog on the same server reported as a rollback failure, then reverted;
  - the pre-change leftover state dropped;
  - a half-started reservation cleared;
  - Revert refusing a layout naming a disconnected output (naming only that output) and keeping its claim released;
  - Discard, including an old token never freeing the current reservation;
  - a held mutation lock making Keep wait.

  The new cases fail against the helper on `main`.
- `tests/test-settings.sh`, `tests/test-dwm-settings-wallpaper.sh` (wallpaper now uses the shared `dwm-xsession.sh`), `tests/test-quickshell-plain-text.sh`, `tests/test-settings-input.sh`.
- `make check-installed-helper-paths check-shell-contracts check-session-isolation check-dev-sync-install check-quickshell-qml`.

ShellCheck and shfmt were not available on the host.

## Virtual machine

- **Host:** QEMU 11.1.2 with KVM, q35, UEFI (OVMF), 4 vCPUs, 6 GiB, 40 GiB virtio disk, virtio-gpu (one connected head, `Virtual-1`, 1280x800).
- **Guest:** the official Arch Linux cloud image
  (`Arch-Linux-x86_64-cloudimg.qcow2`, SHA-256
  `360f0fa49db6813bdc8e35bed230a2dc2ae3567b7b5ab74719c0a706e4e34e87`, matched against its published checksum), upgraded to `linux` 7.2.9.
- **lyona:** installed from the branch with the existing-system installer, `install.sh --non-interactive --profile full --skip-topgrade --skip-yay`. It finished with only the expected warning: gaming packages skipped because multilib was not approved.
- **Session:** LightDM autologin (test-only drop-in) into the `dwm` session, with Quickshell and Picom (xrender) running.
- **Not tested:** the ISO image and its wizard. Building the image needs root on the host, which was not available. The ISO path installs the same helper and shell.

Each scenario was run in the live session. Previews were started with `dwm-settings-display preview` detached from the test shell, as Quickshell starts it. The panel was driven through its `settings` IPC target and with `xdotool` clicks, and checked from QEMU screen dumps.

| Scenario | Result |
| --- | --- |
| Original bug: preview rotating `Virtual-1` left, watchdog frozen, Xorg killed with SIGKILL mid-preview, watchdog killed, re-login | The leftover state was intact after re-login. Opening Settings dropped it: "An interrupted display preview was discarded; the current layout stays." No prompt, and nothing applied to the new server. |
| Same, with the watchdog left alive | The watchdog woke on the new server, judged the preview foreign and removed it without applying its layout. |
| Watchdog killed, same server | Settings showed "The automatic rollback is no longer running." with Keep current, Revert and Discard. Revert restored the layout ("Previous display layout restored.", which stayed visible after the refresh). No surprise revert at the timeout. |
| Captured layout naming a disconnected output (`DisplayPort-0`) | Revert was refused before touching the display: "The previous layout cannot be restored: output is not connected: DisplayPort-0." It named only the missing output. Revert was disabled, and Discard removed the preview while the screen stayed as it was. |
| The state the reporter's machine had (old-format preview six hours old, amdgpu output names, orphaned claim) | Dropped as soon as Settings opened, with nothing applied. |
| Everyday path through the panel: Rotation, Apply changes, countdown, timeout | The prompt counted down with Keep changes and Revert only, then restored the layout ("The display preview ended; the previous layout was restored."). |
| Apply changes, then Keep changes | "Display settings kept." The layout stayed past the timeout, and was re-applied at the next login. |

## Found during the VM run

- **Fixed:** the recorded watchdog PID was the subshell around the watchdog, so killing that subshell alone left the real watchdog running. It is now `exec`'d, and a test pins it.
- **Fixed:** "Revert tries again" wording on a rollback that was never tried, and an `error:` prefix in the refusal text.
- **Not part of #369, still open:** the Settings window does not resize when the screen it is on turns portrait. With a single screen rotated left or right, Keep changes and Revert are off-screen, so the countdown always reverts.

## Not tested

- Real hardware, including the reporter's AMD RX 9070 with two DisplayPort monitors.
- Two connected heads in the VM (the second virtio head stays disconnected without a second viewer).
- Input previews, which do not have this recovery yet.
