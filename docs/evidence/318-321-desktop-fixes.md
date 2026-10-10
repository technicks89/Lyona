# #318 to #321: desktop fixes, validated

Branch `desktop-fixes-318-321` (PR #330), with the CodeQL and CodeRabbit
follow-ups.

## Suite

Each of the 152 steps of `make check` was run on its own through
`scripts/run-tests`, with its exit status recorded: 152 of 152 passed, none
skipped. `run-tests` now fails a step that leaves a process running (#321); it
found one (`test-autostart.sh`'s stub watcher, fixed) and no other. The steps
the review follow-ups touched were run again after them: `check-tomlparser`,
`check-quickshell-state`, `check-quickshell-state-bridge-xvfb`,
`check-dwm-config-fallback`, `check-lyona-toml`, `check-xvfb-runtime`.

Each new test was also run against the code before its fix, and failed there:
focus after a close on the other monitor (input focus went to the root), the
popup's stale focus, the parser's long and unclosed arrays, the bridge's dead
watcher (main and fallback paths), and the rebuild rate (20 rebuilds in 2 s
without the gap, 11 with it).

## The VM (2026-10-09)

| | |
| --- | --- |
| Image | `lyona-2026.10.0-beta.6-x86_64.iso`, SHA-256 `9956f9f10da9bc5d12b88dd9c6edd2ec6a9bced471dd804f3f52686c3144bc32` |
| VM | QEMU with KVM, q35, 4 GB, 4 CPUs, OVMF (UEFI), `-vga std` 1280x800, virtio disk 32 GB, no NVIDIA |
| Install | the image wizard (us, btrfs, no encryption) |
| Branch | `make release` of `f5b1a35` (with the CodeQL and CodeRabbit fixes), installed with `lyona-update apply --file` (no mismatch), then a new login |

- **The 96 desktop checks** of the earlier runs (session, EWMH, tags, window
  functions, popups, the bridge, hot reload of the three files, idle): all
  pass. The invalid-file check now reads "invalid config (line 1: an array is
  never closed) - kept the previous config".
- **#319, the live `hotkeys.toml`:** an unknown key name loads the rest and gives
  one notification, "1 problem, the rest loaded - unknown key 'Retrun'"; a
  missing comma names its line (107); a file cut off inside its array is
  refused, naming the line the array opened (60), and a key past the cut still
  works; the restored file gives no notification.
- **#320, the bridge:** `dwm-xwatch` killed with SIGKILL: the bridge exits, the
  shell starts a new bridge and watcher, and it sees a new window.
- **#318, two monitors** (two RandR monitors on the one screen): closing the
  only window on the other monitor, and one of two there, leaves the focus,
  `_NET_ACTIVE_WINDOW` and the selected monitor where they were; that monitor
  names its remaining window.
- **#320, the shell down:** Super+Shift+Q and Super+R say how to recover and the
  session stays; Super+Shift+R starts the shell again, and it answers.

## Not tested

- Real hardware, two physical outputs, legacy BIOS, NVIDIA.
- The fallback state bridge (no `dwm-xwatch`) in a real session; its tests use
  fake watchers.
