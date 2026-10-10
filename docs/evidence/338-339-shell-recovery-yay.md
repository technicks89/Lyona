# #338 and #339: shell recovery and one yay installer, validated

Branch `shell-recovery-yay-338-339`, uncommitted, on `main` at `aabc997`
(PR 4 of 4 from the 2026-10-10 review,
`docs/reviews/2026-10-10-whole-repo-review.md`).

## What changed

- `scripts/lyona-shell` (#338): when the IPC call fails and the shell does not
  answer its tray probe, it starts the shell again through
  `dwm-quickshell-controlcenter action restart-quickshell`, waits for it
  (bounded, `LYONA_SHELL_RESTART_WAIT` seconds, 8 by default) and asks again,
  so the key does what it was pressed for. A call the running shell refuses is
  passed through as its own error, with no restart. When the shell cannot
  start, the message is printed to stderr and shown with `xmessage`, which
  needs only X; the first version used `notify-send`, whose only server is the
  shell. The chords it names come from the user's `hotkeys.toml` through
  `lyona-toml` (the binding running `restart-quickshell`, and the `quit`
  binding), falling back to the defaults.
- `scripts/dwm-packages.sh`: `xorg-xmessage` in the desktop profile;
  `aur-build` (`base-devel`, `git`), what makepkg needs. `docs/src/dependencies.md`
  says what each is for.
- `scripts/install-yay` (#339, new, installed as a command): the one place yay
  is built and installed, as `install-topgrade` is for Topgrade. It closes the
  sudo timestamp, builds `yay-bin` at its pin through `dwm-aur.sh` as the user
  and installs the package with pacman; `--build-only DIR` for the image,
  `--print-plan` for the summary. Non-interactive
  (`INSTALL_YAY_NON_INTERACTIVE=1`): `--noconfirm`, `sudo -n`, and where sudo
  needs a password it installs nothing, says so and exits 3 before building.
- `install.sh`: `ensure_yay_installed` runs `install-yay`, and warns in the
  closing list when a non-interactive run skipped yay (exit 3); the summary's
  AUR line comes from `--print-plan` and says, non-interactively, that yay is
  installed only where sudo needs no password; `--skip-yay` stays, documented
  as the image installer's way of saying it built yay itself before its
  temporary sudo rule existed.
- `archiso/airootfs/root/lyona-postinstall.sh`: `install_yay` builds through
  `install-yay --build-only`; the AUR build prerequisites, there and for the
  legacy NVIDIA driver, come from the map's `aur-build` profile.
- Tests: `tests/test-lyona-shell.sh` covers the restart and retry, a refused
  call with the shell up (no restart), a shell that cannot start (the
  `xmessage` hint, never `notify-send`), and rebound chords read from a user
  `hotkeys.toml`; `make check-lyona-shell` builds `lyona-toml` first.
  `tests/test-install-yay.sh` (`make check-install-yay`) runs the script
  against stub git, makepkg and sudo: the plan line, the interactive install,
  the non-interactive install with and without passwordless sudo, an installed
  yay, a failed build, `--build-only`, and the two callers' wiring.
  `tests/test-dwm-aur.sh`, `tests/test-aur-policy.sh` and
  `tests/test-install-summary.sh` follow the move.
- Docs: `docs/src/install.md`, `docs/src/troubleshooting.md`,
  `docs/AUR-PACKAGES.md`, `CHANGELOG.md`.

## Tests

Run through `scripts/run-tests`, each on its own:

| Check | Result |
| --- | --- |
| `make check-lyona-shell` | PASS |
| `make check-install-yay` | PASS |
| `make check-aur-policy` (runs `test-dwm-aur.sh` too) | PASS |
| `make check-topgrade-install` (the postinstall's export list and ordering) | PASS |
| `make check-install-summary` | PASS (this host has yay, so the plan's "already installed" branch ran and the non-interactive wording was checked in the source) |
| `make check-arch-packages` (`xorg-xmessage` documented) | PASS |
| `make check-install-manifest` (`install-yay` installed) | PASS |
| `make check-installed-helper-paths` | PASS |
| `make check-shell-contracts`, `make check-ci-parity`, `make check-iso-install-recovery` | PASS |
| `shellcheck -S warning`, `shfmt -d` on the changed scripts and tests | clean (the `SC2034` note on `LYONA_STEP_EXPECT` in the postinstall is pre-existing) |

## Not tested

- No real or nested X11 session: the restart-and-retry was exercised with a
  stub `quickshell` and Control Center, not against a stopped Quickshell; the
  `xmessage` window was not seen.
- No VM: the image's `install_yay` through `install-yay --build-only` was not
  run; `tests/test-install-yay.sh` pins its shape, and
  `check-topgrade-install` its place before the sudoers rule.
- `install.sh` was not run on a system without yay; the summary wording for
  that case is checked in the source only on this host.
