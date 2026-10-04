# Sync Sprint 16 -- Fixes from the 2026-10-03 whole-repo review

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). The findings are in
[`../reviews/2026-10-03-whole-repo-review.md`](../reviews/2026-10-03-whole-repo-review.md).
That report has six reviews: architecture, engineering, security, user
experience, efficiency and documentation.

**Status:** every item implemented 2026-10-03 on branch
`repo-review-and-docs-cleanup`, awaiting review: the **Fix** items first, then
the **Decision** items as decided (D-29 to D-33) and the **Split** items. What
was done, and what could not be tested, is under [Implemented](#implemented)
and [Second round](#second-round-decisions-split-items-and-the-image).

Every finding is mapped to one of three kinds:
- **Fix:** done in this sprint.
- **Decision:** needs the maintainer, because it reverses an earlier decision
  or is a product choice.
- **Split:** a large refactor, worth its own sprint rather than a rushed
  change here.

## Fix first

| ID | Fix | From |
| --- | --- | --- |
| R16-01 | **The live medium never leaves its passwordless sudo rule behind.** Remove `90-lyona-install` on every exit, failure or interrupt. Also remove it at the start of a run (for Retry), and in the recovery menu before offering a shell. Explain the machine's state when the install fails. | security 1, engineering 1, UX 5 |
| R16-02 | **A channel with nothing published is not "offline".** `lyona-update check` reports `unknown`, with "Nothing has been published on the stable channel yet; switch to preview: lyona-update set-channel preview". New installs of a pre-release seed `channel=preview`. | UX 1, documentation 4 |
| R16-03 | **Installed helpers do not use checkout paths.** The Control Center's dependency check and installer, System Health's install-dependencies repair, and `dwm-default-apps`' shipped-defaults fallback use the installed commands and data. A staged-install test runs them. | architecture 1 |
| R16-04 | **`lyona-release` refuses a tag at another commit.** The ISO workflow treats only a 404 as "no tag". | engineering 2 |
| R16-05 | **No partial upgrades.** `-Syu`, not `-Sy`, in `build-iso.yml` and the ISO postinstall. | engineering 4, 6 |

## Engineering

| ID | Fix | From |
| --- | --- | --- |
| R16-06 | `lyona-update-terminal` works with a terminal that returns at once. It waits for the update to start and end, through a lock on the result file. | engineering 3 |
| R16-07 | The release `SHA256SUMS` names files by basename, so `sha256sum -c` works on downloads. | engineering 5 |
| R16-08 | The TOML parser reads a truncated string to its closing quote, so its tail cannot become keys. | engineering 7 |
| R16-09 | dwm keeps hot-reloading after `~/.config/lyona` is created, deleted or recreated. | engineering 8 |
| R16-10 | `test-dwm-diagnostics.sh` uses the managed workspace, and its `pkg-config` stub checks its flag. | engineering 9 |

## Security

| ID | Fix or decision | From |
| --- | --- | --- |
| R16-11 | **Fix:** the ISO workflow runs `release-check` before the admin token is in reach, and the build job's own token is read-only. | security 4 |
| R16-12 | **Fix:** `docs/AUR-PACKAGES.md` says that `yay -Syu` updates AUR packages from their current, unreviewed PKGBUILDs. | security 5 |
| R16-13 | **Fix:** the root display setup reads only the system Xorg logs, not the user's. | security 6 |
| R16-14 | **Fix:** System Health's privileged scan and repair always go through polkit, never a cached `sudo`. | security 7 |
| R16-15 | **Fix:** `install-mybash` uses `install.sh`'s pinned, checksummed Meslo font, or skips it. | security 8 |
| R16-16 | **Fix:** the wallpaper clone is pinned to a commit. | security 9 |
| R16-17 | **Fix:** the ISO hostname is validated (RFC 1123). | security 10 |
| R16-18 | **Decided (D-29):** root gets no password on image installs and is locked; the user administers with `sudo`. | security 11 |
| R16-19 | **Decided (D-30):** the timezone is detected (several providers) and the user answers yes or no; otherwise a searchable list. | security 11 |
| R16-20 | **Decided (D-31):** releases are signed (Sigstore build-provenance attestations), and `lyona-update` checks the signature. | security 2 |
| R16-21 | **Decided (D-32):** Topgrade stays `cargo install topgrade`, the newest release (no change). | security 3, efficiency 3 |

## User experience

| ID | Fix | From |
| --- | --- | --- |
| R16-22 | The image installer collects warnings, shows them on its final screen, and waits instead of rebooting when there are any. | UX 2 |
| R16-23 | `install-mybash` keeps a timestamped backup of every file it replaces. | UX 3 |
| R16-24 | Quitting dwm and rebooting from the keyboard go through the power menu's confirmation (new installs; existing `hotkeys.toml` files are not changed). | UX 4 |
| R16-25 | Rolling back from Settings asks for confirmation, like updating does. | UX 6 |
| R16-26 | The install guide clones `technicks89/Lyona` before running anything, and the issue link works. | UX 7 |
| R16-27 | Settings > System groups lyona, system packages and Flatpak under their own headings. The terminal update buttons are disabled while a PackageKit operation runs. | UX 8 |
| R16-28 | The installer summary lists every change it makes (the `yay` build, LightDM, `~/.bashrc`, wallpapers, the `gamemode` group), and does not call `multilib` third-party. | UX 9 |
| R16-29 | The ISO progress bar counts its steps correctly. | UX 11 |
| R16-30 | Cancelling the ISO wizard says how to start again. | UX 12 |
| R16-31 | The update helpers' `--help` describes each command, and the float-rule hint says "inside the `rules` array". | UX 13 |

## Efficiency

| ID | Fix or split | From |
| --- | --- | --- |
| R16-32 | **Fix:** the input hotplug watcher checks its parent every 5 s, with builtins and one `sleep`, not `awk` and `sleep` 4 times a second. | efficiency 1 |
| R16-33 | **Fix:** the Topgrade build's parallel jobs are bounded by available memory. | efficiency 3 |
| R16-34 | **Fix:** the update indicator reacts to NetworkModel's connectivity, not a resident Python watcher. | efficiency 4 |
| R16-35 | **Fix:** the Bluetooth watcher subscribes with `gdbus monitor`, which works without privileges. | efficiency 5 |
| R16-36 | **Fix:** `WatchedProcess` backs off exponentially when its helper keeps exiting. | efficiency 6 |
| R16-37 | **Fix:** the power watch checks its children each second with builtins, not with `awk` 4 times a second. (POSIX `sh` cannot wait for whichever of two children ends first.) | efficiency 9 |
| R16-38 | **Fix:** the audio fallback settles bursts of events. | efficiency 10 |
| R16-39 | **Fix:** CI runs one package sync per job, and the docs workflow a shallow fetch. | efficiency 12 |
| R16-40 | **Done:** one `dwm-xwatch` watches every window, and only a changed window is read again. | efficiency 2 |
| R16-41 | **Done:** thumbnails fetch bands of rows, a few round trips per window. | efficiency 11 |
| R16-42 | **Done:** the slowest tests wait less, where the wait was not what they test. | efficiency 7 |
| R16-43 | **Fix:** the redundant `run_parent_bound` backstop loop is skipped when pdeathsig already binds the watcher. | efficiency 8 |

## Architecture

| ID | Fix or split | From |
| --- | --- | --- |
| R16-44 | **Fix:** the update indicator reads `window-rules.toml` with `lyona-toml` (D-20). | architecture 4 |
| R16-45 | **Fix:** `check-deps.sh` and `dwm-diagnostics` agree on which commands are required (SPEC 5.3, 5.8). | architecture 5 |
| R16-46 | **Fix:** one root-helper lookup, in `dwm-trust.sh`, searching only the installed prefix. | architecture 6 |
| R16-47 | **Fix:** default keybinds call the installed wrappers, not Quickshell IPC directly. | architecture 7 |
| R16-48 | **Fix:** `DwmState.qml` and the other models run helpers through `Commands`. | architecture 9 |
| R16-49 | **Fix:** `restart-quickshell` uses the same identity-checked lifecycle as autostart. | architecture 2 |
| R16-50 | **Fix:** dwm's developer-override lookup is one function. | architecture 12 |
| R16-51 | **Fix:** the dwm-to-shell X properties and the DPI state file are documented as protocols. | architecture 10, 11 |
| R16-52 | **Fix:** SPEC says Topgrade sits outside the Settings update contract. | architecture 13 |
| R16-53 | **Done:** one header rule, `core/Protocol.js`, for every QML model. | architecture 8 |
| R16-54 | **Done:** the image puts the checkout in `~/.local/src/lyona`. | architecture 3 |

## Documentation

| ID | Fix | From |
| --- | --- | --- |
| R16-55 | **The README:** the published ISO and its name, the keyring's profile, "Recent Changes", and the "Latest release" link. | documentation 1, 15; UX 10 |
| R16-56 | **The book covers installing from the ISO,** with the wizard as it is now. SPEC, `RELEASING.md` and the release notes describe it accurately (gum, btrfs or ext4, optional LUKS, timezone). | documentation 2, 3 |
| R16-57 | **The update docs explain the channels** and `set-channel preview`. | documentation 4 |
| R16-58 | **`configuration.md`:** the lock and DPMS defaults (D-13). **`install.md`:** what `.xinitrc` does. | documentation 5, 6 |
| R16-59 | **No old `dwm-titus` names:** `install.md`, `troubleshooting.md` and the ISO's `iso_publisher`. | documentation 7 |
| R16-60 | **The book covers** the window overview (Super+O) and the layout switcher. | documentation 8 |
| R16-61 | **The roadmap files:** `TASKS.md` reduced to the active work; `ROADMAP.md`'s phase status and image line corrected. | documentation 9, 10 |
| R16-62 | **`SETTINGS-PLATFORM.md`'s Fedora-era parts** are marked historical. | documentation 11 |
| R16-63 | **Smaller corrections:** the Floating layout key, `RELEASING.md`'s stale lines, the broken anchors, `SECURITY.md`'s support line, and the duplicate headings in `CHANGELOG.md`'s 2026.10 section. | documentation 12-17 |
| R16-64 | **Decided (D-33):** technicks89, in `book.toml` and `FUNDING.yml`. | documentation |

## Implemented

Each Fix, with what changed and the test that checks it (new tests are marked
*new*; every one fails against the code before the fix unless noted).

- **R16-01:** `lyona-ui.sh` removes `LYONA_CLEANUP_FILES` on exit, interrupt and
  Retry, and the recovery menu says what state the machine is in. *new*
  `test-live-medium-cleanup.sh`.
- **R16-02:** `lyona-update check` reports `unknown` for an empty channel (only
  a 404 or an empty list), with the `set-channel preview` hint on stable; a
  pre-release install seeds `preview`. `test-lyona-update.sh`.
- **R16-03:** the Control Center, System Health and `dwm-default-apps` use the
  installed `check-deps.sh`, package library and shipped config. *new*
  `test-installed-helper-paths.sh`.
- **R16-04:** `lyona-release` refuses a tag at another commit; the workflow's
  lookup fails on anything but "no such tag". `test-release-helper.sh`,
  `test-release-workflows.sh`.
- **R16-05, R16-39:** `-Syu` where `-Sy` was, and one sync per CI job; the docs
  workflow fetches shallow. `check-archiso`, `test-release-workflows.sh`.
- **R16-06:** `lyona-update-terminal` holds a lock on its result file while the
  update runs, and waits for it, so a terminal that returns at once (wezterm,
  gnome-terminal) is waited for. `test-lyona-update-terminal.sh`.
- **R16-07:** `SHA256SUMS` lists file names; `sha256sum -c` works on the
  downloads. `test-release-helper.sh`.
- **R16-08:** the TOML parser reads a truncated string to its closing quote.
  `test-tomlparser.c`.
- **R16-09:** dwm watches the config home too, so a `lyona` directory created
  or recreated after login is watched and loaded. `test-dwm-reload-theme-xvfb.py`.
- **R16-10:** `test-dwm-diagnostics.sh` uses the managed workspace, and its
  `pkg-config` stub accepts only `--exists`.
- **R16-11:** the build job's token is read-only; `release-check` runs before
  `RELEASE_TOKEN` is used, and `lyona-release` skips it. `test-release-workflows.sh`.
- **R16-12:** `AUR-PACKAGES.md` says what an AUR update builds.
- **R16-13:** as root, the display setup reads only `/var/log/Xorg.N.log`.
  `test-dwm-display-setup.sh`.
- **R16-14:** System Health elevates through polkit only. `test-system-health.sh`.
- **R16-15, R16-16:** `install-mybash` installs `install.sh`'s pinned Meslo (or
  skips a mismatch); the wallpapers are fetched at a pinned commit. *new*
  `test-download-pins.sh`.
- **R16-17:** the ISO hostname is checked against RFC 1123.
  `test-iso-install-credentials.sh`.
- **R16-22, R16-29, R16-30:** the postinstall records every fallback and
  `install.sh`'s warnings, and the last screen lists them and waits for Enter;
  ten steps, counted right; a cancel says to run `lyona-install` again. *new*
  `test-iso-install-warnings.sh`.
- **R16-23:** `install-mybash` keeps every file it replaces as
  `FILE.bak.TIME`, and leaves links already in place. `test-install-mybash.sh`.
- **R16-24:** Super+Shift+Q and Super+Ctrl+Shift+R open the power menu at the
  Logout or Reboot confirmation (`power confirm ACTION`); the direct quit moved
  to Super+Ctrl+Shift+Q, as the way out when the shell is not running. New
  installs only: an existing `hotkeys.toml` is not changed.
  `test-quickshell-session-actions.sh`, `test-xvfb-runtime.sh`,
  `test-quickshell-settings-xvfb.sh`.
- **R16-25:** "Roll back" asks first. `test-quickshell-update-model.sh`.
- **R16-26, R16-59:** the install guide clones `technicks89/Lyona` first; the
  issue link and the ISO's publisher name it.
- **R16-27:** Settings > System has a **lyona** heading and a **System packages
  and Flatpak** heading; Update packages waits while PackageKit runs.
  `test-quickshell-update-model.sh`.
- **R16-28:** the installer summary lists the yay build, mybash, the
  wallpapers, the display manager and the gamemode group, and calls
  `[multilib]` Arch's. *new* `test-install-summary.sh`.
- **R16-31:** the update helpers' `--help` describes each command; the float
  hint says where the line goes. `test-lyona-update-terminal.sh`.
- **R16-32:** `test-settings-input.sh`.
- **R16-33:** the Topgrade build runs one job per 2 GiB of available memory
  (`CARGO_BUILD_JOBS` kept). `test-install-topgrade.sh`.
- **R16-34:** the indicator follows `NetworkModel.online` (the snapshot's new
  `network-state` record); `watch-network` and its python3 are gone. The state
  found at login does not trigger a check. `test-lyona-update-indicator.sh`,
  `test-quickshell-update-indicator-xvfb.sh`.
- **R16-35:** the Bluetooth watcher uses `gdbus monitor`, checked to receive
  BlueZ-shaped signals unprivileged. `test-quickshell-connectivity.sh`.
- **R16-36:** `WatchedProcess` doubles its restart delay, to 5 minutes, after
  each quick exit. `test-quickshell-watched-process-xvfb.sh`.
- **R16-37:** `test-quickshell-power-backend.sh`.
- **R16-38:** the audio fallback snapshots once a burst settles, and again if a
  change came during one. `test-quickshell-audio.sh`.
- **R16-43:** a helper Quickshell started bound (`LYONA_PARENT_BOUND_SELF` is
  its own PID) skips the backstop loop. `test-dwm-watchdog.py`.
- **R16-44:** the float-rule check reads `window-rules.toml` through
  `lyona-toml`. `test-lyona-update-indicator.sh`.
- **R16-45:** `check-deps.sh` and `dwm-diagnostics` take their tiers from
  `dwm_command_tier`. `test-dwm-diagnostics.sh`.
- **R16-46:** `trusted_root_helper_path` in `dwm-trust.sh`, the one lookup.
  `test-shell-contracts.sh`.
- **R16-47:** keybinds call `lyona-shell TARGET ACTION`. *new* `test-lyona-shell.sh`.
- **R16-48:** `DwmState.qml` uses `Commands.stateHelperCommand`.
  `test-installed-helper-paths.sh`.
- **R16-49:** `dwm-quickshell-lifecycle.sh`, shared by autostart and
  `restart-quickshell`. `test-quickshell-controlcenter.sh`.
- **R16-50:** `dev_override()` in `dwm.c`. `test-dwm-reload-theme-xvfb.py`.
- **R16-51:** `docs/SHELL-STATE-PROTOCOL.md`, linked from SPEC 5.1.
- **R16-52:** SPEC 5.10 puts Topgrade outside the update contract.
- **R16-55 to R16-63:** the README, the book (an image install section, the
  window overview, the layout row, channels, lock defaults, `.xinitrc`),
  SPEC, `RELEASING.md`, the release notes, the roadmap files,
  `SETTINGS-PLATFORM.md`, `SECURITY.md`, 17 broken anchors, and the 2026.10
  CHANGELOG headings.

Found along the way: the README and SECURITY now point at pre-releases. The
only published release is `v2026.08.0-beta.1`; `2026.10.0-beta.1` was
published and then withdrawn, as it could not reach a desktop (below).

## Second round: decisions, split items and the image

- **The image did not reach a desktop.** Booted in a VM (`qemu:///session`,
  UEFI), the `2026.10.0-beta.1` image installs Arch, but `install.sh` stops at
  the LightDM step: the greeter theme is generated through `lyona-toml`, which
  a fresh checkout has not built yet. The system then boots to LightDM, and
  logging in fails ("Failed to start session"). `install.sh` now deploys the
  LightDM config after `make`, and `lightdm/Makefile` says what is missing if
  run first. `test-lightdm-config.sh` fails on the old order.
- **An image built from this branch, installed in the same VM, reaches the
  desktop:** LightDM, then dwm and the panel; the launcher opens on Super+R
  through `lyona-shell`, and Super+Shift+Q opens the power menu at Logout's
  confirmation; root is locked (`passwd -S root`: `L`); the closing screen
  listed the install's warnings and waited for Enter. It also found three more
  faults, fixed after it (and so not yet run in an image):
  - `install.sh --non-interactive` hung building `yay`: `makepkg` waited on
    pacman's prompt behind the spinner. It now passes `--noconfirm`
    (`test-install-summary.sh`).
  - `mkarchiso` gives files not in `file_permissions` mode 644, so the
    embedded checkout's scripts lost their executable bit and the wizard took
    the CachyOS helper for missing. The builder lists every executable file
    (`test-arch-iso-builder.sh`).
  - The closing screen said to remove the medium before rebooting, which
    crashed the reboot while the live system still ran from it. It now says to
    remove it only if the installer starts again.
- **A second image, with those three fixes, installed cleanly through to the
  desktop** with `yay` 13.0.1 and Topgrade 17.12.3, and detected the timezone
  for a yes/no answer once `ipinfo.io` was reachable. With the scripts
  executable again, the wizard's CachyOS step ran, and three more faults
  showed, fixed after it:
  - The first package update failed ("unknown trust"): the new system listed
    the CachyOS repositories before the step that trusts their key. That step
    now runs first (`test-iso-install-warnings.sh`).
  - Steam's `vulkan-driver` was left to pacman, which with `--noconfirm` took
    `mesa-git` from CachyOS and conflicted with `mesa`. The drivers for the
    machine's GPUs are installed first (`dwm_vulkan_driver_packages`,
    `test-arch-packages.sh`).
  - Gear Lever's Flatpak install fails inside the installer's chroot; it now
    runs at the first login, until it succeeds
    (`test-gearlever-first-login.sh`). From a real login it installed.
- **A third image, with those three fixes, installed without a hand-made
  fix.** The first update and the gaming packages succeeded. Gear Lever still
  failed during the install: `systemd-detect-virt --chroot` does not see
  `arch-chroot`, which gives the chroot its own PID namespace. install.sh now
  also leaves it for the first login when `LYONA_SOURCE=iso`. That change was
  made after this image, so it is untested in an image. With the marker made
  by hand on the installed system, the next login installed Gear Lever in
  the background and removed the marker.
- **The timezone lookup failed in the VM too:** `ipapi.co` answered 429. See
  R16-19.
- **R16-18 (D-29):** no `root_enc_password` in the archinstall credentials,
  and the postinstall runs `passwd -l root`. `test-iso-install-credentials.sh`.
- **R16-19 (D-30):** `detect_timezone` tries `ipinfo.io`, then `ipapi.co`,
  offers only a zone the medium knows, and asks yes or no; on no, or with no
  answer, `gum filter` over every zone replaces `tzselect`.
  `test-iso-install-warnings.sh`.
- **R16-20 (D-31):** `build-iso.yml` attests the ISO and the source archive
  (`actions/attest-build-provenance`, pinned), with only the `id-token` and
  `attestations` permissions it needs, before it publishes anything.
  `lyona-release --bundle` publishes the bundle as
  `lyona-VERSION.sigstore.json`, after checking that it names the digests of
  the files it uploads. `lyona-update` checks it with `cosign` against
  `build-iso.yml` on `main` before unpacking, from `2026.10.0-beta.2` (the
  first signed release) on; `--bundle FILE` gives it for `--file`, and
  `--sha256` (offline) skips it. GitHub serves attestations snappy-compressed
  and `gh attestation verify` needs a login, hence the published bundle and
  `cosign`. Checked against a real Sigstore bundle (GitHub CLI's): the right
  file verified, and a tampered file, another workflow or another repository
  was refused. `cosign` cannot verify offline, even with a cached trust root.
  `test-lyona-update.sh`, `test-release-helper.sh`,
  `test-release-workflows.sh`.
- **R16-40:** `dwm-xwatch.c` (libX11 only, installed in `PREFIX/lib/lyona`)
  prints `root PROP` and `window 0xID`; `dwm-quickshell-state watch` caches
  each window and reads only the changed ones, falling back to the per-window
  spies without it. With 10 windows: 1 resident process instead of 11, and
  0.26 s of CPU for 10 title changes instead of 0.36 s; the first block is
  byte-identical to a full `state`. `test-quickshell-state-bridge-xvfb.py`.
- **R16-41:** byte-identical previews, checked against the old binary, also
  with many small bands.
- **R16-42:** font 30.3 s to 27.3 s (an overridable watchdog lock wait),
  wallpaper 41.5 s to 30.6 s (stubs that stalled the wrong `setsid` call or
  slept longer than needed, and 1 s previews), appearance inventory 16.9 s to
  10.9 s (an overridable scan bound). Autostart's waits are the timeouts it
  tests, and settings input's are real work.
- **R16-53:** `core/Protocol.js`: name and major must match, the minor is any
  number. Every model uses it; system management keeps its known minors and
  extension fields. `tst_protocol.qml`, and a guard in
  `test-quickshell-design-system.sh` against hand-written header checks.
- **R16-54:** the postinstall copies the checkout to `~/.local/src/lyona`.
  Existing installs keep theirs.
- **R16-47 follow-up:** `lyona-shell` opens the launcher, overview, Control
  Center and power menu; the default keys call it.

## Verification

- Each fix comes with a test where behaviour changed, and the existing tests
  still pass.
- The full suite passes at the end.
- What could not be tested (the live medium, a real login, real hardware) is
  listed here when the sprint is done.
