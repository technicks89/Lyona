# Whole-repo review, 2026-10-03

Six read-only reviews of `main` at `27468dd`:
- architecture, engineering and security;
- user experience;
- efficiency and documentation.

Each reviewer read `AGENTS.md` and `SPEC.md` first and verified its own
findings. The findings marked **(checked)** below were checked again against
the code when this report was written.

Nothing was changed by the reviews. This report is the record; fixing is a
separate decision.

## Fix first

These came up in more than one review, or block the most common path.

1. **The live medium can leave passwordless root on the installed system**
   (security High, engineering Critical, UX). **(checked)**
   - **What:** `archiso/airootfs/root/lyona-postinstall.sh` writes
     `/etc/sudoers.d/90-lyona-install` (`USER ALL=(ALL) NOPASSWD: ALL`) and
     removes it only on the line after a successful `install.sh`.
   - **How it stays:** if that step fails and the user picks "Exit to shell"
     in the recovery menu (`lyona-ui.sh`), or interrupts the run, the file is
     left behind. Every later program the user runs then has silent root.
   - **Fix:** `trap 'rm -f -- "$install_sudoers"' EXIT INT TERM` right after
     the file is written. Also remove the file in `_lyona_recover`, and at the
     start of the postinstall for the Retry path.
2. **The default update channel can never see a release, and says "offline"**
   (UX blocking, documentation Important). **(checked)**
   - **What:** `lyona-update` defaults to `stable`, which reads
     `/releases/latest`. Every release is published as a pre-release, so that
     returns 404, and `check` reports "offline: The update server could not be
     reached".
   - **Who it affects:** every ISO and beta install, which is never offered an
     update and points its user at their network.
   - **Fix:** tell "reachable, nothing on this channel" apart from "offline".
     Default to `preview` while the installed version is a pre-release, or
     suggest it. Document `lyona-update set-channel preview`.
3. **Helpers in an installed system use checkout paths** (architecture
   structural). **(checked)**
   - **What:** `scripts/dwm-quickshell-controlcenter` sets
     `repo_dir=$0/..`, which is `/usr` once installed. It then runs
     `/usr/scripts/check-deps.sh` and `cd /usr && ./install.sh`.
     `dwm-system-health` and `dwm-default-apps` have the same pattern.
   - **Effect:** the "Open dependency installer" repair (SPEC 5.9) does nothing
     on every installed system. The tests pass because they run from a
     checkout.
   - **Fix:** resolve helpers through PATH or `lyona_lib`, and defaults
     through `dwm-paths.sh`. Add a staged-`DESTDIR` test that calls these
     actions.
4. **`lyona-release` reuses an existing tag without checking its commit**
   (engineering Important). **(checked)**
   - **What:** when the tag exists, it only prints "already exists", then
     uploads this commit's archive. A local rerun without bumping `VERSION`
     publishes assets that don't match the tag.
   - **The CI side:** the workflow's own check treats any `gh api` error as
     "no tag".
   - **Fix:** compare the tag's commit to `HEAD` and refuse a mismatch. In
     the workflow, treat only a 404 as absent.
5. **Partial upgrades** (engineering Important and Minor). **(checked)**
   `build-iso.yml` (twice) and the ISO postinstall run `pacman -Sy` and then
   install packages, which Arch does not support. Use `-Syu`.

## Architecture

**Structural**
- **Checkout paths at runtime:** item 3 above.
- **Two Quickshell lifecycles:** AGENTS.md names `restart-quickshell` as the
  canonical restart, but it runs `pkill -x quickshell` and relaunches without
  `--path` (`dwm-quickshell-controlcenter:1537-1560`). `autostart.sh:191-299`
  checks the process identity and passes `--path`. Move both onto one
  installed library.
- **The ISO copies the source tree into user data:** it copies the checkout
  to `~/.local/share/lyona` (`lyona-postinstall.sh`). S12-13 defines that
  directory as user seed data. This forces an overlap guard in the Makefile,
  and makes every update back up and restore the whole tree. Use a source
  directory such as `~/.local/src/lyona`.

**Significant**
- **A new hand-written TOML reader** (`lyona-update-indicator`, the
  float-rule check), against D-20. Use `lyona-toml dump`.
- **Three hand-kept lists of required commands that disagree:**
  `check-deps.sh` counts picom, feh and quickshell as required, and
  `dwm-diagnostics` as optional, as SPEC does. Derive both from command tiers
  in `dwm-packages.sh`.
- **The root-helper lookup is copied four times,** each also searching
  `/usr/local` and `/usr` while polkit pins only `@PREFIX@`. Use one function
  in `dwm-trust.sh`.
- **Keybinds call Quickshell IPC directly** from the seeded, never-updated
  `hotkeys.toml`. SUPER+F1 calls `open` while `dwm-controlcenter` calls
  `toggle`. Point keybinds at the installed wrappers.
- **Each QML model parses protocol headers its own way,** with two different
  rules (exactly 3 fields versus at least 3). Use one `core/Protocol.js`.

**Minor**
- **`DwmState.qml` bypasses `Commands.helperCommand`,** so
  `LYONA_DEV_SCRIPTS` never reaches it.
- **`shell.qml` reads another helper's private DPI file.**
- **The dwm-to-shell X-property protocol is undocumented** (`_DWM_SET_LAYOUT`,
  `_DWM_FULLSCREEN_MONITORS`, `DWM_TAG_UPDATE`).
- **`dwm.c` duplicates its developer-override lookup.**
- **Topgrade sits outside the update contract** (SPEC 5.10: Settings > System
  is the one place updates run). Surface it there, or document it as outside
  the contract.

**In good shape:**
- the root gates;
- the `lyona_lib`, `dwm-xdg.sh` and `lyona-toml` conventions;
- QML layering (views launch no processes and build no privileged commands);
- the package map, enforced by tests;
- watcher binding.

## Engineering

**Critical:** the passwordless sudo leftover (Fix first, item 1).

**Important**
- **Tag reuse:** Fix first, item 4.
- **`lyona-update-terminal` assumes the terminal blocks until it closes**
  (reproduced).
  - A terminal that returns at once, such as `warp-terminal`, which is in the
    default list, gnome-terminal or wezterm, gets `not-started`.
  - Its result file is then deleted before the update runs, so the update
    dies.
  - Fix: hold a lock on the result file and wait for it, or refuse terminals
    not known to block.
- **Partial upgrades in `build-iso.yml`:** Fix first, item 5.

**Minor**
- **The release `SHA256SUMS` lists absolute build paths,** so
  `sha256sum -c` on downloaded files fails. Hash by basename.
- **A partial upgrade in the ISO target** (`pacman -Sy`): Fix first, item 5.
- **The TOML parser lets a long string spill into extra keys** (reproduced).
  An inline-table string over 511 characters is truncated, and the scan for
  `,` or `}` then starts inside it: `{ class="<600 x>, isfloating=1" }` yields
  a real `isfloating=1`. Read to the closing quote after truncating.
- **dwm stops hot-reloading** if `~/.config/lyona` is missing at login, or is
  deleted and recreated (`IN_IGNORED` is not handled).
- **Test gaps:**
  - `test-dwm-diagnostics.sh` uses its own `/tmp` workspace, ignoring
    `DWM_TEST_TMP_ROOT`;
  - its `pkg-config` stub accepts any flag;
  - no test covers a non-blocking terminal or a tag at another commit.

**In good shape:**
- the `lyona-update` and root-helper trust chain;
- `install-topgrade`'s bounds and cleanup;
- the update indicator's exit-code handling and atomic settings;
- the promotion and authorize jobs;
- watcher lifetime;
- the C event loop.

## Security

1. **High:** the passwordless sudo leftover (Fix first, item 1).
2. **Medium: releases are unsigned** (D-14). The expected hash comes from the
   same release as the tarball, and root then builds it. A stolen
   `RELEASE_TOKEN` or maintainer account means root on every machine that
   updates. Sign `SHA256SUMS` (minisign or `ssh-keygen -Y sign`), and verify
   against a key built into the root helper.
3. **Medium, accepted (D-28): Topgrade is built from the newest crates.io
   release.** Its build scripts run as the user, and Topgrade calls sudo.
4. **Low: the release job is broader than it needs to be.**
   - **The token:** the admin token is present while `make release-check`
     runs, inside the privileged container. Run the checks first, then
     `lyona-release --skip-checks`.
   - **Permissions:** give the build job `contents: read`.
   - **The image:** pin `archlinux:base-devel` by digest.
5. **Low: `yay -Syu` updates AUR packages from unreviewed HEAD.** It is
   user-run and documented. Say so plainly in `AUR-PACKAGES.md`.
6. **Low:** `dwm-display-setup`, run as root, reads the user's Xorg log
   through the user's `HOME`, which lets the user influence the TearFree
   option.
7. **Low:** System Health elevates with no prompt when `sudo -n -v` succeeds,
   rather than always through polkit.
8. **Low:** `install-mybash` downloads an unpinned Meslo zip as a fallback.
   Reuse `install.sh`'s pinned copy.
9. **Low:** `install.sh` clones the wallpapers unpinned during the sudo
   window.
10. **Low:** the ISO hostname is not validated before it goes into the
    archinstall JSON.
11. **Informational:**
    - root gets the user's password;
    - the ISO's timezone lookup sends the machine's IP to ipapi.co before
      consent;
    - the launcher's fallback runs `Exec` through `sh -c`, which is acceptable
      by design.

**Acceptable:**
- the root helpers' self-checks and input allowlists;
- the update helper's copy, hash and extract into a root-only directory;
- polkit `auth_admin` without keep;
- actions pinned by SHA, inputs passed through `env`, the authorize job;
- QML plain text;
- pinned downloads (CachyOS key, herdr, Meslo, yay-bin, mybash);
- the C hardening flags.

## User experience

1. **Blocking:** the stable channel shows "offline" (Fix first, item 2).
2. **Blocking: the image installer hides partial failures, then reboots.**
   - `gum spin` shows no output.
   - A user who chose the NVIDIA driver can end up on nouveau without being
     told, and CachyOS or kernel failures and `install.sh` warnings go only to
     the log.
   - Collect warnings, show them on the final screen, and pause the reboot.
3. **`install-mybash` overwrites shell config.**
   - If `~/.bashrc.bak` exists, the current `~/.bashrc` is replaced without a
     backup, and `starship.toml` and the fastfetch config are never backed up.
   - It runs on every `install.sh`.
   - Use timestamped backups.
4. **One keystroke ends the session.** Super+Shift+Q quits dwm, and
   Super+Ctrl+Shift+R reboots, both without confirmation, next to keys that
   only restart things. Route both through the power menu's confirmation.
5. **A failed image install** leaves a half-configured system, the sudoers
   file, and no explanation (Fix first, item 1). Say what state the machine is
   in, and what to run.
6. **Rollback runs on one click** (`--yes`), while "Update to" has a
   confirmation step. SPEC requires confirmation for destructive changes.
   **(checked)**
7. **The install guide's first command fails:** `install.md` clones
   `technicks89/dwm-titus.git`, which returns 404, and step 1 runs
   `install.sh` before step 2 clones. The issue link in
   `troubleshooting.md` also returns 404.
8. **Settings > System is hard to follow.**
   - Three update systems share five similar buttons.
   - The lyona release card sits under "Update in a terminal".
   - "Update packages" is not disabled while a PackageKit install runs.
   - "Refresh metadata" is effectively `pacman -Sy`.
   - Group the page as lyona / System packages / Flatpak, and disable the
     terminal buttons while busy.
9. **The installer summary leaves out** the `yay` build, LightDM, replacing
   `~/.bashrc`, the wallpaper download and the gamemode group. It also calls
   `[multilib]` third-party.
10. **The README is stale:** the ISO name is 2026.08, "no prebuilt ISO" is
    wrong, and the keyring is listed under `full`.
11. **The ISO progress bar** reaches "step 10/9".
12. **Cancelling the wizard** gives no hint to run `lyona-install` again.
13. **Topgrade and several helpers are hard to discover,** and their `--help`
    text is terse.

**Works well:**
- the weather errors;
- update-in-terminal's honest results;
- `lyona-update`'s docs and rollback;
- `install.sh --dry-run`;
- display previews with automatic revert;
- the wizard's network guidance and wipe confirmation.

## Efficiency

**High**
1. **The input hotplug watcher polls 4 times a second all session.** It runs
   `sleep 0.25` plus `awk`: about 8 process starts a second, about 0.8% of a
   core (`dwm-settings-input:757`). **(checked)** Read `/proc` with the
   shell's own `read`, and use the 5 s interval `dwm-watchdog.sh` uses.
2. **The state bridge re-queries every window on every event.**
   - It costs about N+10 process starts: 20 ms wall and 27 ms CPU with 5
     windows, and about 50 ms with 20.
   - It also keeps one resident `xprop -spy` per window.
   - A window that retitles every second costs about 3-5% of a core.
   - Fix: re-query only the changed window, or use a small Xlib helper.
3. **Topgrade is built from source on every recommended or full install.**
   That means about 80 MB of toolchain download (500 MB+ left in
   `~/.rustup`), 300 MB of crates, and minutes of compiling with unbounded
   jobs (an out-of-memory risk at 4 GB).
   - The other option is a checksummed release binary, about 5 MB. That
     conflicts with D-28, so it is your call.
   - At minimum, bound `CARGO_BUILD_JOBS` by memory.

**Medium**
4. **A resident python3 process (31 MB)** only to catch NetworkManager's
   `StateChanged`. NetworkModel already tracks connectivity.
5. **The Bluetooth watcher fails at once:**
   `busctl --system monitor org.bluez` returns "BecomeMonitor failed: Access
   denied" for an unprivileged user. **(checked)** Use
   `gdbus monitor --system --dest org.bluez`.
6. **WatchedProcess restarts every 3 s forever.** Watchers whose helper exits
   at once, such as without NetworkManager, spin. Add exponential backoff.
7. **Tests wait on real time.** font 30 s, wallpaper 42 s,
   appearance-inventory 17 s, settings-input 19 s and autostart 16 s, mostly
   fixed sleeps. Make the timeouts overridable, and poll.

**Low**
8. **The redundant `run_parent_bound` backstop loop** costs about 0.6 process
   starts a second per watcher.
9. **The power watch** polls at 4 Hz while the Control Center or Settings is
   open.
10. **The audio fallback** runs a full snapshot per event, with no settle.
11. **Thumbnails** use up to 640 full-row `XGetImage` round trips per window.
12. **CI:** two `pacman -Syu` per push, no package cache, and the docs
    workflow fetches full history.

**Outside the repo:** the live session showed 220 zombie processes parented to
a 12-day-old `sleep infinity`, and two Quickshell instances. That comes from
an older install; check it again once `27468dd` is installed.

**Fine as is:**
- the dwm event loop;
- the three repeating QML timers (all slow or gated);
- network refresh coalescing;
- the update checks' jitter and gap;
- the notification history cap;
- the launcher index released on close;
- the ISO builder's and Topgrade's cleanup.

## Documentation

**Important**
1. **The README says no ISO is published, but `v2026.10.0-beta.1` is,** and
   it names the image `lyona-2026.08.0-x86_64.iso`.
2. **The book never covers installing from the ISO:** `lyona-install`, the
   manual fallback and the NVIDIA choice.
3. **The wizard is described as it used to be.** SPEC and RELEASING describe
   `select_option` menus, "the CTT logo" and "single btrfs root". The code
   uses gum, offers btrfs or ext4 and optional LUKS. The new release notes
   leave out the timezone step.
4. **The stable channel:** Fix first, item 2. Document
   `lyona-update set-channel preview`, and point the README's "Latest release"
   link at `/releases`.
5. **`configuration.md` describes the lock behaviour from before D-13.**
6. **`install.md` describes the shipped `.xinitrc` wrongly;** it only runs
   dwm in a D-Bus session.
7. **Old `dwm-titus` names** remain in `install.md`, `troubleshooting.md`
   and the ISO's `iso_publisher`.
8. **The window overview (Super+O) and the layout switcher** are missing from
   the book.
9. **`TASKS.md` is stale.**
   - It says Sprint 12 has 19 unreviewed items, and Sprints 13 to 15 are
     missing.
   - It still mentions "both ISOs" and "older cards stay on nouveau".
   - It keeps historical checklists, which AGENTS.md forbids.
10. **`ROADMAP.md` contradicts itself and SPEC.** It says "Phase 5 is active"
    though Phases 5 and 6 are complete, it mentions "Standard and NVIDIA
    archiso profiles", and Phase 7 has no status.
11. **`docs/SETTINGS-PLATFORM.md` is still the Fedora-era doc,** including
    Kickstarts and `make check-kickstart`, which does not exist.

**Minor**
- **A wrong layout key:** `getting-started.md` says Floating is
  `Super+Shift+M`; it is `Super+F`.
- **`RELEASING.md`** says "verified to produce a bootable ISO" next to "not
  boot-tested", and its examples still use 2026.08.
- **Anchors that do not resolve:** `#the-system-management-port`, short
  `#s11-01`-style anchors in the evidence files and two QML comments, and a
  retired doc linked without a commit.
- **The README's "Recent Changes"** describes 2026.08.
- **`CHANGELOG.md`'s 2026.10 section** repeats `### Fixed` and `### Changed`
  headings.
- **Stale status lines:** Sprint 6 shows "In progress" in `UPSTREAM-SYNC.md`,
  and `SECURITY.md` names a "stable line" that does not exist.
- **Leftover attribution:** `book.toml` lists the authors as "Chris Titus",
  and `FUNDING.yml` misspells the name.

**Obsolete or unnecessary files:**
- `docs/SESSION-ACTIONS.md`, `AUDIO-PROTOCOL.md` and
  `CONNECTIVITY-PROTOCOL.md` are referenced nowhere;
- `SETTINGS-PLATFORM.md` is Fedora-era;
- `docs/sync-sprints-github.sh` is a script inside `docs/` (now `docs/sprints/sync-sprints-github.sh`, beside the sprint plans);
- `attic/`;
- `lyona-qs-4x.webp` sits at the repository root.

**Accurate as is:**
- `install.sh --help` and its flags;
- the `lyona-cachyos`, `lyona-grub-theme` and `install-topgrade` usage;
- the `lyona-update` docs;
- the README's first-login keys;
- `RELEASING.md`'s CI, token and promotion steps;
- the release notes' artifacts and limitations;
- every documented `make` target except `check-kickstart`;
- the AUR policy.

## Planning records

- **Done:** Sprints 1, 2, 3, 7, 8, 10 and 13.
- **Done except S9-01's decision:** Sprint 9.
- **Code complete, qualification open:** Sprints 4, 5 and 11.
- **Closing out:** Sprint 12.
- **Hardware or live-session checks open:** Sprints 14 and 15.
- **Stale:** Sprint 6, which still says "In progress" though every item is
  done or moved.
