# Whole-repo review, 2026-10-09

Six read-only reviews of `main` at `34c8021` (2026.10.0-beta.6):
- architecture, engineering and security;
- user experience;
- efficiency and documentation.

The previous review, [2026-10-03](2026-10-03-whole-repo-review.md), was of
`27468dd`. Since then there have been 84 commits and about 31,000 changed lines,
so each reviewer covered the whole repo, gave priority to what changed, and said
for each earlier finding whether it is fixed. Each reviewer read `AGENTS.md` and
`SPEC.md` first and verified its own findings. The engineering reviewer
reproduced two of its findings under Xvfb and with the real TOML parser. The
findings marked **(checked)** below were checked again against the code when
this report was written.

Nothing in the repository was changed by the reviews. This report is the record;
fixing is a separate decision.

## Since the last review

Almost everything the 2026-10-03 review asked for is done:

| Area | Fixed | Partly fixed | Still open |
| --- | --- | --- | --- |
| Architecture | 12 | 1 (Quickshell start sequence written twice) | 0 |
| Engineering | 7 | 2 (ISO partial upgrade, TOML array overflow) | 0 |
| Security | 10 | 1 (root gets a password hash) | 1 (timezone lookup before consent) |
| User experience | 10 | 3 (two package paths in Settings, README order, terse `--help`) | 0 |
| Efficiency | 9 | 3 (test sleeps, power watch at 1 Hz, thumbnails) | 0 |
| Documentation | 18 | 2 (TASKS.md and ROADMAP stale again) | 1 (three unreferenced protocol docs) |

The earlier High (passwordless sudo left by the image) and every Medium security
finding are closed. Releases are signed and checked twice, and every download and
AUR build is pinned.

## Tracking

The findings below, and the items carried over from the 2026-10-03 review, are
grouped into twelve issues and four pull requests:

| PR | Issues |
| --- | --- |
| 1. Documentation catch-up | #317 |
| 2. Desktop fixes | #318 (focus on close), #319 (config errors, TOML parser), #320 (state bridge and shell lifecycle), #321 (test hygiene) |
| 3. Bar role and thumbnails | #322 (the panel declares itself the bar), #323 (thumbnails) |
| 4. Install, update and rollback | #324 (rollback scope), #325 (one install layout), #326 (updating from Settings), #327 (updater hardening), #328 (image installer hardening) |

Decided on 2026-10-09: `config.h` is built as an unprivileged identity with
`setpriv` (#327), and a downgrade goes through its own polkit action that names
both versions (#327).

## Fix first

These came up in more than one review, or affect the most common path.

1. **Closing a window on another monitor takes or drops the keyboard focus**
   (engineering Important). **(checked)**
   - **Where:** `dwm.c:4214-4228`, in `unmanage()`.
   - **What:** it picks the next window from the closed window's monitor, `m`,
     and calls `focus(top)`, which makes that monitor the selected one. If `m`
     has no visible window left, it sets the input focus to the root, but leaves
     `selmon->sel` and `_NET_ACTIVE_WINDOW` alone.
   - **Effect:** a terminal, dialog or download window on the other monitor that
     exits on its own either steals the focus from where you are typing, or
     sends your keys nowhere while the focused border stays on your window.
     Reproduced with two Xinerama screens.
   - **History:** older than #280, which changed only how `top` is chosen.
   - **Fix:** when `m != selmon`, update `m->sel` and `arrange(m)` only. When
     `m == selmon`, `focus(top)`, or `focus(NULL)` when there is none.
   - **Test:** extend `test-dwm-activate-xvfb.py`'s two-monitor pass to close a
     window on the unselected monitor.
2. **A rollback restores a mixed-version install** (engineering Important,
   security N5). **(checked)**
   - **Where:** `scripts/lyona-update-root:224-250` (the backup manifest) and the
     restore allowlist (`:462-499`).
   - **What it backs up:** `PREFIX/bin`, `PREFIX/libexec/lyona`, the cursor
     themes, the man page, the session file, the licenses and
     `/etc/lyona-release`.
   - **What it leaves out:** `PREFIX/lib/lyona` (the shared libraries, the
     session scripts, `dwm-xwatch`, `lyona-toml`), `PREFIX/share/lyona/config`
     (the shipped defaults), the GTK and GRUB themes, and the polkit actions.
   - **Effect:** since S12-13 most shell logic lives in `lib/lyona`. A regression
     there can't be rolled back, and after a rollback the old commands source the
     new libraries.
   - **Fix:** back up and restore `lib/lyona` and `share/lyona` whole (remove,
     then extract), the polkit actions and the GTK themes. Add them to the
     allowlist. Add a test that changes `lib/lyona` in an update, rolls back and
     checks the files.
3. **A broken `hotkeys.toml` often loads with no warning** (user experience
   Important, engineering Minor). **(checked)**
   - **Where:** `config.c:361-384`. `hotkeys_doc_usable` accepts a file when any
     one binding is usable, and `tomlparser.c` skips lines it can't read.
   - **Effect:** a file cut off after its first binding, a missing `}` or comma,
     or an unknown key name such as `Retrun`, loads with what survives. Only
     stderr says so. The "invalid config" notification fires only when nothing
     usable is left, which is what the #280 VM check happened to test.
     `docs/src/configuration.md:15-18` promises a notification for a typo.
   - **Related:** an inline array with more than 32 items, such as an `exec`
     with 33 arguments, makes the parser lose the rest of the file. A crafted
     35th element was even read as a rule (`tomlparser.c:156,194`; reproduced).
   - **Fix:** count skipped bindings and unreadable lines, and send one
     notification naming the first. Treat an array that never closes as
     invalid, so a live session keeps its keys. In the parser, skip to the
     matching `]` after `TOML_MAX_ARR` and mark the document truncated.
4. **The install layout has two sources of truth** (architecture Important,
   documentation I5). **(checked)**
   - **What:** `stamp-system` records `LYONA_PREFIX`, `MANPREFIX`, `DATADIR` and
     `XSESSIONSDIR` in `/etc/lyona-release`. Only `lyona-update-root` reads them.
   - **Where the user side differs:** it takes its layout from environment
     defaults: `lyona-install-verify.sh:52-55`, `lyona-update:920-922` and
     `:1174`. `install.sh:1425` passes `DATADIR=/usr/share` explicitly.
   - **The defaults also disagree:** the Makefile uses `PREFIX/share` for any
     other prefix, and the root helper falls back to `/usr/share`.
   - **Effect:** the default layout works because every default happens to
     agree. With any other prefix, root installs one layout while the user side
     backs up and verifies another.
   - **Fix:** one reader of the record, used by `lyona-update` before it sources
     `lyona-install-verify.sh`. Drop the explicit `DATADIR` from `install.sh`,
     and make the root helper's fallback match the Makefile.
   - **Docs:** document the record's fields and the `DATADIR` rule in SPEC
     section 6.
5. **Updating from Settings: a cancelled password prompt reads as a failure,
   and a real failure loses its reason** (user experience Important).
   **(checked)**
   - **Cancelled prompt:** `lyona-update:579-591` falls back to `sudo` whenever
     `pkexec` exits 126 or 127, including when the user cancels. Started from
     Settings there is no terminal, so the progress window shows "The update did
     not finish" and two `sudo` errors about terminals and askpass helpers.
     **Fix:** fall back to `sudo` only when stdin is a terminal. Otherwise say
     "Update cancelled: authorization was not given. Nothing was changed."
   - **Lost reason:** `SystemSettingsPane.qml:295-301` shows the outcome only
     while no update is available. A failed apply leaves one available, so
     Settings shows the "Update to" button again with no reason. **Fix:** show
     the outcome whenever the last action failed.
   - **Stale outcome:** an old "Update complete" has no age limit
     (`UpdateModel.qml:330-332`).
6. **Every update leaves about 25 MB behind for good** (efficiency Medium).
   **(checked)**
   - **What:** `lyona-update` keeps the tarball, its signature bundle and the
     unpacked, built tree in `~/.local/state/lyona/updates`. It removes the tree
     only to re-stage the same version (`:867-868`).
   - **Effect:** at about weekly betas, over 1 GB a year.
   - **Fix:** after `verify_install` succeeds, remove the staging tree and
     tarball, and drop older bundles. A rollback uses the backups, not these
     files.
7. **The beta.6 qualification record and planning docs lag the evidence**
   (documentation Important). **(checked)**
   - **Release notes:** `docs/RELEASE-NOTES-2026.10.0-beta.6.md:133-135` calls
     `cd78abbd...` "this release's image". It was rebuilt twice; the final image
     is `9956f9f1...` (btrfs, 96 of 96 checks; `docs/evidence/280-config-split.md`).
   - **RELEASING.md:129-147** still lists only the 2026-10-03 run. It also
     calls ext4 and a release-to-release update untested, though both ran in the
     beta.6 VM.
   - **TASKS.md** (ARCH-002, ARCH-003) and ROADMAP Phase 7 say the same, and
     ROADMAP's list of published images stops at beta.5.
   - **Fix:** update all four with the VM-only qualifier. Keep "an image built
     by the release workflow" as untested.

## Architecture

**The config.c split is sound.** `config.c` gets dwm's functions and
compile-time facts through a `ConfigEnv` value, hands back keys, rules and a
theme, and never touches X state. Reload stays out of the blocking path:
inotify and a self-pipe feed `select`.

**Prior findings:** 12 fixed, 1 partly fixed.
- **Fixed:** checkout paths at runtime, the ISO source copy, the hand-written
  TOML reader, the command lists, the root-helper lookup, IPC from keybinds,
  protocol header parsing, `DwmState` bypassing `Commands`, the DPI file
  contract, the X-property protocol docs, the dev-override lookup, and Topgrade
  outside the contract.
- **Partly fixed:** starting Quickshell is still written twice, in
  `autostart.sh:58-64` and `dwm-quickshell-controlcenter:410-412`. Stopping is
  shared.

**New findings:**
- **Important:** the install layout has two sources of truth (Fix first 4).
- **Important: the C core now knows which windows Quickshell creates.**
  - **Where:** `dwm.c:389,1911-1922,4501-4520`.
  - **What:** `isaltbar` treats any dock whose class contains `quickshell` as a
    bar. The one-bar-per-monitor rule decides between docks by width, and its
    comment names Quickshell's reload notice.
  - **Effect:** a new full-width dock-type surface from the shell (a banner or
    an OSD) could take the bar's place. That moves shell policy into the event
    loop.
  - **Fix:** have the panel declare its role, with a distinct instance name (as
    the tray does with `alttrayname`) or a `_DWM_BAR` property. Match only that,
    and drop the width rule.
- **Minor: `overridefocus` is a second focus owner that `focus()` never clears**
  (`dwm.c:375,1358,4389-4410`; engineering N5). Clear it in `focus()` when a
  managed client gets the focus.
- **Minor: three IPC wrappers bypass `lyona-shell`.** `dwm-controlcenter`,
  `dwm-keybinds` and `dwm-settings` build the config path inline and call
  targets outside its allowlist. **Fix:** `exec lyona-shell ...`, and add
  `settings` to its allowlist.
- **Minor: `runtime_config_setup` changes dwm's environment.** It `setenv`s
  `XDG_CONFIG_HOME` and `XDG_DATA_HOME`, which every spawned program inherits
  (`config.c:767-798`). That is session policy in the parser. **Fix:** move it
  to `setup()` or the session script.

## Engineering

**Prior findings:** 7 fixed, 2 partly fixed.
- **Fixed:** the sudoers file left behind, `lyona-release` tag reuse,
  `lyona-update-terminal` races, `SHA256SUMS` paths, hot reload when
  `~/.config/lyona` is recreated, and the test gaps.
- **Partly fixed: partial upgrades.** The workflows and the postinstall use
  `-Syu`, but `lyona-install.sh:773` runs `lyona-cachyos add-repos
  --no-upgrade`, which does `pacman -Sy` and then `pacman -S` without `-u`
  (`scripts/lyona-cachyos:242-256`): a partial upgrade of the live medium.
- **Partly fixed: TOML.** Long strings are read whole, but long arrays are not
  (Fix first 3).

**New findings:**
- **Important:** a closed window on another monitor takes the focus (Fix
  first 1).
- **Important:** a rollback restores a mixed-version install (Fix first 2).
- **Minor:** a TOML array over 32 items loses the rest of the file (Fix
  first 3).
- **Minor: the state bridge hangs if `dwm-xwatch` dies.**
  - **Where:** `dwm-quickshell-state:599,612`, and in the fallback at
    `:643,677`.
  - **Cause:** `exec 3<>fifo` keeps a write end open, so `read <&3` never sees
    end of file.
  - **Effect:** after an OOM kill of the watcher, the bridge stays alive and
    blocked, `WatchedProcess` never restarts it, and the panel stops updating.
  - **Fix:** open fd 3 read-only once the writer has started, or check the
    watcher with `kill -0` on a read timeout.
- **Minor:** a stale `overridefocus` lets a popup keep a `FocusIn` that
  `focusin()` would otherwise have corrected (see Architecture).

**Checked and sound:** the `config.c` arena and reload path (a failed reload
keeps the previous keys), `updatemonitorwindows`, `waitingbar`,
`read_install_layout`, the display and health root helpers, and the installer's
status drawing.

**Test gaps:**
- closing a window on the unselected monitor;
- a TOML array of 33 or more items followed by another table;
- a rollback after an update that changed `lib/lyona`;
- a killed `dwm-xwatch`;
- the ISO's sync-without-upgrade path.

## Security

No High or Critical finding. The reviewer found no path from an unprivileged
user or an X client to root without an administrator's approval.

**Prior findings:** 10 fixed, 1 partly addressed, 1 open.
- **Fixed:** the sudoers file, unsigned releases, Topgrade from crates.io, the
  release job's scope, `yay -Syu` (documented), the display helper reading the
  user's Xorg log, System Health's `sudo -n -v`, the Meslo zip, the wallpapers
  clone, and the ISO hostname.
- **Partly addressed:** root gets the user's password. archinstall now gets a
  SHA-512 hash.
- **Open:** the image's timezone lookup sends the IP address to ipinfo.io and
  ipapi.co before asking (`lyona-install.sh:473`).
- **Accepted, unchanged:** the launcher's `sh -c` fallback.

**New findings, all Low:**
- **N1: root compiles the invoking user's `config.h`** (`lyona-update-root:389-408`).
  - **Weakness:** an `#include` of a root-only file leaks its first lines into
    compiler errors, and `#embed` (accepted in C99 mode by GCC 16) copies a
    whole file into the installed, world-readable `dwm`.
  - **Who:** this crosses a boundary only on a multi-user machine, where a
    non-admin asks an admin to approve a "verified update". Decision D-18
    covers `config.h`'s runtime behaviour, not reading files at build time.
  - **Fix:** build as an unprivileged identity over root's copy (`setpriv` or
    `systemd-run -p DynamicUser=yes`), and name `config.h` in the polkit
    message.
- **N2: no anti-rollback in the root helper.** Any older signed release
  installs on the routine "verified update" prompt, including one whose root
  helper had a since-fixed bug. **Fix:** compare with `LYONA_VERSION` in
  `/etc/lyona-release`, and send downgrades through their own polkit action that
  names both versions.
- **N3: the yay-bin AUR build runs while sudo is live.** On the image this is
  under the temporary `NOPASSWD: ALL` rule, and elsewhere under the cached
  timestamp (`install.sh:1396`). Topgrade runs `sudo -k` first; yay does not.
  **Fix:** the same `sudo -k`; on the image, build it before the sudoers rule.
  Narrow that rule to the commands `install.sh` needs.
- **N4: the sudoers file survives a hard power-off** during the 5-30 minute
  `install.sh` step. **Fix:** a `tmpfiles.d` or first-boot removal on the target,
  dropped on success.
- **N5 (informational): defence in depth in the #280 code, reachable only by
  root.**
  - **Restore allowlist:** it accepts anything under `usr/share/icons/`, not
    just the two cursor themes.
  - **`remove-legacy-shared-data`:** its `for id in $(awk ...)` is unquoted,
    and it doesn't check `themes/`, `icons/` or `grub/` for symlinks. **Fix:**
    validate the ids and refuse symlinked or non-root directories.
- **N6 (informational):** any X client can send `_NET_ACTIVE_WINDOW` with
  source 2. That grants nothing X11 doesn't already allow; treat focus stealing
  as policy, not a boundary.

**Working well:** the root-helper trust chain, user files read only through
`runuser ... cat` into root-private copies, signatures checked twice with the
signer fixed in the helper, root-private backups named by id, pinned downloads,
makepkg never as root, and least-privilege CI.

## User experience

**Prior findings:** 10 fixed, 3 partly fixed.
- **Fixed:** the stable channel's "offline", hidden partial failures, mybash
  overwriting files, one-key logout, an unexplained failed install, one-click
  rollback, the install guide's first command, the installer summary, the
  progress bar's "step 10/9" and the cancelled wizard.
- **Partly fixed:**
  - Settings > System still has two package-update paths ("System packages and
    Flatpak", and "System updates" further down).
  - The README's ISO section starts with building one.
  - `lyona-version --help` and `dwm-diagnostics --help` print one line.

**New findings:**
- **Important:** a broken `hotkeys.toml` loads silently (Fix first 3).
- **Important:** a cancelled password prompt reads as a failure (Fix first 5).
- **Minor to Important:** Settings hides why the last update failed (Fix
  first 5).
- **Minor: the docs promise an update notification that doesn't exist.**
  `docs/src/updating.md:24-27` says a `behind` result "surfaces a
  notification". It shows the panel's update icon and the Control Center
  instead.
- **Minor: Super+Shift+Q does nothing when the shell is down.** `lyona-shell`'s
  IPC call fails silently. **Fix:** on failure, notify which key restarts the
  shell (Super+Shift+R) and which quits at once (Super+Ctrl+Shift+Q).
- **Minor:** the README sends image users to build an image before saying they
  can download one.

**Working well:** the image installer, with live step timing, an honest closing
screen and a recovery menu that says what state the disk is in; the updater,
which tells "offline" apart from "nothing published"; rollback with
confirmation; hotkey migrations that move only untouched defaults; and session
keys that confirm.

This reviewer worked from the code. It did not run the desktop, so popup
focus, multi-monitor panels and the Picom fallback were not checked at runtime
here; the #280 VM runs cover them.

## Efficiency

**Prior findings:** 9 fixed, 3 partly fixed.
- **Fixed:** the input watcher at 4 Hz, the state bridge re-reading every
  window, Topgrade from source, the resident NetworkManager python, the
  `busctl monitor` watcher, `WatchedProcess` restarting every 3 s, the
  `run_parent_bound` loop, the audio fallback, and CI cost.
- **Partly fixed:**
  - Tests still sleep: the five slow tests now take 101 s, down from 124 s, and
    the font test has `sleep 5.2` and `sleep 7.5`.
  - The power watch is now 1 Hz, and only while Settings is open.
  - Thumbnails come in bands (see L2).

The state bridge measured 2 processes and about 4 ms for a root-only rebuild,
and 4 processes and about 7 ms for one changed window.

**New findings:**
- **Medium:** about 25 MB left behind per update (Fix first 6).
- **Low: title churn rebuilds the state up to about 17 times a second.** The
  50 ms drain merges a burst but doesn't limit the rate
  (`dwm-quickshell-state:612-617,699-715`). A window that retitles
  continuously costs about 70 processes a second, roughly 10% of a core.
  **Fix:** a minimum 200 ms between rebuilds.
- **Low: a thumbnail copies the whole window.**
  - **Where:** `dwm-window-thumb.c:223-255`.
  - **Cost:** it fetches 33 MB for a 4K window, of which at most 4 rows per
    output row are used.
  - **Fix:** scale on the server with XRender (about 147 KB per window), or
    fetch only the sampled rows.
- **Low:** the installer's 1-second status redraw starts about 9 processes, a
  few ms each. That's acceptable once per install. Optionally, read `tput cols`
  once and merge the pipeline into one `sed` or `awk`.

**Leftover test processes (cleaned up):**
- **What:** seven orphaned `dwm-system-management watch-*` processes from an
  old Xvfb Quickshell test were still running, about 91 MB together. Their
  checkout was already deleted. They were stopped when this report was
  written.
- **Gap:** the `*-xvfb` test teardowns should kill the whole process group,
  since these watchers notice a dead reader only on their next write.

**Working well:**
- **dwm:** `updatemonitorwindows` allocates nothing when idle and writes only on
  change.
- **Reload and state:** reload is inotify-driven, with one resident
  `dwm-xwatch`, and `DwmState` diffs each key.
- **QML timers** are settles or gated.
- **Bounds:** the overview's Repeater is gated on `visible`, Settings > System
  shares one `watch-domains` process, and backups are capped at 5.

## Documentation

**Prior findings:** 18 fixed, 2 partly fixed, 1 open.
- **Fixed:** all the README, book, wizard, channel, lock, `.xinitrc`, naming,
  overview, Fedora-era, anchor, CHANGELOG-heading, status-line and attribution
  items.
- **Partly fixed:** TASKS.md and ROADMAP Phase 7 are current-phase only now,
  but stale again since beta.6 (Fix first 7).
- **Open:** `docs/SESSION-ACTIONS.md`, `AUDIO-PROTOCOL.md` and
  `CONNECTIVITY-PROTOCOL.md` are still referenced from nowhere.

**New findings:**
- **Important: the man page describes stock dwm.** **(checked)** `dwm.1:61-150`
  lists Mod1 bindings, `st` and `dmenu`, and says to customise by recompiling
  `config.h`. lyona binds Super, reads `hotkeys.toml` at run time and installs
  this page for users. **Fix:** point to `~/.config/lyona/hotkeys.toml` and the
  Super+/ viewer, describe the TOML files and hot reload, and drop `st` and
  `dmenu`.
- **Important:** the beta.6 qualification record (Fix first 7).
- **Important: sprint records are stale.**
  - **Sprint 16:** "awaiting review" in `UPSTREAM-SYNC.md` and
    `SYNC-SPRINT-16-REVIEW-FIXES.md:8`, though it merged in `a68efe1`.
  - **S9-01 (thumbnails):** "a maintainer decision is needed", though
    `dwm-window-thumb.c` ships and Picom was made required for it (#244).
- **Important:** the `/etc/lyona-release` fields and the `DATADIR` rule are
  documented only in the changelog (Fix first 4).
- **Minor: `SHELL-STATE-PROTOCOL.md` misses the #280 requests from the shell.**
  It doesn't list a popup's `_NET_ACTIVE_WINDOW` focus request or source-2
  activation, and it doesn't say that the bridge leaves docks out.
  `PATCH-OWNERSHIP.md:38-49` has wording to reuse.
- **Minor:** `CHANGELOG.md:543` links the deleted beta.2 release notes. Use the
  `git show 4581d25^:...` form, as at `:660`.
- **Minor: the `AGENTS.md` repository map is missing entries.** It doesn't
  list `dwm-xwatch.c`, `dwm-window-thumb.c`, `lyona-toml.c`, `tests/`,
  `lightdm/`, `docs/evidence/` or `docs/plans/`.
- **Minor:** `PATCH-OWNERSHIP.md:146-147` says `runtime_config_load()` "returns
  the theme". It fills `*theme` and returns an int (`rtconfig.h:98`).

**Checked and accurate:**
- the version in every place that names it;
- the `DATADIR` and legacy-cleanup text;
- `_DWM_MONITOR_WINDOWS`;
- the close-focus and activation descriptions;
- the `config.c` interface;
- `install.sh --help`;
- every documented `make` target;
- the dependencies page.

**Candidates to retire or merge:**
- the three unreferenced protocol docs;
- the Fedora "Historical" sections of `SETTINGS-PLATFORM.md`;
- release notes, which need one retention rule: `2026.08.0-beta.1` is kept,
  while `2026.10.0-beta.1` and `beta.2` were retired.
