# Changelog

All notable project changes are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses calendar
versions (`YYYY.MM`, or `YYYY.MM.PATCH` for a second release in the same
month) from `config.mk`. A pre-release appends `-alpha.N`, `-beta.N` or
`-rc.N`.

## [Unreleased]

### Fixed

- A `recommended` install now includes GNOME Keyring, so a password login through the display manager unlocks the
  login keyring (Sync Sprint 15 S15-01, from upstream `#365`). It used to come only with the `full` profile, and
  nothing reported it missing. Diagnostics and System Health now flag a missing `gnome-keyring`, and `lyona-update`
  warns about it. On an existing install, add it with `sudo pacman -S --needed gnome-keyring`, then log out and back
  in.
- Check every NVIDIA display device before choosing a driver; mixed driver
  branches keep nouveau.
- Clean up legacy NVIDIA packages newly installed by a failed CachyOS
  transaction before trying the AUR, preserving pre-existing packages.
- The shell's watchers no longer leave an `xprop -spy` or `inotifywait` running after Quickshell crashes or is killed,
  however busy the machine (Sync Sprint 13 S13-01). Each one is now bound to its watcher by the kernel, so it ends the
  moment the watcher does. This also stops the watcher-lifetime test failing under load.
- `lyona-update` can install a published release again (Sync Sprint 12 S12-19). The release asset was a runtime bundle
  with no `Makefile`, which both the updater and its root helper build from, so every release install failed at the
  first `make`. The asset is now a reproducible source archive of the repository. `make release-check` builds it from
  the extracted archive alone, and the update tests install the real archive. The cursor themes' symlinks keep their
  targets in the archive, and every file is 0644 or 0755.
- Preserve existing CachyOS signing keys when key verification fails, and stop
  on keyring listing errors.
- Remove partial web-app icon downloads and create the app without an icon
  when curl or wget fails.
- Preserve legacy data trees when their directory overlaps the source checkout,
  and include them in live-install backups so rollback can restore them.
- Run live-install verification cleanup and chained EXIT handlers once on
  interruption, preserving signal exit statuses and caller-owned signal traps.

### Changed

- The AUR policy is now "limit the AUR to where it is needed", not "no AUR" (decision D-27). Packages still come from
  the official repositories, or the CachyOS repository, whenever one can do the job. Each AUR use is listed in
  `docs/AUR-PACKAGES.md` and allowed by the guard, which fails on any other. The uses today are the `yay` helper, the
  legacy NVIDIA drivers, and the user's own `yay -Syu` from Settings. The guard is now `make check-aur-policy`
  (`tests/test-aur-policy.sh`); `make check-no-aur` still runs it.
- Smaller hardening (Sync Sprint 12 S12-18):
  - **Display setup:** a mode timing the X server reports is checked before it is written into the system Xorg
    configuration. A mode with extra tokens or a non-numeric field is refused.
  - **Notification history:** it is private, 0600 in a 0700 `~/.cache/lyona`, even when an older install left the
    directory world-readable.
  - **`webapp-create`:** it quotes the URL in `Exec=` as the desktop-entry spec requires, and its `wget` fallback
    fetches icons over HTTPS only.
  - **`install-mybash`:** it checks out a pinned, reviewed `mybash` commit instead of the latest one.
  - **`lyona-cachyos`:** it receives the CachyOS signing key by its full fingerprint, and accepts it only when the
    keyring shows exactly that one key.
- The live medium's installer now recommends the proprietary NVIDIA driver when it detects an NVIDIA GPU the current
  driver supports, with nouveau as the alternative. It is one image for every GPU (decision D-17a; Sync Sprint 12
  S12-17).
  - An older NVIDIA card keeps nouveau without a prompt.
  - Dismissing the driver prompt aborts the wizard, as every other prompt does. The proprietary driver is installed
    only when it is chosen.
  - The install summary says which driver each machine gets, and why.
- AGENTS.md, SPEC.md and `docs/RELEASING.md` now match the code (Sync Sprint 12 S12-17):
  - one image for every GPU;
  - per-screen panels;
  - Arch package names in SPEC 5.8, which still listed Fedora's;
  - citations of retired design documents now name a commit that holds them, and a contract test keeps them
    resolvable.
- `dwm-system-management` is now a short launcher over the `lyona_system_management` Python package, installed to
  `PREFIX/lib/lyona/python` (Sync Sprint 12 S12-16).
  - The package is 14 modules, one per domain, instead of one 10,379-line file. Behaviour is unchanged.
  - The package's docstring now says what the helper does, including the updates and settings changes it makes. The
    old one called it read-only.
  - Installs verify each module, and report one the release no longer ships. The pre-update backup includes the
    package.
- The shell's `settings` IPC target now has only the commands the desktop uses: `open`, `close`, `toggle`, `refresh`,
  `select` and `status`. The test suite's 159 getters and drivers moved to a `settingsTest` target, which the shell
  creates only when `LYONA_SHELL_TEST_IPC=1` (Sync Sprint 12 S12-16). `shell.qml` is 714 lines shorter.
- Privileged-helper consistency, the package map, and lint coverage (Sync Sprint 12 S12-15).
  - **System Health's privileged scan and repairs** go through a new root-owned helper,
    `libexec/lyona/dwm-system-health-root`, under its own polkit action (`com.lyona.system-health.manage`) with a
    specific prompt and an `exec.path` pin, like the display and update helpers. Before, `dwm-system-health` ran
    `pkexec` on itself from `/usr/bin`, with the generic prompt and no action of its own.
    - The helper accepts only `scan-system`, and `repair-system` with one of the listed repairs, a service verb
      (`start`, `stop`, `restart`, `enable`, `disable`) and a well-formed `.service` name. It runs the installed
      `dwm-system-health` with a clean environment.
    - The passwordless-`sudo` path is unchanged.
  - **Package names** that installers wrote out by hand now come from the shared map in `scripts/dwm-packages.sh`:
    - the live medium's postinstall: microcode, the NVIDIA, AMD and Intel GPU drivers, NetworkManager, and the
      QEMU/KVM guest tools;
    - `install-mybash` and `xscreensaver-setup.sh`.

    The same packages are installed as before, apart from NVIDIA (below). `tests/test-arch-iso-builder.sh` fails if
    the postinstall names one of them directly again.
  - **The live medium's NVIDIA option installs `nvidia-open`** (or `nvidia-open-dkms` with any other kernel). Arch
    dropped `nvidia` and `nvidia-dkms`, so the option had been failing with "target not found"; `make check-no-aur`
    caught it once the names were in the map.
    - The open modules need a Turing (GTX 16xx, RTX 20xx) or newer GPU, and the installer's driver prompt now says
      so. Older cards need the AUR-only `nvidia-580xx` and stay on nouveau.
    - The postinstall checks the card's PCI device ID first. On a GTX 10xx or older card it installs nothing and says
      why, so the card keeps nouveau: `nvidia-utils` blacklists nouveau, so the old behaviour left those cards with
      no working driver. Sprint 14 adds their drivers.
- `protonrestart` no longer kills unrelated programs that share a name with a Proton process (`reaper` is also
  REAPER, the audio workstation). It kills those names only when the executable is inside a Steam, Proton or Lutris
  install.
  - **`make check-shell` and `make check-format`** now lint every shell script under `scripts/`, found by its
    shebang. The hand-kept lists had missed 13, including the privileged `dwm-settings-display-root`. Those 13 now
    pass: five were reformatted, whitespace only, and `webapp-create` no longer hides command failures in `local`
    assignments.
- Resident watchers on one supervisor, S12-14 step 7 (Sync Sprint 12 S12-14).
  - The network monitor, the media watch, and Settings' display, input and notification watches run on the shared
    `WatchedProcess` component, which gains a per-line signal, instead of each owning a process and timers.
  - A Settings display, input or notification watch that exits while its section is open is now restarted after 3 s.
    Before, it stayed down until the section was reopened.
  - Watchers with their own restart or failure rules keep them, each with a comment saying why: the fallback audio
    watch, the Bluetooth monitor, the Picom and appearance-inventory watches, the dwm state bridge, and System
    management.
- One preview countdown in the shell, S12-14 step 6 (Sync Sprint 12 S12-14).
  - The five "reverts in N seconds" countdowns (theme, wallpaper, font and toolkit previews in Appearance, and the
    display and input previews) use one new component, `core/PreviewCountdown.qml`, instead of five hand-written
    timers. When each runs, and what happens when it reaches zero, is unchanged.
- One preview state machine for font and toolkit, S12-14 step 5 (Sync Sprint 12 S12-14).
  - The preview, keep, revert and automatic-rollback machinery of the Settings font and toolkit pages
    (`dwm-settings-font`, `dwm-settings-toolkit`) lives once, in the new `dwm-preview.sh` (in `PREFIX/lib/lyona`).
    That covers the mutation lock, the preview tokens, the rollback watchdog, expiry, and the atomic config exchange.
    The two helpers had 37 copies of these functions, identical but for their labels, so a fix in one never reached
    the other. Messages, state files and behaviour are unchanged.
  - The display, input, wallpaper and theme helpers have different state machines and keep their own.
- The scripts read `themes.toml` as dwm does, S12-14 step 4 (Sync Sprint 12 S12-14, D-20).
  - `theme-apply.sh`, `lyona-gtk-theme`, the Control Center and the Settings appearance provider read `themes.toml`
    through `lyona-toml`, dwm's own parser, instead of three separate awk readers and a Bash one. A file now means
    the same to all of them as to dwm. Before, for example, the Control Center missed `theme="dracula"` written
    without spaces.
  - **Behaviour change in Settings:** when dwm would apply a `themes.toml`, Settings no longer rejects it over
    something only its own stricter checker objected to. Four cases changed:
    - a header with trailing text (`[theme.dracula] trailing`);
    - an array closed on the line it opens;
    - an over-long line;
    - a duplicate theme section.

    Each is still reported, with its line number, but as a warning. Colour and completeness checks are unchanged,
    and a file dwm would not apply keeps its old verdict.
  - `dwm-settings-theme` still edits `themes.toml` line by line, keeping its layout. It now also checks, with dwm's
    parser, that the edited file selects the intended theme.
  - The ISO-build boot splash and console palette generators and the Makefile keep their own readers, because they
    run where `lyona-toml` may not be built yet. A test pins that they read the shipped file exactly as dwm does.
- `lyona-toml`, one TOML reader for scripts, S12-14 step 3 (Sync Sprint 12 S12-14, D-20).
  - A small tool built from dwm's own parser and installed in `PREFIX/lib/lyona`. `lyona-toml dump FILE` prints one
    entry per line (section, table index, key and value, tab-separated, with tabs and newlines escaped), and
    `lyona-toml get FILE SECTION KEY` prints one value, as dwm finds it. Step 4 moves the scripts' own parsers onto
    it.
  - **Fixed:** dwm keeps the first 512 entries of a TOML file and used to drop the rest without a word, so the themes
    at the end of a long `themes.toml` could vanish. The shipped file has 407 entries, so four or five extra themes
    were enough. dwm now logs `<file> has more than 512 entries; the rest were ignored`, and `lyona-toml` exits
    with status 4.
- One copy of the trust checks, S12-14 step 2 (Sync Sprint 12 S12-14).
  - `trusted_parent_chain` and `trusted_file`, which decide whether a file is safe to run with more rights than
    the caller, live in the new `dwm-trust.sh` (in `PREFIX/lib/lyona`). `dwm-settings-display`,
    `dwm-system-health`, `dwm-settings-provider` and `lyona-update` source it; five hand-written copies are gone.
  - The two root helpers, which source nothing at run time, keep a verbatim copy that a test pins to the library.
  - **Fixed:** `lyona-update` checked its root helper's own owner and mode but not the directories above it. It
    now refuses a helper in a directory an ordinary user can write to, like the other callers.
- XDG directories from one place, S12-14 step 1 (Sync Sprint 12 S12-14).
  - 29 scripts that computed `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME` inline now
    call `lyona_xdg_dirs` from the new `dwm-xdg.sh` (in `PREFIX/lib/lyona`). It uses a set value only when it is
    absolute, as the XDG Base Directory spec requires.
  - **Behaviour change:** a relative `XDG_*_HOME` is now ignored everywhere, falling back to the directory under
    `HOME`. Most scripts used to take it relative to their working directory; `lyona-update` and a few Settings
    helpers already ignored it.
  - `autostart.sh`, the control center and the other helpers that must not stop without `HOME` use the lenient
    form, which leaves a directory empty instead of exiting.
  - Still inline, each with a comment saying why: `dwm-system-health`'s deny list, `lyona-install-verify.sh`
    (which works under `USER_HOME`), and three one-line wrappers.

- One runtime source for helpers, step 1 (Sync Sprint 12 S12-13).
  - The shared shell code the commands source (`dwm-paths.sh`, `dwm-utils.sh`, `dwm-packages.sh`,
    `dwm-watchdog.sh`, `dwm-simple-watch.sh`, `dwm-xsettings-config.sh`, `dev-sync-install.sh`) installs to
    `PREFIX/lib/lyona`, mode 0644, instead of `PREFIX/bin`. These files are not commands and no longer sit on `PATH`.
    `make install-system` removes the old copies from `PREFIX/bin`; `make uninstall` removes both.
  - A command finds the shared code beside itself in a checkout, and in `../lib/lyona` once installed.
  - `scripts/dev-sync-install.sh --check` verifies the libraries in `PREFIX/lib/lyona` and reports a copy left in
    `PREFIX/bin` as stale.
- One runtime source for helpers, step 5 (Sync Sprint 12 S12-13): a set `LYONA_DEV_SCRIPTS` is always visible.
  - `dwm-diagnostics` prints a "Runtime source" section naming it, or "not set".
  - `lyona-update check` adds `override\tdev-scripts\t<path>` (JSON: `devScripts`, `null` when unset).
  - Settings -> System shows a "Helpers: Development checkout" card with the path while it is set.
  - dwm logs `running autostart.sh from LYONA_DEV_SCRIPTS=...` each time it runs a session script from it.
- One runtime source for helpers, step 4 (Sync Sprint 12 S12-13).
  - `make install-user` (and so `lyona-update apply`) no longer copies `scripts/` and `config/` into
    `~/.local/share/lyona`, and removes the copies an earlier install left. Nothing reads them any more. Both trees
    were replaced wholesale on every install, so they held nothing of yours; the rest of `~/.local/share/lyona` is
    untouched.
  - **Migration:** if you ran a modified script from `~/.local/share/lyona/scripts`, run it from a checkout with
    `LYONA_DEV_SCRIPTS` set (see `CONTRIBUTING.md`).
  - `lyona-update` shares its verification and backup code with `scripts/dev-sync-install.sh` through the new
    library `lyona-install-verify.sh` in `PREFIX/lib/lyona`. `dev-sync-install.sh` is a checkout tool again and is
    no longer installed; the copy an earlier install put in `PREFIX/lib/lyona` is removed.
  - The live-install check verifies the shipped defaults in `PREFIX/share/lyona/config`, and reports a leftover
    per-user copy as stale, instead of comparing that copy with the checkout.
  - New backups no longer include `lyona-data.tar`. A rollback to an older backup still restores it as it is,
    because the version it restores runs its session from that copy.
- One runtime source for helpers, step 3 (Sync Sprint 12 S12-13).
  - `autostart.sh` and `autostop.sh` install to `PREFIX/lib/lyona`, and dwm runs them from there. They used to exist
    only in each user's copy under `~/.local/share/lyona/scripts`, so an account that never ran `make install-user`
    had no session startup at all. dwm no longer looks in `~/.local/share/lyona/scripts` or `~/.lyona`.
  - The shell runs every helper as the installed command on `PATH`. It no longer prefers a per-user copy for 23 of
    them.
  - Developers: set `LYONA_DEV_SCRIPTS` to a checkout's `scripts/` to run the session scripts, `theme-apply.sh`
    and the shell's helpers from it. No install sets it. dwm ignores it when running as root, and logs when it
    falls back to the installed copy of a script the override lacks.
  - dwm runs `theme-apply.sh` on a theme reload from beside its own executable (`PREFIX/bin`), or from the
    override.
- One runtime source for helpers, step 2 (Sync Sprint 12 S12-13).
  - The shipped default TOMLs (`hotkeys.toml`, `themes.toml`, `window-rules.toml`) install to
    `PREFIX/share/lyona/config`. dwm, `theme-apply.sh`, `dwm-settings-appearance`, `dwm-settings-theme` and the
    Control Center read them there, found from their own location, instead of from the per-user copy in
    `~/.local/share/lyona/config`. That copy is no longer read. A checkout run in place uses its own `config/`.
  - dwm logs where it found the defaults (`dwm: shipped defaults from ...`).
  - The appearance snapshot adds a `managed` record naming the shipped `themes.toml`, which the shell watches.
  - `dwm-controlcenter`, `dwm-keybinds` and `dwm-settings` no longer fall back to
    `~/.local/share/lyona/config/quickshell/shell.qml`; the managed shell is only in `~/.config/quickshell`.

- Overview close, hidden windows and the thumbnail tests (Sync Sprint 12 S12-12, issue `#175`).
  - Closing a window from the overview now asks it to close, as the close key does, so an application can ask about
    unsaved work or refuse. It used `xdotool windowclose`, which destroys the window without asking. dwm now handles
    the standard `_NET_CLOSE_WINDOW` request (what `xdotool windowquit` and `wmctrl -c` send). Before, dwm ignored it,
    so those tools did nothing under Lyona.
  - Every managed window is listed in the overview and the panel's task list. Windows whose `_NET_WM_PID` named a
    root-owned process were left out: any window could hide itself that way, and graphical tools run as root never
    appeared.
  - The window-preview tests run as part of `make check` (`make check-window-thumb-xvfb`,
    `make check-overview-thumbnails-xvfb`); no target ran them before. New `tests/test-overview-close-xvfb.py`
    (`make check-overview-close-xvfb`).

- Install and update correctness (Sync Sprint 12 S12-11, issue `#174`).
  - `lyona-update apply` checks the packages the new release needs, from the release's own package list, before it
    builds. A missing required package stops the update with nothing changed and prints the command to install it
    (`sudo pacman -S --needed ...`); a missing desktop package only warns. It used to install helpers that then
    failed at runtime.
  - `apply --file PATH --version V --sha256 HASH` installs with no network at all. Before, `--file` still looked
    the checksum up online, so the offline install its own error message suggested could not work.
  - The release checksum is taken from the asset's exact file name; the name used to be a pattern, where "." matched
    any character.
  - A rollback replaces the Quickshell config and the Lyona data directory whole, instead of unpacking the backup over
    them, which left behind files a newer version had added.
  - `install.sh` upgrades the system (`pacman -Syu`, shown) after enabling multilib, instead of a database refresh
    alone (`-Sy`), which left a partial upgrade before packages were installed.
  - `make install-user` no longer copies the polkit action templates into `~/.config/polkit`.
  - The ISO installer builds its credentials file with `jq` and hashes the password through stdin. A passphrase with a
    `"` broke the install, and one with a backslash escape silently became a different passphrase, which locked the
    user out.

- Screens turn off and the desktop locks when idle, by default (Sync Sprint 12 S12-10, issue `#173`, decision
  D-13). After 10 minutes idle the screen turns off (DPMS), and light-locker locks the desktop 5 seconds later;
  before, both were off by default, so screens never blanked. The Control Center's Power Settings card turns either
  off or changes the timeout. With no Control Center helper, autostart now applies the saved power settings the same
  way, or blanks at 10 minutes when nothing is saved, instead of always turning blanking off.
  - **Migration:** a choice already saved in `~/.config/lyona/power.conf` (`dpms_enabled`, `lock_enabled`) is kept.
    The new defaults only apply where nothing was saved.
  - The automatic lock needs LightDM; in a `startx` session the screen still turns off.

- Less needless work on events, and no processes left behind (Sync Sprint 12 S12-09, issue `#172`).
  - `dwm-status` sets the root window name to the power state only (`BAT 82% Discharging` or `AC`), and only when
    it changes. The unused volume half and its `pactl` watcher are gone. A `dwm-status` whose X server has gone
    away now exits instead of running on.
  - dwm runs `theme-apply.sh` on a config reload only when `themes.toml` changed (still at start-up and on
    `SIGUSR1`), not for a `hotkeys.toml` or `window-rules.toml` edit.
  - The unused dwmblocks support is removed, with its `popen("pidof ...")` in the event loop. A `hotkeys.toml`
    binding for `sigstatusbar` is now ignored as an unknown function.
  - `dwm-window-thumb` no longer adds a server round trip per captured row.
  - Every resident shell watcher now ends with Quickshell, a crash or SIGKILL included (`Commands.watchCommand`).
    Before, 12 of 20 processes lived on until logout.
  - The Settings display and input watchers no longer wake 10 times a second.
  - The display and input helpers no longer leave temporary files in `/tmp` when they fail or are stopped.
  - The tests keep their workspaces under `${DWM_TEST_TMP_ROOT:-$HOME/tmp}` and stop everything their sessions
    started. `make check-quickshell-qml` no longer leaves a folder behind on every run.
  - New `tests/test-dwm-reload-theme-xvfb.py` (`make check-dwm-reload-theme-xvfb`) and
    `tests/test-quickshell-watcher-lifetime-xvfb.py` (`make check-quickshell-watcher-lifetime-xvfb`), both in
    `make check`.

- The panel's dwm state bridge no longer rebuilds on every property event (Sync Sprint 12 S12-08, issue `#171`).
  `dwm-quickshell-state watch` (now bash) takes every event that arrives within 50 ms of the first into one rebuild,
  and keeps one `xprop -spy` per window, starting and stopping watchers only for windows that appear or go instead
  of restarting all of them on every client-list change. With 10 windows, a tag switch now causes one rebuild (was
  3 to 5), and opening 10 windows causes 10 (was 286, over a full core for several seconds). dwm writes
  `_DWM_FULLSCREEN_MONITORS` only when it changes and publishes a window's desktop only when its tags do. The shell
  skips state keys whose text is unchanged, so unchanged lists no longer rebuild their views, and the closed window
  overview no longer recreates a card per window on every update. With no windows open, the bridge no longer
  reports a phantom window named "found." or a status of "not found.". New `tests/test-quickshell-state-bridge-xvfb.py`
  (`make check-quickshell-state-bridge-xvfb`) and `tests/test-quickshell-state-model-xvfb.py`
  (`make check-quickshell-state-model-xvfb`), both in `make check`.

- The always-on shell watchers stop polling (Sync Sprint 12 S12-07, issue `#170`). `run_parent_bound`
  (`scripts/dwm-watchdog.sh`), which keeps `nmcli monitor`, `pactl subscribe`, `playerctl --follow` and the control
  center's power watcher tied to Quickshell, checked its parent every 0.25 s by running `sed`, `awk` and `sleep`:
  about 12 process starts and 4 wake-ups a second per watcher, for the whole session (the efficiency review measured
  1.7% of a core idle with the network watcher alone). A program child now runs under `setpriv --pdeathsig TERM`
  (util-linux), so the kernel ends it the moment its helper exits, however it exits; the loop that remains only
  covers Quickshell crashing without taking its helpers along, reads `/proc` with shell builtins every 5 s
  (`LYONA_PARENT_BOUND_INTERVAL`), and is bound to its helper the same way, sleep included. A Quickshell crash is
  now noticed within 5 s instead of 0.25 s. The media watcher is no longer restarted every 3 s for the whole
  session when `playerctl` is missing, and the network model debounces monitor bursts (300 ms, like Bluetooth's)
  and no longer drops a change that arrives while a snapshot is running. Each bound process
  checks, once the signal is armed, that its parent is still the one that started it, so a helper dying mid-start
  leaves nothing behind; a zero or malformed interval falls back to 5 s instead of spinning. Idle, the full shell's
  watchers now use 0.07% of a core over 30 s (1.70% before). New `tests/test-dwm-watchdog.py`
  (`make check-dwm-watchdog`), `tests/test-quickshell-watchers-xvfb.py` (`make check-quickshell-watchers-xvfb`) and
  `tests/test-quickshell-idle-watchers-xvfb.py` (`make check-quickshell-idle-watchers-xvfb`), all in `make check`.

- Updates keep your compile-time options (Sync Sprint 12 S12-02, decision D-18). `lyona-update` looked for `config.h`
  only next to its own scripts directory, so updates from Settings or from the installed command always built from
  `config.def.h` and silently dropped compile-time changes. It now builds with
  `${XDG_CONFIG_HOME:-$HOME/.config}/lyona/config.h` first, then a checkout's `config.h`, says which one it used, and
  names it if the build fails. `make install-user` copies a customised checkout `config.h` there once and never
  overwrites an existing one (an unchanged default is not copied). `docs/src/configuration.md` now leads with the TOML
  files as the way to customise and lists the few compile-time options `config.h` still holds; it still described
  `rules[]`, `keys[]`, `colors[]` and `autostart[]` in `config.h`, which no longer exist.

- The window overview now fades out before hiding, with immediate closure under reduced motion.
  Overview load tests enforce absolute CPU and timing budgets only with `DWM_OVERVIEW_STRICT=1`.

- A qualification ledger closes Sprint 10 (Sync Sprint 10 S10-07, issue `#147`,
  `docs/SYNC-SPRINT-10-COMPLETION-AUDIT.md#s10-07-qualification-ledger-for-sprints-closed-with-hardware-checks-open`). Sprints 4, 5 and Phases 5 to 7 were left
  with checks that need real hardware, a real install, or elevated access (the Picom NVIDIA
  backend, fresh-install media defaults on both ISOs, a full privileged `lyona-update` run,
  Settings panes and floating toggles on a slow provider, a Flathub-remote refusal, a fresh
  LightDM login, a live PackageKit transaction, a live polkit denial, D-4's read-only
  `pacman.lck` check), and those closed milestones did not say so. Nothing here can run in this
  sandbox and none of it is done by this entry; the ledger table in the plan doc is the one
  place all of it is now tracked instead of implied-done by a closed issue. `docs/UPSTREAM-SYNC.md`'s
  Sprint 10 row and D-4's "Open decisions" row now point at it, and `TASKS.md` marks the sprint done
  on that basis.

- Clicking the empty part of the top bar closes the launcher, the command menu, notification history and the control
  center's utility windows as well as open panel popups (Sync Sprint 11 S11-03, upstream `#340` click-away half).
  `DwmPanel.qml` gets a background `MouseArea` that calls `popupRequested(root, "")`, and `selectPanelPopup()` already
  closes all of those for an empty id. Panel popups already dismissed on a bar click through their input grab
  (`tests/test-panel-popup.py` asserts it); the floating windows hold no grab, so they stayed open.
  `test-quickshell-panel-menus.sh` pins the `MouseArea` and the four closers. Not verified: an interaction test
  against the real `DwmPanel` (it needs eleven models), or that buttons in the bar still receive their own clicks;
  check by hand.

- Popups and notification cards are square, and the keyboard focus ring is 1 px (Sync Sprint 11 S11-07, decision D-10,
  upstream `#340` geometry half). `Theme.popupRadius` and `Theme.notificationAccentRadius` are `0`, so every surface
  built on `ShellSurface` (13 QML files) is square; `NotificationCard.qml` and `NotificationHistoryWindow.qml` take
  `Theme.popupRadius` instead of `largeSurfaceCardRadius`. `Theme.controlFocusBorderWidth` is now
  `controlBorderWidth`, so the focus ring matches the idle border (1 px, or 2 px in high-contrast mode, was 2 px and 3
  px) and focus is shown by the border colour alone. Controls inside a square popup (`controlRadius`,
  `largeSurfaceCardRadius`) keep their rounded corners. Five places apply `controlFocusBorderWidth` unconditionally as
  an emphasis border, not on focus (`PanelSlider.qml:83` and `AppearanceSettingsPane.qml` lines 361, 502, 737, 934),
  so they thin from 2 px to 1 px too; check them by eye. The accessibility pin for the focus width changed with it,
  and `test-quickshell-design-system.sh` now pins the three radius values.

- `PanelTooltip.qml`'s horizontal position is now a live property binding
  (Sync Sprint 6 S6-01, `docs/SYNC-SPRINT-6-THEME-CONSISTENCY-AND-WINDOW-OVERVIEW.md`,
  small portable fix from upstream `#343` `2461027`), not only recomputed from
  `anchor.onAnchoring`, an event that does not necessarily fire on every
  geometry-relevant change. The clamping math moves to a small pure function,
  `PanelTooltipPosition.js`'s `clampedX()`, unit-tested directly
  (`tests/qml/tst_panel_tooltip_position.qml`, via `qmltestrunner`) instead of
  only through the six panel widgets that use `PanelTooltip`.

- Floating a tiled window now visibly changes it (Sync Sprint 5 S5-03, decision
  D-9, ported from upstream `#331` `2e77c11` and `#333` `841d3cd`).
  `togglefloating` used to float a window at its current tile size, so
  `Super+Space` seemed to do nothing. An explicit toggle (a key or button
  binding) now pops a tiled window out at 85 percent of its tile, centered and
  clamped to the monitor's work area through a new `shrinkfloating()`, as far as
  the window's size hints allow: a minimum size larger than the work area wins,
  and the window then starts at the work area's top-left corner and extends past
  it. Toggling back retiles it. Switching a
  monitor to the floating layout, from tiling or monocle, shrinks each visible
  tiled window the same way, once: choosing the floating layout again does not
  shrink them again, and `Super+T` retiles. Windows already floated
  individually, fixed-size windows, and fullscreen windows (other than fake
  fullscreen) are left alone, and mouse drags, which call `togglefloating` with
  no argument, keep their geometry. `tests/test-xvfb-runtime.sh` covers the
  toggle cycles, both layout transitions, individually floated and fixed-size
  windows and windows whose minimum size exceeds the work area; it gained a
  `Super+L` floating-layout key in its own hotkeys and `border`, `min-size` and
  `fixed` modes in its X client.

- Settings panes stay hidden until their data has loaded (Sync Sprint 5
  S5-01, `docs/SYNC-SPRINT-5-SETTINGS-LOADING-FLATHUB-FLOATING.md`, ported from
  upstream `#335` `709bcd0` and `4b0d438`; completes Lyona's `#315` work from
  Sprint 3). A pane used to fade in as soon as its component loaded, so cards
  still appeared and reflowed inside a visible pane while its first reads
  finished. `DeferredSettingsPane.qml` (now upstream's file) takes a
  `dataLoading` input from `SettingsWindow.qml` and keeps the pane invisible
  and disabled, behind a fixed "Loading settings..." message, until its
  component is ready and `dataLoading` is false; it then presents once, and
  later refreshes never hide controls again. Every model behind a pane reports
  its finite initial reads as a read-only `initialLoading` (never a resident
  watch subscription), and `SettingsModel` adds `displayActionBusy` and
  `inputActionBusy` so a preview-recovery read holds the Display and Input
  panes. Each queued-refresh flag (`snapshotPending`, `refreshPending`,
  `capabilityRefreshPending`, and the display, input, appearance, font,
  toolkit and Picom ones) now clears only after the process it queued has
  started, and no longer inside `onRunningChanged`, so there is no frame in
  which a refresh is about to run but nothing reports it. Lyona adaptations:
  the Appearance pane also waits on the toolkit provider and Picom (Lyona has
  no personalization provider), and upstream's `desktopUpdateModel` term is
  dropped because that git-`main` updater is declined (D-8). (Lyona's own update
  card is gated separately: see the System pane fix below.) The responsiveness harness now delays the
  display and input preview-recovery reads, the accessibility, panel and
  System-management reads and the notification policy, and asserts each pane
  stays hidden with an unchanged viewport until its data arrives, that no pane
  presents while one of its models is still loading, and that a queued flag is
  never cleared while nothing is running; the new
  `make check-quickshell-settings-loading` pins the wiring in the source.

- Stop depending on AUR-based packages, and audit the repository for any
  (`docs/AUR-PACKAGES.md`). The one package Lyona needed from the AUR,
  `xkbset` (sticky, slow, bounce and mouse keys and the AccessX shortcuts in
  Settings), is replaced by the in-tree `scripts/dwm-xkbset`: a Python helper
  over libX11's XKB calls, using `ctypes` like `dwm-cursor-reload`, so it adds
  no package. It speaks the subset of `xkbset` that Settings used, so
  `dwm-settings-input` and `dwm-settings-provider` only changed the command
  name and their messages; a checkout that has not been installed finds it
  beside the script. `xkbset` is dropped from the `desktop-optional` profile
  and from `check-deps.sh`. The AUR helper (`yay`) that `install.sh`
  bootstraps stays, by decision; no package Lyona installs uses it. All 113
  packages in the profiles and the live ISO resolve in `core`, `extra` or
  `multilib`. Two new checks: `make check-xkbset` runs the helper against a
  real X server and compares its masks with the system `XKB.h`, and
  `make check-no-aur` fails if an AUR helper installs a package, if anything
  but `install.sh` reaches the AUR, or if a profile names a package outside
  the official repositories. As a side effect the Settings xvfb suite no
  longer skips on hosts without `xkbset`.

- Qualify that missing optional components stay capability-scoped, and coalesce
  capability refreshes (Sync Sprint 3 S3-09, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  ported from upstream `#188`/`c8f574b` and `#191`/`4d776bc`, pre-survey gaps).
  A new `make check-phase5-optional-components` target and a combined
  optional-loss scenario in the Settings xvfb suite remove the wallpaper
  folder, Feh, cursor/icon/GTK assets, the Qt backend and Picom at once and
  check that only those capabilities degrade while the font and toolkit
  providers, terminal integrations, inventory watch and theme controls keep
  reporting what they did when healthy, then that everything recovers. The
  Appearance model now exposes wallpaper mutation and reset state and detail,
  and `shell.qml` gains read-only probes for them. Capability discovery
  requested while a provider run is in flight is queued as one follow-up
  run, and `capabilityById()` reports "Capability discovery is still
  refreshing" instead of a stale answer; the accessibility text-scale
  grouping from `#191` stays diverged by decision. The wallpaper preview
  watchdog now allows up to about one second (100 tries at 10 ms, was 20) to
  confirm its process identity, so a loaded machine no longer fails a preview
  that had started correctly.
  Lyona adaptations: upstream's personalization test is not ported because
  Lyona's toolkit has no delegate records; instead
  `tests/test-dwm-settings-toolkit.sh` checks that a missing `qt5ct`/`qt6ct`
  stays scoped to Qt, run against a PATH without them so it holds whether or
  not the host has them installed. The scenario probes `toolkit*` and the
  managed-font provider where upstream probed personalization, and the
  fixture now installs `dwm-settings-toolkit`, which it previously omitted.
  Fixture names follow Lyona's (`Lyona-nord`, not `Nordic`).

- Stop automatic theme-preview status retries once their bounded failure
  budget is exhausted (Sync Sprint 3 S3-09, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  ported from upstream `#183`/`e91d018`, a pre-survey gap): after more than
  three zero-remaining or unparseable `preview-status` reads Appearance stops
  polling and reports that rollback status needs a manual refresh. Opening
  Appearance or pressing Refresh still performs one explicit retry, and every
  definitive result (none, expired, failed, a positive remaining time, or a
  finished keep/revert/abandon) re-arms automatic observation. Applied
  unchanged.

- Keep the panel sharp under popups, and make shell surfaces usable at large
  text (Sync Sprint 3 S3-07 and S3-08, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  ported from upstream `#324`/`c44dae4` and the surface fixes of `#327`/`a5b829d`).
  Popups now start below the panel so a compositor can no longer blur the bar
  through the transparent click-away surface, and a popup taller or wider than
  the screen scrolls inside a clamped viewport instead of running off-screen.
  The Wi-Fi password dialog grows with its content, wraps its hint text, and
  scrolls when it would exceed the screen. Notification stacks, System Health,
  the Controls and Bluetooth windows and the panel icon glyphs size from the
  text scale; launcher, Wi-Fi and Bluetooth rows grow with their text instead
  of clipping it, the notification stack is clamped to the panel width and
  scrolls in its own viewport, and Health summary tiles wrap. Font sizes go through the new `Theme.scaledFontSize()` and the
  shell text scale accepts 0.75–2.0 (was 0.8–1.5). Status and rollback
  readiness for the wallpaper now list files by name and metadata only and
  never start an image decoder; the decode check moves to apply/preview.
  Lyona adaptations (decision D-7, amended 2026-09-20): geometry stays on
  `Theme.dp()` — upstream's `scaledSize()` is not ported, and the fixed
  pixel sizes it touched are wrapped in `dp()` instead. Upstream's
  desktop-typography port (`desktopFont*`, `applySharedTypography()`) is not
  taken because it needs a desktop font and text-size provider Lyona doesn't
  have; the managed shell font and its controls stay as they are. Upstream
  `68a0d1f` is not taken either: Lyona's default-wallpaper selection already
  decodes only a sample. `devicePixelRatio` was confirmed to be 1.0 at 144 DPI
  under Lyona's `QT_ENABLE_HIGHDPI_SCALING=0` launch, so no native-scale
  compensation is needed.
  `tests/qml/SettingsResponsiveness.inc` now renders these surfaces at 200
  percent text and checks that text stays inside its row, popups and the
  Wi-Fi prompt stay on screen and scroll, and the last notification's dismiss
  control is reachable.

- Settings > Appearance reads the Picom configuration once when nothing changed, not
  twice (#85). The watcher used to say `ready` right after starting `inotifywait`,
  before its watches existed, and the model answered every `ready` with a second
  `dwm-settings-picom status` (about 0.2 s of Python start-up) to close the gap; the
  compositor term of the pane's loading gate could flap false then true 150 ms
  apart. `dwm-settings-picom watch` now waits for `inotifywait`'s "Watches
  established." and says `ready<TAB>revision` with the configuration revision as of
  that moment, and `PicomModel` reads again only when that revision differs from the
  one it already holds (or the watcher could not give one, or the first read
  failed), so an edit made between the first read and the watcher going live is
  still shown. Covered by two helper tests in `tests/test-picom.py` (an edit right
  after `ready` is never missed) and the new `make check-quickshell-picom-model-xvfb`,
  which plays eight watcher scenarios against the real model and counts the reads:
  opening Settings went from 2 reads to 1 when nothing changed.

- Compact the Control Center and Settings detail pane (Sync Sprint 3 S3-04,
  `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`, ported from upstream
  `c3e9a18` "refactor(quickshell): compact control surfaces", open since the
  first survey): remove the Control Center overview's redundant "Launch"/
  "Desktop"/"Utilities" section headers and the Power page's duplicate
  status text lines (their information now lives in each row's own
  `detail`, which shows the remaining duration instead of a bare On/Off),
  tighten row heights via a new `compactRowHeight` token, margins, and
  spacing throughout, and shrink the Settings detail pane's header and
  capability cards to match.
  Lyona adaptations: `Theme.compactSpacing` already existed, so no new
  token was needed; every new pixel constant (`compactRowHeight`, the
  `PresetButton` height) is wrapped in `Theme.dp()`, matching this sprint's
  established convention; duration formatting uses Lyona's own
  `Theme.formatDuration()` (not upstream's local `root.formatDuration()`,
  which Lyona hoisted into `Theme.qml` earlier); the Auto Lock row keeps
  Lyona's own "Unknown" state for an unavailable lock backend alongside
  upstream's new duration-when-enabled behavior. Two `xdotool` click
  coordinates in `tests/test-quickshell-health-xvfb.sh` needed updating for
  the now-shorter rows; rather than porting upstream's own new coordinates
  (tuned to its own layout), the correct values for Lyona's real rendering
  were read directly off a live xvfb run instrumented with a temporary
  `mapToGlobal()` probe, then verified end to end against the genuine
  compacted UI.

### Added

- Settings > System can update packages and Flatpak apps in your terminal (Sync Sprint 15 S15-03 and S15-04, from
  upstream `#363`, decision D-26). Packages use `yay -Syu` when `yay` is installed, so AUR packages such as the legacy
  NVIDIA drivers update too, and `sudo pacman -Syu` otherwise. Flatpak updates the system and user installations each
  on its own. You see the tool's plan and confirm it yourself, and the result shown is the command's. The PackageKit
  preview stays beside it. The panel's count now includes pending Flatpak updates.
  - **Migration:** the terminal can float through a new default rule,
    `{ class="lyona-update-float", isfloating=1 }`. An existing `window-rules.toml` is not changed; add the rule to
    float it, as Settings explains.
- The panel shows an update icon with a count when updates are available (Sync Sprint 15 S15-02, from upstream
  `#363`). The count is the pending system packages, counted with `checkupdates`, plus one for a new lyona release. A
  click opens Settings > System, where updates are run. It checks a few minutes after login, every 6 hours by default,
  and on reconnecting. Settings > System sets the interval and whether the icon stays when everything is current. This
  adds `pacman-contrib` to the desktop packages.
- The live medium installs a working proprietary driver on older NVIDIA cards (Sync Sprint 14):
  - Maxwell, Pascal and Volta cards (GTX 750 to GTX 10xx) get the 580xx driver, and Kepler cards (GTX 600 and 700)
    the 470xx one. The card's device ID decides, from a table generated from NVIDIA's own list.
  - The driver comes from the CachyOS repository when it is available, and is otherwise built from a pinned, reviewed
    AUR PKGBUILD. That is the project's one AUR exception (`docs/AUR-PACKAGES.md`).
  - Fermi and older cards keep nouveau. Not yet tested on real hardware.
- Calendar and weather panel widgets (Sync Sprint 12 S12-20, upstream `#358`):
  - **Calendar:** click the clock for a month calendar, with keyboard navigation. It can be turned off, and has a
    `calendar` IPC target.
  - **Weather:** it shows the current temperature from Open-Meteo for a location you type in Settings, Appearance.
    It is off by default, and nothing is sent until it is turned on and given a location (decision D-19).
  - **How it fetches:** at most every 30 minutes, with units from the locale unless set. Failures show
    "Unavailable", with no retry loop.
  - **Bar Widgets:** both switches are in Control Center's Bar Widgets and in Settings. An existing
    `panel-widgets.conf` keeps its choices.
- Two overview tests (Sync Sprint 9 S9-03, S9-04): `check-overview-keyboard-xvfb` drives the popup with real key
  events and no mouse, and `check-overview-load-xvfb` runs it over 60 windows on 9 tags and checks the closed
  Quickshell CPU before and after opening, open, filter and navigation time budgets, and that the selection scrolls to
  the top and bottom. Measured up to 600 windows: the card list needs no virtualization. The tests exit 77 (skip)
  without xdotool, quickshell or a built dwm.

- The window overview is keyboard-operable, accessible and animated (Sync Sprint 9 S9-02, S9-03). Ctrl+W closes the
  selected card (from the popup and from the search box), a keyboard selection scrolls into view, each card is an
  accessible list item with the window title as its name and "Tag N, class, monitor M" as its description, the close
  button and search box are named, and the popup is a named dialog. Card colours are Theme tokens only, including the
  text roles, and state changes and the popup fade use Theme.animationFast/Normal, so they are instant under reduced
  motion. Fixes the monitor label, which never rendered on a multi-monitor setup because the card read a count nothing
  provided. Not verified: a screen reader, how the motion looks, or two real monitors.

- A layout switcher in the Control Center (Sync Sprint 11 S11-08, decision D-12, the layout half of upstream issue
  `#297`). The main page has a "Window layout" row of Tile, Floating and Monocle buttons; the current layout is
  highlighted and follows the hotkeys, and layouts stay per tag. It needed a small change to the dwm core: dwm
  publishes the selected monitor's layout for its current tag as the root property `_DWM_LAYOUT` (an index into
  `layouts[]`, written only when it changes) and takes a request through `_DWM_SET_LAYOUT`, which it reads, deletes,
  range-checks and applies with `setlayout()`; out of range and negative values are ignored. `dwm-quickshell-state`
  gains a `layout=` field, watches the property, and has a `layout <index>` command that sets it with `xprop`;
  `DwmState.qml` gains `layoutIndex` and `setLayout()`. An older dwm publishes nothing, so the buttons are disabled.
  Any local X client could already set root properties or send key events, so this adds no new capability. Tests: the
  dwm harness (`check-xvfb-runtime`) sets, ignores, consumes and per-tag checks the property and fails against the
  original `dwm.c`; `check-quickshell-state` covers the `layout=` field and command; `check-quickshell-panel-menus`
  pins the wiring and that the button list has one entry per layout in `config.def.h`. Not verified: the buttons under
  a real mouse, more than one monitor, or a `config.h` with different layouts (the button list is static).

- A window corner-radius slider in Settings > Appearance > Compositor (Sync Sprint 11 S11-09, decision D-12, the
  corner half of upstream issue `#297`). It sets Picom's `corner-radius` from 0 to 32 px through a new
  `dwm-settings-picom set-corner-radius <px> <revision>` action that follows `set-backend`: comments and formatting
  are preserved, a value in an included file is changed at its source, a stale revision is refused, a fractional,
  negative, non-finite or over-range value is refused, editing is refused while Picom runs with a command-line
  `--corner-radius`, and `0` removes the entry. `status` reports `corner_radius`, and its detail text notes that
  fullscreen windows stay square, per-window rules can override it and it does not combine well with
  `transparent-clipping`. `PicomModel.qml` validates and sets it and `PicomSettingsPane.qml` adds the slider with the
  same debounce as the opacity sliders. No dwm change. Picom itself does not type-check the value (`--diagnostics`
  exits 0 for a string), so the helper's own check is the guard. Tests: 5 new helper tests (56 in the file,
  mutation-checked) and a case in `test-picom-xvfb.py` that sets, replaces and clears the radius through the real
  helper and the real pane (fails when the model's command name is broken). Not verified: the rounding itself (Xvfb
  cannot composite), how Picom clips dwm's 1 px border at a rounded corner, or the slider under a mouse.

- A "Dependencies and Package Profiles" page in the book (Sync Sprint 11 S11-05, upstream `2a0e9b3`, written for
  Arch). `docs/src/dependencies.md` explains what the `core`, `recommended` and `full` installer profiles install, how
  the groups in `scripts/dwm-packages.sh` are composed, and lists every group's packages with its purpose;
  `install.md` links to it and `SUMMARY.md` includes it. The package lists were generated from the map, and
  `tests/test-arch-packages.sh` now fails if a package that `full`, `iso`, `terminal`, `lightdm` or the QML groups can
  install is missing from the page (verified by removing one). Upstream's page describes Fedora package names and an
  Astro site, so nothing was copied. Not checked: the mdBook build (`mdbook` is not installed here).

- Switching theme now tells already-running GTK 3 applications (Sync Sprint 11 S11-02, upstream `#351` live-broadcast
  half). `theme-apply.sh` writes `Net/ThemeName` (and `Net/IconThemeName`) into `xsettingsd.conf` next to the cursor
  keys, through the shared `xsettingsd_write_line()` writer, so the daemon reloads and applications such as Thunar
  repaint without a restart; the earlier `xfconf-query` call is not read by `xsettingsd`. Each line replaces its own
  previous line, other keys survive, a quote or backslash in the name is escaped, and a name containing a carriage
  return or newline, or over 1024 characters, is refused with a warning and the previous value is kept. The icon theme
  follows the same set, replace or remove rule as the GTK 2 branch. Upstream's dark-theme name resolution is not
  ported: Lyona generates its own `Lyona-<theme>` (S6-02) and already knows the name. `test-dwm-settings-theme.sh`
  covers the broadcast, replace-not-duplicate, escaping and rejection, and fails against the original
  `theme-apply.sh`. Not verified: a running GTK application actually repainting.

- Multi-monitor labels, type-to-filter and close-from-card for the cross-tag window overview (Sync Sprint 8 S8-02
  through S8-04, `docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md`, issue `#350`; the model half landed in Sync Sprint 10
  S10-01, see "Fixed"). `OverviewCard.qml` shows a monitor label only when more than one monitor is present; a search
  box in `WindowOverview.qml` narrows the cards by title or class through `OverviewFilter.js`'s `filterWindows()`
  (case-insensitive substring, the launcher's own convention); each card has a close button that sends
  `WM_DELETE_WINDOW` through `dwm-quickshell-state close` (`DwmState.closeWindow()`) and hides the card at once via
  `OverviewFilter.js`'s `excludeIds()`, without waiting for the next `_NET_CLIENT_LIST` update. A window that ignores
  the close request stays hidden until the popup is reopened. `tests/test-quickshell-overview-xvfb.sh` (new,
  `make check-quickshell-overview-xvfb`) loads the real `OverviewModel` and `WindowOverview` under Xvfb against a stub
  `dwmState` and asserts filtering, selection clamping, close-from-card, a window vanishing mid-use, and a clean
  reopen (22 assertions, mutation-checked against three broken models); real key presses and mouse clicks are not
  simulated, the model calls their handlers make are.

- `DwmState.qml` exposes the per-window list as `windowStates` and resolves each window to a tag and monitor through
  `DwmStateWindows.js` (`windowsByTag()`, `groupByTag()`) (Sync Sprint 7 S7-02,
  `docs/SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md`, issue `#350`), covered by `tests/qml/tst_dwm_state_windows.qml`.
  Recorded here after the fact: the original PR (#134) carried no changelog entry.

- A cross-tag window overview popup (`config/quickshell/overview/`): one card per open window grouped by tag, click to
  switch tag and focus the window, Escape or click-away to close (Sync Sprint 7 S7-03,
  `docs/SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md`, issue `#350`). Recorded here after the fact: the original PR (#135)
  carried no changelog entry.

- Keyboard navigation for the cross-tag window overview (Sync Sprint 8 S8-01,
  `docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md`, part of the cross-tag window overview, issue `#350`): the exact
  `Keys.onPressed` shape `LauncherWindow.qml` already has (arrows/Home/End move the selection, Enter activates it;
  Escape already closed the popup since S7-03). `OverviewModel.qml` gains `selectedIndex`, `flatCards` (the tag-grouped
  card list flattened into keyboard-navigation order, using a new `flatIndex` `DwmStateWindows.js`'s `groupByTag()` now
  assigns to each window in render order), `selectRelative()`/`selectAbsolute()`/`activateSelected()`. The wrap-around
  and clamping math itself lives in a new pure library, `OverviewSelection.js` (`.pragma library`, the same split
  `PanelTooltipPosition.js` and `DwmStateWindows.js` already established), unit-tested directly via
  `tests/qml/tst_overview_selection.qml` under `qmltestrunner` rather than only through `OverviewModel.qml`, which
  cannot be instantiated live there (it imports `Quickshell`, unavailable outside a real Quickshell process). The
  selected card gets a visible highlight, the same `Theme.menuSelectedBackground`/`controlSelectedBorder` styling
  `LauncherResultDelegate.qml`'s own `selected` state already uses, distinct from mouse hover since the two can
  disagree (arrow keys move the selection without the mouse moving). Multi-monitor label polish and the
  window-closes-while-open edge case remain the rest of S8-02, not this item.

- `scripts/dwm-quickshell-state` gains a `windows=` field alongside `apps=` (Sync Sprint 7 S7-01,
  `docs/SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md`, part of the cross-tag window overview, issue `#350`): one entry per managed
  window (`id:desktop:class:title`), never deduplicated by class the way `apps=` is for the panel's running-apps row, which
  it leaves untouched. Adds both title atoms (`_NET_WM_NAME`, preferred, and `WM_NAME` as the fallback) to the same per-window query
  `apps=`/`occupied=` already make, so this rides the existing `watch` loop for free rather than adding a new round trip.

- `scripts/ci-local.sh` runs the "Full suite (manual)" workflow's job in a local
  Docker container (see `CONTRIBUTING.md`): the same base image, package set
  and unprivileged runner, on a copy of the working tree, so a CI-only failure
  can be found and fixed without a push. `--each` runs every target of the
  `check` recipe separately and lists all failures in one pass, where `make
  check` stops at the first. Running it found and reproduced the failure below.

- Desktop update experience (Sync Sprint 4 S4-06,
  `docs/SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`, decision D-8: upstream's
  mechanism for `#318`-`#323` is declined because `lyona-update`'s signed
  release tarballs already cover it, and only its user-facing ideas are ported).
  Progress is now visible outside Settings and survives the Quickshell restart
  an apply causes: a **progress popup** under the panel shows the current step
  with a **View log** button, and a **panel indicator** next to the battery
  brings the popup back after **Hide**. When the shell restarts mid-update both
  reappear by themselves, still in progress or showing how it ended. Only news is
  shown: a finished update does not reappear at a login ten minutes later, and a
  status left "in progress" by a crash more than an hour ago does not spin
  forever. A successful update dismisses itself after 20 seconds; a failed one
  stays until dismissed. `lyona-update` now sends a desktop **notification**
  when an apply or rollback ends (critical, and naming the log, for a failure),
  from the same place it writes the terminal status, and only after Quickshell
  has been restarted so the notification reaches the new shell rather than the
  one being replaced. Declining the confirmation prompt is not announced as a
  failure. **Update log:** the plan assumed `lyona-update` already wrote a log;
  it did not (the model only held the output in memory, which the restart
  destroys), so each apply or rollback now writes `update.log` with its full
  output, readable only by its owner and replaced on the next run, while a dry
  run keeps the previous log. The model reads at most the last 64 KiB, cut at a
  line boundary, and **Settings > System** has a matching **View update log**.
  Nothing new was needed for "one authorization per update": apply asks once
  (its two privileged call sites are release versus checkout mode) and rollback
  once, and a step that ran and failed is not retried through a second prompt;
  that is now pinned by a test. Issue `#311`'s acceptance was re-verified against
  `tests/test-lyona-update.sh`: up to date reports `current`, outdated reports
  `behind` and offers it, an unreachable network reports `offline`, and
  deferring leaves the install record, backups and `update.conf` unchanged,
  which had no test until now.
  Lyona adaptations: the popup is centered under the panel like the notification
  stack (so it needs no new dwm window rule) instead of a window of its own, the
  new tests never run a real `notify-send`, and the mechanism-side upstream
  commits are recorded as covered in `docs/UPSTREAM-SYNC.md`.
  Verified by `tests/test-lyona-update.sh` (log, notifications, defer,
  authorization count) and the new `tests/test-quickshell-update-progress-xvfb.sh`,
  which runs an isolated copy of the shell against real status and log files and
  was mutation-checked four ways.


- Icon themes and first-login theme convergence (Sync Sprint 4 S4-03,
  `docs/SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`, ported from upstream
  `#301`/`69240ea`; `#328`/`d4c6d89` recorded as not needed): the `theme`
  package profile now includes `adwaita-icon-theme` and `papirus-icon-theme`
  next to `dconf` (all in official `extra`, and on the live ISO, which now
  also carries `dconf` for first-login theming), so GTK applications have
  icons on a fresh install. `make install-user` now runs `scripts/theme-apply.sh`
  before recording the install, so first login already has the selected theme
  applied instead of waiting for a manual theme change. A failure there is a
  warning rather than an aborted install. The ISO package list is now the union
  of the `required`, `desktop`, `theme`, `media` and `iso` profiles.
  Upstream `#328` fixed `xsettingsd` inheriting an installer's lock descriptors
  through `dwm-xsettings`. Lyona has no `dwm-xsettings`, `theme-apply.sh` never
  starts `xsettingsd` (it edits its configuration and sends `SIGHUP`;
  `autostart.sh` starts it at login and already closes the descriptors it
  owns), and no install path holds a lock, so the plan's Python launcher wrapper
  was not ported. That was checked, not assumed: the real script was run under
  a held lock with real `gsettings` and `xfconf-query` on a private D-Bus
  session, the lock was free afterwards and no process held it. The new
  `tests/test-theme-apply-install-lock.sh` (in `check-appearance`) pins this and
  fails if `theme-apply.sh` ever launches the daemon with an inherited lock.

- Media and image defaults on fresh installs (Sync Sprint 4 S4-02,
  `docs/SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`, ported from upstream issue
  `#308` and the fixes `#317` and the MIME hunk of `c679937`): the recommended and
  full install profiles now install Celluloid, mpv, and sxiv (all in official
  `extra`, and on the live ISO too), and a new `scripts/seed-default-apps.sh`
  makes Celluloid the handler for audio and video, sxiv the handler for images,
  and, when Thunar is installed, Thunar the handler for folders on a fresh
  account. It runs before Gear
  Lever, which writes its own AppImage MIME preference file, and does nothing
  when a `mimeapps.list`, a desktop-specific `*-mimeapps.list`, or a legacy
  `defaults.list` already exists. Every handler is validated before anything is
  written, the file is published atomically, and a preference written while the
  script runs is kept rather than replaced. Settings > Defaults now lists menu-hidden
  handlers such as sxiv (its desktop entry sets `NoDisplay=true`), which used to
  be excluded, while still excluding disabled entries and missing executables and
  keeping menu-visibility filtering for the browser, file-manager and terminal
  roles. GIF, BMP and TIFF join the supported image types.
  Lyona adaptations: upstream's browser seeding is dropped (Lyona does not ship
  Brave), the seed runs inside the recommended branch of `install.sh` just before
  Gear Lever instead of moving the Gear Lever block, and the ISO package list is
  now the union of the `required`, `desktop`, `media` and `iso` profiles. `python`
  and the four new packages were checked against the official repositories with
  `make check-no-aur`. The `.desktop` IDs were confirmed from the shipped Arch
  packages (`sxiv.desktop` sets `NoDisplay=true`; Celluloid is
  `io.github.celluloid_player.Celluloid.desktop`). Not yet verified: the
  acceptance in the sprint doc that a fresh ISO install (standard and NVIDIA) and an
  existing-system `install.sh` both open `.mkv` in Celluloid and `.png` in sxiv
  from Thunar, and still do after logout and reboot, which needs real installs.

- The application launcher hides desktop entries scoped to other desktops (#104,
  ported in part from upstream PR #340). `scripts/dwm-quickshell-launcher` now
  reads `OnlyShowIn` and `NotShowIn` and compares them with the tokens of
  `XDG_CURRENT_DESKTOP` (a Lyona session exports `X-DWM` and `dwm`; unset means
  the same), so other environments' preference panels, such as the XFCE panel
  settings that Thunar pulls in, no longer appear. Any one matching token is
  enough, the comparison is case sensitive, an empty `OnlyShowIn` shows the
  entry nowhere, and GLib-compatible ordered token handling checks
  `OnlyShowIn` before `NotShowIn` for each token (falling back to the existing
  behavior when no token matches). A key inside an action group never scopes
  the whole entry. Opening a panel popup now also closes the launcher, the
  notification history and the Control Center utility window instead of
  leaving them open behind it. The rest of upstream's PR (screen-sized
  click-away windows, square corners, 1 px focus borders) was declined and
  Lyona keeps its behaviour. New cases in `tests/test-quickshell-launcher.sh`
  and `tests/test-quickshell-command-menu.sh`.

- Configuration-backed Picom controls (Sync Sprint 4 S4-01,
  `docs/SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`, ported from upstream
  `#312`/`#313`/`#314`, closing upstream issue `#309`): **Settings > Appearance >
  Compositor** now has foreground and background opacity sliders, a backend
  selector (Automatic, XRender, GLX, experimental EGL) and start/stop, driven by
  the Picom configuration file instead of process polling, so the controls no
  longer appear and disappear. The new `scripts/dwm-settings-picom` (Python,
  JSON protocol 1) edits `picom.conf` while preserving comments, unrelated
  settings and included files, validates before publishing, keeps the ten most
  recent backups and rolls back a failed activation. Automatic picks GLX for an
  accelerated Intel/AMD renderer and XRender otherwise (NVIDIA adds
  `--xrender-sync-fence`), retrying XRender once if automatic GLX fails to start.
  Autostart, the Control Center's Restart Picom and Toggle Compositor, and
  `theme-apply.sh` all go through the helper, so the backend no longer differs
  between login and a manual restart (the Control Center used to start Picom
  without `--backend`); theme changes reapply opacity without storing it in
  themes. The old process watcher and its `dwm-settings-appearance
  watch-compositor` command are gone, and the compositor inventory and
  integration now report "controls use its configuration file". `python` is now
  listed in the `desktop` profile and the live ISO because login starts the
  compositor through the helper.
  Lyona adaptations: state, backup and include paths use `lyona`, not
  `dwm-titus`; every new pixel constant in the pane uses `Theme` tokens.
  **Race fixed beyond upstream:** the helper's `picom --diagnostics` status probe
  claims the compositor selection for a moment, so a Settings refresh landing
  during `start` made Picom refuse with "Another composite manager is already
  running". `launch()` now waits up to two seconds for that owner to release
  the selection and retries up to three times, while a real second compositor
  (which keeps the selection) still fails immediately. The Picom runtime test
  failed in four of six runs before this and passes six of six after, and three
  new unit tests cover the retry, the real-second-compositor case and the bound.
  Not yet verified: the NVIDIA image (`auto` should resolve to XRender with
  `--xrender-sync-fence`, and `picom --diagnostics` must work without a running
  compositor on the proprietary driver) needs a check on real hardware, to be
  recorded in `docs/evidence/`.

- Polish the Power menu, Settings, cursor updates, tray, and Quick Actions
  (Sync Sprint 3 S3-06, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`, ported
  from upstream `#307`/`56ec27b`, closing issues `#302`–`#306`, plus the
  focused-screen hunk from `44800ba`): Power menu labels simplify ("Log Out"
  → "Logout") and unavailable actions stay selectable so choosing one can
  explain why, instead of just disappearing from tab order. Settings opens
  fullscreen on the focused screen like System Health — reversing this same
  Unreleased section's earlier 1180x760-clamped window size. Appearance now
  scrolls vertically without diagonal drift or overscroll bounce. The system
  tray hides Blueman's redundant icon while keeping the Bluetooth widget
  itself. Quick Actions gains Self-Heal, running a user-configured script in
  a terminal with its progress and any authorization prompts visible; with
  no script configured it explains that rather than silently doing nothing
  (decision D-6: upstream parity, no default script ships, not auto-wired to
  `dwm-system-health`'s own repair flow — filed in `ROADMAP.md` Future
  Evaluation). Cursor theme/size changes now take effect immediately: a new
  `scripts/dwm-cursor-reload` (ctypes against libX11/libXcursor/libXfixes,
  no new Python dependency) replaces named cursors already held by existing
  X11 clients, and the choice is published through xsettingsd for GTK
  applications, without requiring a reboot or re-login.
  Lyona adaptations: Lyona has no `dwm-xsettings`, so cursor publication was
  built on top of `scripts/dwm-settings-display`'s existing DPI xsettingsd
  writer instead of a separate daemon-lifecycle helper — its atomic,
  symlink-safe write-and-reload logic is now a small shared, sourced
  function (`scripts/dwm-xsettings-config.sh`) so both DPI and cursor keys
  can edit the same `xsettingsd.conf` without clobbering each other, verified
  directly: writing a cursor key preserves an existing `Xft/DPI` line and
  vice versa. `scripts/theme-apply.sh` calls the new
  `scripts/dwm-cursor-reload` after applying a theme; since Lyona's
  theme-apply.sh has no upstream `STRICT_PERSONALIZATION`/`XSETTINGS_HELPER`
  concept, a failed live cursor refresh logs a warning rather than failing
  the whole apply, matching this script's existing tolerant style for other
  best-effort desktop-integration steps (gsettings, xfconf-query). Verified
  live against this sandbox's real X11 session: `dwm-cursor-reload` updates
  73–122 named cursors across runs with no errors, and the full X11
  cursor-replacement/rollback round trip (`tests/test-cursor-reload.py`,
  ported minus the `dwm-xsettings`-specific XSETTINGS-publication half,
  which doesn't apply) passes end to end under `xvfb-run`, matching the
  ported `check-cursor-reload` Makefile target. Caught and fixed along the
  way: `tests/test-dwm-settings-theme.sh`'s real `theme-apply.sh` calls were
  unintentionally reaching this sandbox's real DISPLAY, since the tests
  never explicitly isolated it, which would have live-mutated real cursor
  state on every run wherever DISPLAY happens to be set — the whole file now
  defaults `DWM_APPEARANCE_CURSOR_HELPER` to a no-op, matching a similar
  isolation fix upstream made independently in `tests/test-install-preservation.sh`
  (also ported).
- Reduce Settings startup work and readiness (Sync Sprint 3 S3-05,
  `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`, ported from upstream `#291`
  (Settings half of `d359a4f`), `#294`/`080b39e`, and Lyona's own fix for
  open issue `#315`): every Settings pane is now lazily loaded through a new
  `DeferredSettingsPane.qml` (`Loader { active: visited }`) that stays
  instantiated once visited, so switching sections preserves drafts, scroll
  positions, and each pane's own operation model instead of recreating it;
  `SettingsModel.qml` skips re-activating an already-selected section (three
  call sites) and opens with a new, narrower `refreshCapabilities()` instead
  of a full `refresh()`, since `activateSection()` already refreshes the
  newly-selected section on its own. `InputSettingsPane.qml`'s label column
  now wraps instead of pushing controls off-screen for long labels.
  `scripts/seed-autostart-overrides.sh` now strips stray `X-DWM`/`dwm`
  tokens out of a vendor entry's `OnlyShowIn` (which otherwise silently wins
  over `NotShowIn` and defeats the exclusion after a user-service restart
  reseeds it) and refuses to scope an entry that has both keys, rather than
  producing an ambiguous result.
  For open issue `#315` (no upstream fix; Lyona's own implementation):
  `DeferredSettingsPane` reserves the pane's layout space and shows a
  "Loading…" placeholder while its `Loader` is still async-instantiating,
  then fades the real content in (`Theme.reducedMotion`-aware), instead of
  popping in and reflowing the window on first visit.
  Lyona adaptations: `refreshCapabilities()` and its `capabilityRefreshPending`
  debounce didn't exist in Lyona yet (upstream had already split them out of
  `refresh()` before Sprint 3's own scope) — added them as the minimal
  dependency this port actually needs, without porting the unrelated
  `capabilityById()` staleness guard that came bundled with them upstream,
  since nothing in this diff touches that function. New
  `tests/test-quickshell-settings-responsiveness-xvfb.sh` (with
  `tests/fixtures/settings-responsiveness.py` and
  `tests/qml/SettingsResponsiveness.inc`) verified passing end to end against
  the real `quickshell` runtime. Upstream's `#295`/`8df119c` (a race fix for
  a "restart quickshell, verify notification policy persisted" test) was
  **not ported**: that test scenario doesn't exist in Lyona, which already
  tests notification-policy persistence a different, race-free way (through
  `ipc`-polled `policyState` assertions in
  `tests/test-quickshell-large-surfaces-xvfb.sh`, tracing back to Lyona's own
  history rather than upstream's `#204`) — there is nothing for the fix to
  apply to. `.github/PULL_REQUEST_TEMPLATE.md`, `AGENTS.md`, `CONTRIBUTING.md`,
  `TASKS.md`, and `docs/PRE-P7-MAINTENANCE.md` changes were not ported
  (review-process wording and Lyona's own separately-maintained planning
  docs).
- Hide the Docked/Undocked automatic-layout controls when no system battery
  is present (Sync Sprint 3 S3-03, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  upstream issue `#310`, still open upstream — no upstream code exists, this
  is Lyona's own implementation): `scripts/dwm-settings-display-profiles`
  gains `system_battery_present()`, reading
  `/sys/class/power_supply/*/{type,scope}` and treating only `type=Battery`
  with a `scope` other than `Device` (or no `scope` file, for older ACPI
  drivers) as a real system battery — peripheral HID batteries (mice,
  keyboards) report `scope=Device` and are excluded, matching the issue's
  acceptance criteria exactly. `status()` reports the new `battery` field and
  returns early (empty profiles) when it's false. Settings' new
  `automaticDisplaysRelevant` property binds the whole "Automatic layouts"
  section's visibility to that field. Verified against this sandbox's real
  `/sys/class/power_supply`, which holds exactly the peripheral case the
  issue calls out (a `hidpp_battery_18` wireless-mouse battery,
  `scope=Device`): `system_battery_present()` correctly excludes it and
  reports `battery: false`.
- Add explicit Docked and Undocked automatic display layouts to Settings
  (Sync Sprint 3 S3-02, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`, ported
  from upstream `#290`/`6b7548b`): a new unprivileged
  `scripts/dwm-settings-display-profiles` (Python) edits autorandr's `mobile`
  (Undocked) and `docked` profiles without ever applying a layout — autorandr
  itself applies it at login/hotplug. Settings gains saved-layout previews,
  detected/currently-applied status, draft editing (Edit saved/Create draft),
  and confirmed saves with backups, alongside the existing manual "Saved
  layouts" (named, privileged Use-at-next-login) controls, which this does
  not touch. Confirmed saves merge `set,crtc` into autorandr's
  `skip-options` so session-specific CRTC assignments and output properties
  can't invalidate layout matches.
  Lyona adaptations: `autorandr` added to the `arch:desktop-optional`
  package group (`scripts/dwm-packages.sh`) so a missing package degrades
  the automatic-layouts UI rather than failing installs — verified on this
  sandbox, where `autorandr` is genuinely absent, that `status()` reports
  `available: false` with the adapted message instead of erroring; the
  install message itself reads "Install the optional autorandr package
  (pacman -S autorandr)...", not upstream's Fedora wording; backups move
  from upstream's `~/.config/dwm-titus/display-profile-backups/` to
  `~/.config/lyona/display-profile-backups/`, matching the existing
  `~/.config/lyona/display-profiles` convention; the Python helper is
  registered in `INSTALL_COMMANDS` only (not `check-shell`/`check-format`),
  matching the existing `dwm-system-management` exception, with its own new
  `check-display-profiles` Makefile target rather than folding into
  `check-settings` as upstream does. `scripts/autostart.sh` runs no
  competing profile-apply at login, so no autostart change was needed.
- The CI package set and environment now have one source each (#92). The
  full-suite workflow and `scripts/ci-local.sh` each assembled the package list
  by hand (three profiles plus a literal list of extras) and repeated the job's
  environment (image, security options, the `nobody` runner's directories). A
  new `ci-full` profile in `scripts/dwm-packages.sh` (with `ci-tools` for the
  extras) is now what both install, and a new `scripts/ci-env.sh` holds the
  constants that `ci-local.sh` uses; the workflow, being YAML, repeats the values
  and the new `make check-ci-parity` fails if the workflow, `ci-local.sh` and
  `ci-env.sh` drift apart, or if either one grows a package list of its own. The
  generated list is byte-identical to the old one (114 packages), so the
  cached `ci-local.sh` image stays valid.

- Replace the Displays pane's raw X/Y position inputs with relative
  placement (Sync Sprint 3 S3-01, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  ported from upstream `#289`/`55dbd76`, plus `6b7548b`'s driver-quirk fix to
  `discover()` pulled in early since it affects placement too): a new pure
  `config/quickshell/settings/DisplayLayout.js` computes placement math and a
  numbered, proportionally-scaled layout preview from monitor geometry; each
  output card now has a "position relative to" selector and Left of/Right
  of/Above/Below buttons instead of numeric X/Y fields.
  `scripts/dwm-settings-display discover()` emits new `mode-size` records
  parsed from `xrandr --verbose`, since RandR mode labels are driver-arbitrary
  strings that can't reliably be parsed for pixel dimensions.
  Lyona adaptations: the upstream diff was ported into Lyona's existing
  `DisplaySettingsPane.qml` and `SettingsModel.qml` rather than taking
  upstream's files, since Lyona's pane already carries the resolution
  countdown, `ShellButton` primary/pending states, and DPI-decoupling
  workflow from an earlier sync phase; every new pixel constant in the
  preview tile is wrapped in `Theme.dp()`. Verified against this sandbox's
  real dual-monitor hardware (`DisplayPort-0` 2560x1440 normal/primary,
  `DisplayPort-1` 1920x1080 rotated right at x=2560): `discover()` emits
  correct `mode-size` records for both real outputs.
- Close `ROADMAP.md` Phase 6 (System Management) (Sync Sprint 2 S2-07,
  `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, upstream closed its own Phase 6
  with docs-only commits whose Fedora-44-evidence prose isn't ported; used as
  a qualification checklist instead): measured, not assumed, idle CPU with
  all seven `watch-*` domains (updates, time, locale, accounts, printers,
  storage/`watch-mounts`, security/`watch-units`) subscribed — a new
  CPU-sampling stage in
  `tests/test-quickshell-system-management-xvfb.sh`, Phase 5's own
  closed-shell methodology applied to this pane's live subscriptions, read
  0.00% and 0.50% across two runs. Added a new "System information, storage,
  and security" record-source reference and a "Settings Information Card and
  Health Navigation" section to `docs/P6-SYSTEM-MANAGEMENT.md`. `ROADMAP.md`
  Phase 6 is now `Status: Complete (2026-09-19)` with a Completion Evidence
  section recording D-5's permanent firewall-manager generalization and the
  sprint's carried-forward limitations (no PackageKitGlib bindings or
  multi-monitor hardware in this sandbox; `xkbset` still unavailable, carried
  from Phase 5). `docs/UPSTREAM-SYNC.md`'s status table now reflects Sprint 1
  and Sprint 2 as done. `TASKS.md` replaced with a first-pass Phase 7 (Arch
  Image and Release Qualification) task breakdown, grounded in
  `docs/RELEASING.md`'s own already-documented gap ("has not been
  boot-tested end-to-end on real hardware or in a VM") rather than invented
  from nothing; genuinely open questions (legacy BIOS scope, specific
  hardware/VM targets, NVIDIA hardware availability) are flagged inline for
  the user to resolve rather than guessed, per their own explicit direction
  when asked how to scope it.
- Add the System Settings information card and Health navigation for the
  minor-2 records S2-05 wired in (Sync Sprint 2 S2-06,
  `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported from upstream `#287`,
  commits `cc96efd`/`0c9d07c`; `39ce924` targets a harness Lyona never
  ported, nothing to port): new
  `config/quickshell/settings/SystemInformationControls.qml` renders system
  information, a virtualized (240px, bounded to 256 rows) storage overview,
  privacy/security status, and diagnostics/recovery guidance in the System
  pane. The fixed "Open System Health" button calls the now-wired
  `SystemManagementModel.openHealth()`, which opens the existing
  `dwm-system-health` full-screen window and closes Settings;
  `shell.qml` resolves the target screen through a three-way fallback (the
  Settings window's own current screen, then a requested screen, then the
  active panel's screen) so Health always opens where Settings actually was,
  including after the window moved between screens.
  Lyona adaptations: the security list carries D-5's 7 identifiers
  (`firewalld`/`ufw`/`nftables` as three distinct rows, not upstream's single
  "Firewall service" row); action-availability checks read `.status`, not
  upstream's `.availability` (matches `parseSnapshot()`'s actual field name —
  the same mismatch already found and fixed for `canNtp` back in S1-08);
  recovery guidance names Arch/Lyona tooling (`pacman -Qkk`, `arch-chroot`
  from the Lyona installation media, `lyona-update rollback`) in place of
  upstream's Fedora-specific `dnf`/`rpm -Va`/Anaconda rescue references, with
  a grep gate now built into `tests/test-quickshell-system-management.sh` so
  none can silently reappear.
  Also ported upstream's `tests/qml/SystemInformationUi.qml` and
  `tests/qml/SystemHealthNavigation.qml` harnesses, each as Lyona's own
  standalone `tests/test-quickshell-{information-ui,health-navigation}-xvfb.sh`
  + `Makefile` target (following `tests/test-quickshell-update-ui-xvfb.sh`'s
  established isolated-shell.qml pattern, `cp -a`-ing the real
  `config/quickshell` directories into a scratch dir rather than upstream's
  single-giant-xvfb-file convention) — the health-navigation one
  programmatically extracts `shell.qml`'s actual `targetScreen:` expression
  via a small Python template step, so it can never silently drift out of
  sync with the real production binding. Verified: both new xvfb suites pass
  3/3 consecutive runs (the information view across all three of upstream's
  own evidence window sizes); the full `tests/test-quickshell-system-management-xvfb.sh`
  integration suite and full-tree qmllint (still the same 15-warning
  baseline) both stayed clean after wiring the new card into the live pane.
- `scripts/ci-local.sh --each --jobs N` runs the check targets on N containers at once
  (#86). The targets are dealt longest first to the least-loaded worker, using the
  durations the previous run recorded (`scripts/ci-schedule.sh`, unit-tested by
  `make check-ci-schedule` without Docker), the output is prefixed `[wN]`, and the
  summary lists every failure plus any target that did not run because its worker
  died, with a ready-to-paste `--targets "..."` line to rerun them. N is capped by
  the cores and the target count. The run says up front that a parallel pass is a
  weaker signal than a serial one, since timing-sensitive tests can fail under the extra load.
  `scripts/ci-validate-parallel.sh` records the required serial comparison and five
  four-worker runs, including every per-target outcome and timing.

- Wire the information/storage/security readers from S2-01 through S2-04
  into the system-management snapshot protocol as minor `2`, both on the
  Python provider and the Quickshell consumer (Sync Sprint 2 S2-05,
  `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported from upstream `#285`/
  `#286`, commits `7954c54`/`177e3c3`/`b19fb90`/`3232932`/`4aee614`):
  `InformationSnapshotSources`/`build_information_snapshot()` assemble the
  new records; `snapshot`/`snapshot-core`/`snapshot-without-storage` are now
  three distinct fixed CLI commands — a required (recovery-only) read always
  asks for `snapshot-core` (native rows only, no information block, so it
  never opens the filesystem inventory's unmonitored initialization gap or
  falsely marks storage/security as freshly re-verified when it didn't
  actually probe them); an optional read asks for `snapshot-without-storage`
  until the `storage` domain's own `watch-mounts` subscription is ready,
  then `snapshot`. New
  `config/quickshell/systemmanagement/SystemInformationProtocol.js` mirrors
  the Python side's ownership/validity rules for the QML parser
  (`SystemManagementModel.qml`) without duplicating either list. Two new
  discovery domains, `storage` and `security`, join the existing four in
  `SystemProviderDiscovery.qml`, which also gained upstream's per-launch
  isolated monitor (a `generation`/`serial`-stamped identity and callback
  set created fresh per `Process` launch via `Component.createObject()`), so
  a stale timer, parser line, or exit signal from a retired monitor can
  never be mistaken for a replacement one's, even within one pane cycle.
  `openHealth()`/`healthModel`/`targetScreen`/`onHealthOpened` wire the
  `health-open` action through to the existing `dwm-system-health` view,
  closing Settings on open.
  Lyona adaptation (D-5): `INFORMATION_SECURITY_IDS`/`securityIds()` carry 7
  identifiers (selinux, secure-boot, firewalld, ufw, nftables,
  root-encryption, screen-lock), not upstream's 5 — `InformationSnapshotSources.security()`
  dispatches firewall identifiers through the existing `read_firewall_status(kind)`
  from S2-02; every state-count assertion (Python and QML) is 21, not
  upstream's 19.
  **Real bug found and fixed during verification** (not a mechanical port
  issue — a genuine correctness gap this session's own live xvfb testing
  caught): a required (recovery-only) snapshot read can silently "steal" the
  exact execution slot that a *different*, settling discovery domain's own
  pending-cycle signal had just triggered, because a queued
  `root.requiredPending` flag upgrades the very call that signal produced.
  Since required reads intentionally skip discovery-token draining, that
  domain's cycle was left stuck in `settling-pending` forever with nothing
  left to re-trigger it — reproduced live via a delegated `printers-open`
  dispatch that never recovered even after 100 seconds of retries. Fixed in
  `SystemManagementModel.qml`'s `requestSnapshot()`: when a call proceeds as
  required and other domains still have work pending, it now queues
  `root.snapshotPending = true` so the existing `onRunningChanged` retry
  logic follows up with a real optional drain once the required read
  finishes.
  Also fixed a pre-existing, unrelated dead/wasteful code path found in the
  same function while making this required edit: `main()`'s `try: backend =
  PackageKitBackend(); lines = build_snapshot(backend)` discarded that
  second call's result unconditionally a few lines later; removed.
  New `tests/qml/tst_system_information_protocol.qml` (16 tests, matching
  `tst_system_regional_preflight_protocol.qml`'s established pattern for
  testing a pure `.pragma library` protocol file directly) — a Lyona-specific
  addition per the sprint document's own suggestion, since upstream never had
  a dedicated test file for this library. Did not port upstream's separate
  `tests/qml/SystemNativeDiscovery.qml`/`SystemProviderGeneration.qml`
  integration-level harness (`b19fb90`, `3232932`) or the matching
  `ComposedFixtureSnapshotTests` Python class (`4aee614`) and their
  supporting fixtures — Lyona never ported that harness family for the
  original four discovery domains either, and the generation/serial monitor
  isolation it targets is already exercised end-to-end (including the
  starvation-bug fix above) by the existing, much larger
  `tests/test-quickshell-system-management-xvfb.sh`, which this change
  extends with new minor-2 content, six-domain-readiness, and
  `openHealth()`/Settings-closing assertions instead.
  Verified live on this sandbox: `snapshot`/`snapshot-core`/
  `snapshot-without-storage` all produce correct real output (real OS/
  hardware/security/filesystem data at minor 2, correctly empty/partial
  information at minor 1 and mid-storage-startup); the full ported
  `InformationSnapshotTests` (10 tests) and new `tst_system_information_protocol.qml`
  (16 tests) pass; the xvfb integration suite passed 5/5 consecutive runs
  including the new S2-05 assertions; the full `tests/test-system-management.py`
  suite (684 tests) matches the established baseline (only the 16 pre-existing,
  unrelated PackageKitGlib-unavailable failures in this sandbox).
- Add a bounded mount change monitor to `dwm-system-management` (Sync Sprint
  2 S2-04, `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported from upstream
  `#284`, commits `5b246a0`/`dbbfde1`/`994011f`/`088069b`/`6ac6f5a`):
  `watch-mounts` supervises one fixed `findmnt --poll` child, arming
  parent-death cleanup (`prctl(PR_SET_PDEATHSIG)`) and re-checking the
  original parent PID to close the startup race before `execv`. Readiness is
  observed only from the live, unreaped child's own `/proc/PID/fd` — the
  exact `mountinfo` descriptor opened without `O_CLOEXEC` — never a merely
  temporary parsing descriptor, and never before a one-second deadline
  expires. A pidfd and a signal-wakeup pipe alongside the child's output mean
  no idle polling timer runs once ready. The helper requires write-only pipe
  output (as Quickshell supplies): a socket can half-close without an event,
  and a read/write FIFO retains its own reader, so both are rejected before
  starting a child, and losing the pipe's reader is itself a bounded event,
  not an idle spin. `parse_filesystem_information()` now rejects (rather
  than silently discarding into "partial") a filesystem inventory beyond its
  256-record limit, since silently dropping is not the same information as
  what a client asked for. Lyona adaptation: replaced upstream's one
  Fedora-specific comment about `CLOEXEC` parsing-descriptor timing with
  neutral wording, since Lyona never targets Fedora; confirmed `findmnt`
  (util-linux) is already tracked in `arch:runtime-required`. Verified on
  this sandbox with a real unprivileged mount namespace (`unshare -rm`):
  `watch-mounts` correctly reports `mount-monitor-ready` then
  `mount-change\tmount`/`mount-change\tumount` for actual `mount -t tmpfs`/
  `umount` calls. The full ported `MountMonitorTests` suite (15 tests,
  including real subprocess signal-cleanup, orphan-reaping, and an
  `LD_PRELOAD`-based real-`findmnt` timing test) passes 3/3 consecutive
  runs. Does not yet wire `watch-mounts` into the snapshot protocol or
  `SystemProviderDiscovery.qml`'s domain list — that's S2-05.
- Reuse the shared power helper's automatic screen-lock evidence in
  `dwm-system-management` through a bounded internal information reader
  (Sync Sprint 2 S2-03, `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported
  from upstream `#282`, commits `92c4543`/`76d0739`/`2fe6f7d`):
  `read_screen_lock()`/`parse_screen_lock()` consume
  `dwm-quickshell-controlcenter power-lock-snapshot`, a new lock-only
  snapshot that reuses `power_status()` without querying UPower, profiles,
  suspend, or lid policy. Hardened the shared probe per upstream: the xset
  screen-saver timeout and gsettings lock-after/lock-on-suspend values are
  now bounds- and type-validated, reporting `partial` (not stale configured
  fallback values) on malformed evidence, tracked through a new
  `lock_malformed` status row. Locker readiness now matches the user's
  effective UID and current `DISPLAY` through bounded procps environment
  matching, so a locker on another display or missing display evidence
  cannot establish readiness. Lyona adaptation: Lyona autostarts
  `dwm-lock-watch` (a reactive watcher for logind's `Lock` signal,
  independent of X11-idle timeouts) alongside `light-locker`; a new
  `configured_lock_running()` recognizes either mechanism as "running"
  evidence when `power_lock_managed=1`, while `start_configured_light_locker`/
  `stop_configured_light_locker` keep using the light-locker-only,
  DISPLAY-scoped check since they only ever manage that daemon's own
  lifecycle. `dwm-watchdog.sh`'s shared `run_bounded()` gained an optional
  `bounded_foreground` flag so a nested X11/GSettings probe stays inside the
  information reader's own timeout-owned process group instead of escaping
  it. `PowerModel.qml`/`PowerSettingsPane.qml`/`ControlCenterWindow.qml` now
  show "Unknown" instead of a stale enabled/disabled/timeout value when the
  lock record isn't `available`. Verified against this sandbox's real
  session: `power-lock-snapshot` and `read_screen_lock()` both correctly
  report `available`/`enabled` from the real X11/gsettings/light-locker
  state; `tests/test-quickshell-power-backend.sh` (including a new
  Lyona-specific managed-lock case exercising real `dwm-lock-watch`
  evidence via `pgrep --pid`) and `tests/test-quickshell-controlcenter.sh`
  pass 3/3 consecutive runs; the full `tests/test-system-management.py`
  suite (659 tests, +8 new `ScreenLockTests`) passes with only the
  pre-existing, unrelated PackageKitGlib-unavailable failures.
  `tests/test-quickshell-settings-xvfb.sh`'s new lock-record fixture cases
  were ported but could not be executed in this sandbox, which lacks the
  suite's required `xkbset` binary (a pre-existing, unrelated gap).
- Add bounded security status readers to `dwm-system-management` (Sync
  Sprint 2 S2-02, `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported from
  upstream `#280`/`#281`): `read_selinux_status()` (runtime enforcement
  first, config fallback only when the runtime interface is absent),
  `read_secure_boot_status()` (the fixed EFI `SecureBoot` variable, never
  inferring "disabled" from mere absence or a denied read),
  `read_root_encryption()` (resolves LUKS/dm-crypt ancestry above `/` from
  bounded `lsblk --json`, requiring a complete, unambiguous block-device
  graph before claiming either answer). Lyona adaptation (D-5, decided
  2026-09-16): upstream's `FirewalldRead` only ever asks about
  `firewalld.service`, but a default Arch/CachyOS install runs no firewall
  at all -- generalized into `FirewallUnitRead`/`read_firewall_status(kind)`
  over `firewalld`, `ufw`, and `nftables`, the same real, distinct systemd
  units either package ships, so the eventual Settings card shows honest
  per-manager status instead of only ever reporting on firewalld. Verified
  against this sandbox's own real system: SELinux correctly `unsupported`,
  Secure Boot correctly read as disabled from the real EFI variable,
  firewalld/ufw correctly `unsupported` (not installed) while nftables
  correctly reads as installed-but-disabled, and root encryption correctly
  resolves to `unencrypted` from this machine's real block-device topology.
- Add bounded local, hardware, and filesystem information readers to
  `dwm-system-management` (Sync Sprint 2 S2-01,
  `docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md`, ported from upstream
  `#277`/`#278`/`#279`): `read_local_information()` reads OS identity
  (`/etc/os-release`), CPU model (`/proc/cpuinfo`), memory/swap
  (`/proc/meminfo`), kernel release/architecture (`uname`), logical CPU
  count, and boot-time uptime, each field failing independently rather than
  blanking the whole read. `read_hardware_information()` reads vendor/model
  from `org.freedesktop.hostname1` over a fresh, bounded D-Bus connection.
  `read_filesystem_information()` runs a fixed, deadline-bounded
  `findmnt --json` and validates its output into per-mount rows (source,
  target, filesystem type, size/used/available bytes), rejecting duplicate
  or oversized JSON without losing valid peer rows. None of this is wired
  into the snapshot protocol or any UI yet -- that starts at S2-05.
  Lyona adaptation: upstream's OS-identity mapping only reads `VERSION_ID`,
  which renders "unknown" on Arch and CachyOS since both are rolling
  releases with no `VERSION_ID` at all; `parse_os_information()` now falls
  back to `BUILD_ID` (which Arch's `os-release` sets to `rolling`) only
  when `VERSION_ID` itself was not available, verified against both a
  synthetic fixture and this repository's own CachyOS sandbox.
- Add a manual `Full suite (manual)` GitHub Actions workflow
  (`.github/workflows/full-suite.yml`, Sync Sprint 1 S1-01,
  `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`) that runs `scripts/run-tests
  make check` (or one named target) as an unprivileged user in an
  `archlinux:base-devel` container, uploads the log, and optionally builds
  dwm with clang. Push and pull-request CI is unchanged.
- Add confirmed delegated administration (Sync Sprint 1 S1-04,
  `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`, ported from upstream `#266`/`#267`):
  the Accounts/Password/Printers/Software-sources launch buttons in
  Settings → System now show a visible "Open *tool*?" confirmation card
  before launching, the same as regional (timezone/NTP/locale) changes
  already do, instead of dispatching on the first click.
  `SystemManagementModel.qml` gains `nativeConfirmation`/
  `prepareDelegate()`/`confirmDelegate()`/`discardDelegate()`/
  `delegateActionReason()`, replacing `launchDelegated()`, which dispatched
  immediately with no confirmation step. A live account or printer change
  retires an in-progress confirmation prepared against stale data. The new
  `config/quickshell/settings/SystemDelegateControls.qml` also lists the
  accounts and software sources the system currently reports, read-only.
  D-3 (`accounts-open`/`sources-open` permanently `unsupported` on Arch, no
  `lxqt-admin-user`/`dnfdragora` equivalent) is unchanged; their launch
  buttons stay disabled and now show the helper's own reason text.
- `dwm.c` floating code separates mechanism from policy, and names its shared
  pieces (#91; no behaviour change). `setfloating(c, shrink)` does the toggle and
  `shrink` alone decides whether a tiled client pops out smaller: `togglefloating`
  (keys and buttons) passes 1 and the two mouse-drag paths pass 0, where before
  `togglefloating(NULL)` meant "this is a drag" by an unenforced convention.
  `restack()` and `raiseselectedclient()` share `restackraisesselected()` instead
  of each spelling out "floating, or the floating layout". The pop-out percentage
  is `FLOATSHRINKPCT` in `config.def.h` (default 85; `dwm.c` falls back to 85, so
  a `config.h` written before it existed still builds), and
  `docs/PATCH-OWNERSHIP.md` gains a "Stacking and floating geometry" section.
  `make check-dwm-floating-guards` pins the structure and the default; compared
  at `-O0`, `shrinkfloating` compiles to identical code and the mouse paths differ
  only at the call.

- Give regional (timezone/locale/NTP) preview and confirmation its own model
  (Sync Sprint 1 S1-05, `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`, ported
  from upstream `#268`/`#269`): the new
  `config/quickshell/systemmanagement/SystemRegionalSettingsModel.qml`
  replaces the regional preview/confirm state that used to live directly on
  `SystemManagementModel.qml` (`regionalPreview`/`prepareRegional()`/
  `confirmRegional()`/`discardRegional()`), the same split S1-04 already
  gave delegated actions. `SystemRegionalControls.qml` is rewritten to
  match: timezone and locale changes now load a reported choices catalog
  first and require an exact selection from it, rather than accepting free
  text, before reviewing and confirming a change. A pending update,
  delegated, or regional confirmation now blocks starting any of the other
  two consistently in both directions -- closing gaps in the S1-04 mutual
  exclusion where an update confirmation in flight did not block starting a
  delegated one, and a live confirmation-invalidation signal did not clear
  a pending delegated confirmation.
- `scripts/ci-local.sh --clang` now runs the workflow's clang job the way the
  workflow does (#87): a clean container with only the `build` profile and clang,
  as root, `make clean all CC=clang`. It was `pacman -S clang` into a container
  that already had every package, which could hide a build dependency missing from
  the `build` profile and re-downloaded clang on every run. That container's image
  is cached as `lyona-ci-clang:<hash>` (about 2 GB, built in a minute, rebuilt when
  the `build` profile changes or with `--refresh`), and the suite's image is
  untouched. `--clang-only` runs just this leg. Checked by dropping `libxft` from
  the `build` profile: the leg now fails on the missing `xft`.

- Share one timezone-aware minute clock between the panel and Settings
  (Sync Sprint 1 S1-06, `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`, ported
  from upstream `#270`): the new `config/quickshell/core/ClockModel.qml`
  replaces a bare `SystemClock` instance in the panel that never noticed a
  live `timezone-set` change -- Qt's `Date` does not re-read the system
  timezone on its own, so nothing previously called
  `Date.timeZoneUpdated()` after a confirmed timezone mutation. The
  System Settings page now also shows the current local date and time next
  to the timezone/locale controls.
- Add a bounded, event-driven read path for network time status to
  `dwm-system-management` (Sync Sprint 1 S1-07,
  `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`, ported from upstream
  `#271`/`#272`/`#273`): new `ntp-sample` and `time-status` CLI commands
  publish one finite record each, and a new `watch-time` command emits a
  `time-event\towner-arrived` record distinct from an actual `timedate1`
  property change, separating "the service came back, state is uncertain"
  from "state actually changed" for the first time. A local stop (SIGTERM/
  SIGINT/SIGHUP) during a regional change or its verifying read now
  terminalizes the in-flight journal operation as `interrupted` and returns
  promptly instead of leaving it ambiguous or blocking on the change's own
  timeout; a repeated stop coalesces rather than reordering cleanup, and an
  unrelated `SystemExit` (such as the locale catalog collector's own signal
  handling) is never reclassified as a stop. `finite_status_command()` also
  fixes a case the ported test suite caught during development: a closed,
  readonly, or Python-level-closed stdout previously reached the network
  read before failing on the write, wasting a live D-Bus round trip on
  output nobody could receive; it now fails immediately instead.
- Reconcile network-time-service owner arrivals and sample synchronization
  while System Settings is open (Sync Sprint 1 S1-08,
  `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`, ported from upstream
  `#274`/`#275`/`#276`): the "time" domain now watches with S1-07's
  `watch-time` instead of `watch-regional time`, so an authenticated
  `timedate1` owner arrival (uncertainty) is reconciled with a bounded
  `time-status` read through the new `SystemTimeReconciliationModel.qml`,
  instead of being treated as an unconditional invalidation the way every
  other watched property change is. A confirmed `ntp-set` change now also
  triggers an immediate `ntp-sample` read, and network time synchronization
  is sampled every 30 seconds while Settings is open rather than only at the
  last full snapshot; `SystemRegionalControls.qml` preserves and restores
  keyboard focus around either read the same way it already does around a
  regional confirmation. Found and fixed along the way: porting
  `tests/qml/SystemRegionalPreflightOwner.qml` (upstream's own bespoke
  integration harness for `SystemRegionalPreflightModel.qml`, closing a
  coverage gap Sync Phase 9 deferred) against a real Quickshell process
  surfaced a real crash -- `SystemRegionalPreflightProtocol.js`'s `consume()`
  threw a `TypeError` on the empty buffer a reused `StdioCollector` can
  deliver when its process restarts or fails to start, never previously
  exercised; a `0`-byte buffer is now a no-op instead.
- Show live per-package update progress and recover user-service session
  evidence (Sync Sprint 1 S1-09, `docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`,
  ported from the system-management half of upstream `#291`): PackageKit's
  `Package`/`ItemProgress` signals now publish a bounded, ephemeral
  `package-progress` record (name, phase, percent) separate from the
  operation's own overall progress and log, and System Settings shows it as
  a labeled progress bar in place of the previous raw operation-log
  scrollback. A terminal operation's `error` record now always carries the
  operation's own detail rather than a caller-supplied override, so a failed
  acknowledgment's recovery instructions ("Reload status to retry") stay
  visible instead of being replaced by unrelated internal audit text. Restart
  evidence (`session_started()`) now also works when the helper is launched
  as a `systemd --user` service outside any login session scope: it falls
  back to logind's verified primary graphical display instead of failing
  outright on `NoSessionForPID`, re-verifying that display's identity hasn't
  changed before trusting its session timestamp. Ported and verified at the
  Python and QML-model/protocol layers (7 new/adapted Python tests, 1 new
  qmltestrunner test), plus upstream's own dedicated `SystemUpdateUi.qml`
  xvfb integration harness (a pre-`#291` file, predating this item by a
  long way -- see the sprint doc's S1-09 implementation notes) as
  `make check-quickshell-update-ui-xvfb`: porting it surfaced and fixed a
  real gap in its own fixture, not in production code -- with no active
  operation and a `partial` recovery reading, `journalAdmitted` (S1-03,
  from upstream's `#262`) had no evidence to trust the journal, since this
  update-only fixture never emitted the minor-1 native provider/state/
  action rows a real `dwm-system-management` always does; `operationModel`
  correctly, if unhelpfully, retried into `blocked`. Fixed in the fixture,
  not the model.
- Add a durable, crash-safe operation journal to `dwm-system-management`
  (Sync Phase 5, `docs/SYNC-P5-OPERATION-JOURNAL.md`): a double-buffered
  8,192-byte frame codec, an `openat`-relative directory chain hardened
  against symlink/group-writable tampering, operation/restart/handoff record
  codecs, admission control, and collision-safe operation IDs. Ships no
  user-visible behavior on its own — it is the crash-durable record Sync
  Phase 6 writes into and recovers from.
- Turn the journal into a working, confirmed execution owner (Sync Phase 6,
  `docs/SYNC-P6-UPDATE-EXECUTION.md`): `dwm-system-management` gains
  `updates-refresh`, `updates-install-all GENERATION`,
  `watch-operation OPERATION_ID`, `ack-operation OPERATION_ID`, and
  `updates-cancel OPERATION_ID` CLI commands that actually run PackageKit
  transactions, stream bounded progress, can be cancelled, and recover exact
  evidence (never a fabricated success) after a crash or shell restart mid
  update. `require_mutation_safe()`'s PackageKit-version gate now checks the
  daemon's own D-Bus version properties directly instead of Fedora's RPM
  database (Arch has neither). Still CLI-only; the Settings/Control Center
  button is Sync Phase 7. `config/quickshell/systemmanagement/SystemManagementModel.qml`
  gains `active-operation`/`terminal-handoff` snapshot parsing so a
  Quickshell restart mid-update can reattach via `watch-operation` instead of
  showing nothing.
- Put a button on the confirmed execution path (Sync Phase 7,
  `docs/SYNC-P7-OPERATION-SURFACE.md`): Settings -> System can now refresh
  PackageKit metadata and install Arch updates, not just read their status.
  `SystemOperationProtocol.js` (new) is a pure UTF-8-safe stream parser over
  `watch-operation`/`ack-operation` output; `SystemOperationModel.qml` (new)
  owns the process lifecycle over it, including reattaching to an operation
  the shell did not start after a Quickshell restart. Confirmation is a
  captured snapshot, not a flag: `SystemManagementModel.qml`'s
  `prepareUpdate()`/`confirmUpdate()` re-validate the plan's generation, this
  model's own read counter, and the live discovery cycle epoch all still
  match at confirm time, invalidating the prompt rather than dispatching a
  stale plan. `SystemUpdateControls.qml` (new) is the confirm/cancel UI,
  mounted in the System pane above the status grid, with live progress, a
  verified-result card, and cancellation gated on PackageKit reporting it
  safe. `build_snapshot()`/`build_managed_snapshot()` now thread a
  `mutation_blocker`/`mutation_failure` result so `updates-refresh`/
  `updates-install-all` actually report `available` once recovery evidence
  and `require_mutation_safe()` allow it -- ported from the same upstream
  commit as the rest of this phase, but missed in the original port (found
  and fixed while starting Sync Phase 8; without it every confirm/cancel
  control above was unconditionally disabled).
- Add five bounded, read-only backend readers to `dwm-system-management`
  (Sync Phase 8, `docs/SYNC-P8-REGIONAL-READERS.md`): system timezone/NTP
  (`RegionalRead`), locale (`RegionalRead`, `read_locale_choices()`), the
  local `AccountsService` account list (`AccountRead`, current-user-reserved,
  concurrency-bounded, overflow-safe), CUPS's running state (`CupsRead`,
  a systemd unit query, not a print-queue connection), and the PackageKit
  repository list (`RepositoryRead`, reusing the update snapshot's
  transaction handshake). Four `ServiceRead` subclasses back these five
  reads (`RegionalRead` is instantiated fresh per kind, for both the
  timezone/NTP and locale reads); each read is its own single-use instance
  with an independent deadline, so one source failing (e.g. `timedate1`
  unreachable) never blanks another. No mutation, no D-Bus write, and
  no caller yet -- these are backend building blocks with no snapshot
  protocol record, model property, or Settings row until Sync Phase 9 wires
  them into the snapshot alongside the timezone/NTP/locale/account/printer/
  source mutation and delegated-tool-launch actions.
- Wire Sync Phase 8's readers into a confirmed timezone/NTP/locale mutation
  path and delegated administration (Sync Phase 9,
  `docs/SYNC-P9-REGIONAL-MUTATION.md`): `dwm-system-management` gains
  `regional-choices`/`regional-preview` read-only preflight commands, a
  confirmed `timezone-set`/`ntp-set`/`locale-set` mutation path
  (`RegionalMutation`) that never fabricates a terminal state -- a sent
  change whose reply is lost is reported `interrupted`, never guessed
  success or failure -- and `accounts-open`/`password-open`/
  `printers-open`/`sources-open` delegated tool launching, each a fixed,
  root-owned, isolated `posix_spawn`. Since a regional/delegated operation
  has no PackageKit transaction to attach to, it gets its own crash-durable
  journal-owner lease (a dedicated `flock` on the active record, independent
  of the directory admission lock) and its own inotify-based watch.
  `watch-regional time|locale`, `watch-accounts`, and `watch-units printers`
  generalize Sync Phase 4's update monitor into a live-watch family covering
  four more domains. `accounts-open` and `sources-open` ship permanent
  `unsupported` on Arch -- neither `lxqt-admin-user` nor `dnfdragora` is
  packaged for it, and `system-config-printer` (`printers-open`) is the only
  one of the four with a real target; edit `/etc/pacman.conf` directly for
  repositories. `SystemRegionalPreflightProtocol.js`/
  `SystemRegionalPreflightModel.qml` (new) are the QML-side parser and
  process lifecycle for the read-only preflight commands, ported unchanged
  from upstream. This closes out Sync Phase 9 and, with it, the whole
  nine-phase system-management port -- Settings UI wiring for all of this
  (pickers, toggles, launch buttons) is left for later, same as it was for
  every reader Sync Phase 8 added.
- Add the Sync Phase 9 Settings UI (`sync-p9-settings-ui`, PR #33): a new
  `config/quickshell/settings/SystemRegionalControls.qml` (timezone/locale
  pickers, NTP toggle, delegated-launch buttons, a confirmation card) mounted
  in `SystemSettingsPane.qml`; `SystemOperationModel.startRegional()`/
  `startDelegated()` and `SystemManagementModel`'s `prepareRegional()`/
  `confirmRegional()`/`discardRegional()`/`launchDelegated()` family driving
  a private `SystemRegionalPreflightModel` instance; and `shell.qml` IPC
  probes for regional preview/confirm and delegated launch. This is the
  Settings UI half Sync Phase 9's own entry above left for later --
  timezone/locale/NTP changes and delegated administration (accounts,
  password, printers, sources) are now reachable from Settings, not only the
  CLI. `launchDelegated()` dispatches without its own confirmation step;
  Sync Sprint 1 (`docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`) converges this
  surface onto upstream's structure, which adds one.
- Add the update surface to Settings and Control Center (UPDATE-003,
  `docs/P6-UPDATE-SURFACE.md`): a new `config/quickshell/system/UpdateModel.qml`
  root model over `lyona-update`/`lyona-version`, and a Settings -> System pane
  showing the installed-version card (turning red and naming which of
  system/user/binary disagree when the install is damaged), current update
  status, a confirmed **Update now** action with phase-by-phase progress
  (downloading, verifying, building, installing, verifying, restarting), a
  stable/preview channel selector, and a backups list with per-backup
  rollback. Control Center gets a one-line installed-version row plus a
  conditional **Update available** row when behind — no apply action there by
  design, since a multi-minute privileged operation does not belong behind a
  one-click row. `lyona-update` gained `set-channel` (persists the channel
  selection through the same seed-never-overwrite `update.conf` convention)
  and a `$XDG_STATE_HOME/lyona/update.status` file, written at every phase of
  `apply`/`rollback`, that lets a fresh model instance report the outcome of
  an update that completed across its own Quickshell restart — without it,
  every successful update would look like a crash to the UI. `rollback` now
  also restarts Quickshell itself when a desktop session is present (falling
  back to a plain "log in now" message from a bare TTY, where it always
  worked), instead of leaving the running shell out of sync with what was
  just restored. New `docs/src/updating.md` walks through checking, applying,
  channels, and rollback, prominently including the bare-TTY recovery path;
  mirrored in `README.md`'s Troubleshooting section.

- Add install provenance (UPDATE-001, `docs/P6-UPDATE-PROVENANCE.md`):
  `make install-system` and `make install-user` now each write a stamped
  record last, only on success — `/etc/lyona-release` (system) and
  `$XDG_STATE_HOME/lyona/install.state` (user) — and the new `lyona-version`
  helper reads them back through the same safety idiom used elsewhere
  (`status`, `status --json`, `print`). A record that is missing reads as
  `defaults`; one that is symlinked, wrong-owner, oversized, or writable by
  group/other reads as `unavailable` and is never read through or rewritten.
  `consistent` is `yes` only when the system record, the user record, and the
  running `dwm -v` binary all agree, catching a half-applied install rather
  than reporting a version nobody can act on. An ISO install now carries its
  real build commit onto the target instead of recording `unknown`
  (`archiso/airootfs/root/lyona-postinstall.sh` passes `LYONA_SOURCE=iso`/
  `LYONA_COMMIT` through explicitly, since `su -` resets the environment),
  and `install.sh`'s completion banner reports the version that was actually
  stamped. Nothing else about the install path changed; this is the
  foundation the rest of Phase 6's update path (`lyona-update`) builds on.

- Add `lyona-update` (UPDATE-002, `docs/P6-UPDATE-HELPER.md`): a `check` /
  `apply` / `rollback` / `backups` helper that lets an installed machine move
  to a newer release and back again, on top of UPDATE-001's provenance
  record. `check` compares the installed version against a `stable` or
  `preview` GitHub release (calendar-version ordering, with a short-lived
  cache so a panel indicator does not hammer the API) and reports `current`,
  `behind`, `ahead`, `downgrade-offered`, `unknown`, or `offline` — never an
  error for an unreachable network. `apply` downloads and SHA-256-verifies a
  release tarball *before* unpacking it, builds unprivileged, backs up the
  live install, then runs one confirmed privileged step
  (`scripts/lyona-update-root`, installed via
  `config/polkit/com.lyona.update.policy`) before verifying the result and
  restamping provenance last — a build failure or a declined privileged step
  costs nothing but time, never a half-applied system. `rollback` is the
  missing half of `scripts/dev-sync-install.sh`'s existing backup machinery
  (now reusable as a library via a `DEV_SYNC_INSTALL_LIB_ONLY` sourcing
  guard that leaves its own direct-invocation behavior unchanged): it
  refuses on any checksum or environment mismatch, and is designed to work
  from a bare TTY with no desktop running by falling back from `pkexec` to
  `sudo` when no agent is reachable — not yet exercised from an actual bare
  TTY; that scenario is pending the disposable-VM verification pass in
  `docs/P6-UPDATE-HELPER.md`. Channel and backup retention are configured in
  `~/.config/lyona/update.conf`, seeded on first use and never overwritten.
  The privileged step re-verifies the release tarball's checksum immediately
  before use and then extracts, rebuilds, and installs from a scratch
  directory the invoking user never has write access to, rather than running
  a Makefile from a directory that was still writable by that user at the
  moment root acted on it; `rollback`'s restore likewise validates every
  backup archive member's path, type, and mode before extracting — refusing
  anything outside the managed install locations, any non-regular member
  (symlink, hardlink, device, FIFO, socket), and any setuid, setgid, or
  sticky bit — rather than trusting GNU tar's own default root-extraction
  behavior against a directory the invoking user could have replaced.

- Persist workspace, volume, Bluetooth, network, and power panel visibility in
  one versioned user-owned state file shared by every monitor, Control Center,
  and Settings. An absent file migrates from the prior implicit all-on state;
  malformed, incomplete, unsafe, or unsupported state falls back all-on
  without preventing shell startup. Atomic set/reset actions preserve the file
  mode and refuse concurrent or unsafe replacements.

- Theme the GRUB boot menu by default. The `CyberRe` theme (vendored from
  [ChrisTitusTech/bootloader-themes](https://github.com/ChrisTitusTech/bootloader-themes),
  MIT) installs to `/usr/share/grub/themes/CyberRe`, and the installer
  selects it on machines that boot with GRUB. New `lyona-grub-theme` helper
  with `status`, `list`, `apply`, and `remove`.

  Installing the theme files changes nothing about booting. Selecting the
  theme edits `/etc/default/grub`, so it backs the file up first, prints
  every key it rewrites (`GRUB_THEME`, a `GRUB_TERMINAL_OUTPUT` that would
  disable the graphical terminal, and `GRUB_GFXMODE` when unset), comments
  replaced lines out instead of deleting them, and regenerates
  `/boot/grub/grub.cfg`. Which entry boots, the kernel command line, and the
  timeout are untouched.

  Machines that do not boot with GRUB -- including installs from the lyona
  image, which use systemd-boot -- are reported and left alone, and a failed
  theme step does not fail the install. Opt out with `--skip-grub-theme` or
  `DWM_INSTALL_GRUB_THEME=false`; revert an applied theme with
  `lyona-grub-theme remove`.

- Add text scaling, contrast, reduced motion, notification policy, and
  keyboard/pointer accessibility capability records to `dwm-settings-provider
  discover`, so Settings can report accessibility maturity per capability
  instead of a single all-or-nothing accessibility state. Text scale is
  probed live against `dwm-settings-font`; contrast and reduced motion report
  static `partial`/`unsupported` states describing the semantic-theme
  subsystem's current maturity; notification policy probes the D-Bus
  notification owner; keyboard/pointer access reflects XInput discovery
  readiness. Every emitted record is bounded and validated the same way as
  the rest of `dwm-settings-provider`'s helper output.

- Add a persistent high-contrast and reduced-motion policy, applied across
  every managed Quickshell surface. New `dwm-accessibility-settings` helper
  (`status`/`watch`/`set`/`reset`) stores the policy at
  `~/.config/lyona/accessibility.conf`, with the same atomic-publish,
  concurrent-edit-refusal, and symlink/hard-link-refusal safety as the
  existing settings helpers. High contrast widens control borders and pins
  muted text to full-strength text; reduced motion collapses animation
  durations to zero. Both compose over the active theme rather than
  replacing it, so hot-reloading a theme while an override is active still
  repaints the palette and the override survives -- `Theme.qml`'s
  `textMuted` is now a read-only value derived from a separate
  `paletteTextMuted` palette slot for exactly this reason. A missing or
  unreadable policy file falls back to standard contrast and full motion
  without preventing shell startup.

- Add keyboard- and screen-reader-accessible controls for the new high
  contrast and reduced motion policy: a Settings → Appearance "Accessibility"
  section with two toggles, a status card explaining why a control is
  disabled when the provider is read-only, and a reset action. `Settings`
  and the Bluetooth power toggle in the Control Center gained proper
  `Accessible.*` metadata and a shared `requestToggle()`/`requestActivation()`
  guard, so a screen reader's press action can no longer bypass the same
  enabled/busy check the keyboard and mouse paths already enforce.
  `dwm-settings-provider`'s `accessibility-contrast` and
  `accessibility-reduced-motion` capability records now reflect whether the
  policy can actually be changed right now (backed by a real atomic-exchange
  readiness probe against the configuration filesystem) instead of the
  static placeholders Phase 4 shipped.

- Add XKB accessibility controls -- sticky keys, slow keys, bounce keys, and
  mouse keys -- to Settings → Input, backed by `xkbset` through the existing
  `dwm-settings-input` provider. The new "Keyboard accessibility" group uses
  the same bounded preview-then-keep-or-revert flow, and reset, as every
  other input setting. Reflects live in `dwm-settings-provider`'s
  `accessibility-input` capability record, which now distinguishes "xkbset
  is missing," "xkbset is installed but unresponsive," and "fully available"
  instead of a single static state. `xkbset` has no official Arch package
  and is AUR-only; it is listed as an optional dependency that installs
  automatically only when already resolvable, and every code path degrades
  cleanly to an explicit unsupported state when it is absent.

- Each Settings section's `dataLoading:` line is now exactly one or more
  `<model>.initialLoading` / `settingsModel.<x>Loading` terms, never a
  SettingsModel internal (a `*Pending` flag, a `*Busy` flag, `busy`, a `*State`
  string) inlined and recomposed in `SettingsWindow.qml` (#90). Displays and
  Input each get a new `SettingsModel` readonly property (`displaysLoading`,
  `inputLoading`), and Appearance's two loose terms (`busy`,
  `capabilityRefreshPending`) fold into `capabilitiesLoading`.
  `tests/test-quickshell-settings-loading.sh` pins the rule generically instead
  of trusting the file to stay that way. `AppearanceModel.qml` documents what
  `initialLoading` means (every read a model starts or has queued, never a
  resident subscription once it is confirmed live) and the one deliberate
  exception: `wallpaperStatusBusy` also counts the inventory watcher's own
  not-yet-live handshake, for the same reason an unconfirmed Picom watch could
  miss an edit (#85). The dynamic responsiveness harness gained the coverage the
  static rule alone cannot give: a delayed read now keeps Network, Bluetooth,
  Audio, Power and Defaults hidden until it ends, the same way Displays, Input,
  Appearance and System were already covered (Audio's own case is a known gap --
  its snapshot also runs once at shell startup for the tray volume control, and
  a stub delay long enough to still be in flight when Settings reaches it was
  not reliably reproducible in the harness; the static rule is what actually
  protects it, and its `dataLoading` line was not changed by this refactor).

- Add a managed notification policy: Do Not Disturb and a configurable popup
  duration (4/6/10 seconds), in a new Settings → Appearance → Notifications
  section. The existing D-Bus notification owner is never touched -- the
  policy gates which popups *display*, not which notifications are
  *received*, so history keeps recording everything even while Do Not
  Disturb is on. Critical-urgency notifications always show regardless of
  the policy. The policy fails closed: an unreadable or malformed policy
  file suppresses all non-critical popups rather than defaulting to
  "show everything." `dwm-settings-provider`'s `accessibility-notifications`
  capability now inspects the real D-Bus owner process (via
  `/proc/<pid>/exe` and its Quickshell config selectors) to confirm it is
  actually the managed Lyona shell before reporting `available`, rather
  than just checking that some owner exists.

- Replace the Displays pane's single mode-cycling button with dependent
  resolution and refresh-rate dropdowns, and replace immediate mode changes
  with an explicit **Apply changes** step: a 15-second countdown, **Keep
  changes** to confirm, or **Revert**/timeout/closing Settings to restore the
  captured layout automatically. `ShellButton` gains a `primary` visual state
  for the Apply/Keep/Use-at-next-login actions. Saved layouts are relabeled
  from implementation-oriented wording ("Profile", "Install persistent",
  "Rollback system") to "Layout name", "Use at next login", and "Restore
  login backup". `AppearanceModel`'s theme-mutation readiness probe now
  queues and re-checks itself instead of racing a concurrent action or
  refresh, so a refresh that lands while a readiness check or mutation is
  already running no longer reports a stale `mutationReady` value.

### Security

- The shell shows text from other programs as text, never as markup (Sync Sprint 12 S12-06, issue `#169`). Qt's default
  `Text.AutoText` rendered notification summaries and bodies, window titles, and network, device and application names
  as rich text: a notification carrying `<img src="http://...">` made the shell fetch it (a tracking beacon, and remote
  images fed to Qt's decoders), and a window title could restyle the panel. `UiText`, `SectionLabel` and every other
  `Text` in the managed shell (91 elements in 23 files) now set `textFormat: Text.PlainText`; nothing in the shell used
  markup, so nothing else changes. New `tests/test-quickshell-plain-text.sh` (`make check-quickshell-plain-text`)
  fails on any `Text` without it or any request for another format, and `tests/test-quickshell-plain-text-xvfb.sh`
  (`make check-quickshell-plain-text-xvfb`) sends a notification and opens a window whose text points `<img>` tags at a
  local listener, and asserts nothing is fetched and Qt parses no markup. Both are part of `make check`.

- The privileged update helper no longer builds a user's checkout as root or writes through paths in their home
  (Sync Sprint 12 S12-03, issue `#166`, decision D-15). `lyona-update apply --from-checkout DIR` and
  `lyona-update-root install-system checkout` are removed: after one password prompt, root ran `make install-system` in a
  directory the user owned, so any program running as the user could change the Makefile or its scripts first. To
  install a checkout, run `sudo make install-system` (or `scripts/dev-sync-install.sh`), where you type what runs as
  root; `lyona-update apply --from-checkout` now says so. The helper also wrote `~/.local/state/lyona/update.log` as
  root, so a symlink there made root create or append to any file; it now writes the log as the invoking user, with
  control characters in the logged path replaced. `make install-cursors` copied the cursor themes with `cp -a`, which as
  root kept the building user's ownership; it now installs them root-owned, like the GRUB theme. Tested as root in a
  disposable container (`make check-update-root-backups`) and in `tests/test-lyona-update.sh`, whose apply cases now
  install a source tarball with `--file`.

- The privileged release install hashes, unpacks and builds one root-owned copy of the tarball (Sync Sprint 12 S12-02,
  issue `#165`). `lyona-update-root install-system release` used to hash the user-owned tarball in
  `~/.local/state/lyona/updates/` and then extract it by reading the same path again, so it could be swapped between
  the two reads, and it copied `config.h` with `cp -a` as root. It now reads the tarball and `config.h` with the invoking
  user's own permissions (`runuser ... cat`) into files only root can reach, checks the digest on that copy, and
  extracts and builds only that copy, so no swap, symlink or path can make root read or build anything the user could
  not read themselves. `docs/src/updating.md` now says what the digest proves: the download is intact, not that the
  release is genuine, since releases are not signed yet (decision D-14) and the administrator prompt is the boundary.
  It also no longer claims the build never runs with elevated privileges; the privileged step rebuilds its own copy.
  Tested as root in a disposable container (`make check-update-root-backups`) and pinned in
  `tests/test-quickshell-update-model.sh`.

- Rolling back an update no longer installs anything from the user's home directory as root (Sync Sprint 12 S12-01,
  issue `#164`). `lyona-update-root restore-system` used to extract `system-files.tar` from
  `~/.local/state/lyona/live-update-backups/<id>/` as root with `tar -xpf`, keeping the archive's owners and modes and
  checking only member paths, so any program running as the user could plant a backup whose next authenticated
  rollback put root-owned files of its choosing into `/usr/local/bin` or replaced the helper itself. The helper now
  makes the system backup itself, as root, just before `install-system` installs (release and checkout modes), from the
  live files into `/var/lib/lyona/backups/<id>/` (0700, root-owned), and keeps the newest 5. `restore-system` takes a
  backup id, not a path, and restores only that root-owned archive; the member checks stay as defence in depth. The
  backup now also covers `dwm-window-thumb` and `/etc/lyona-release`, and cursor-theme symlinks no longer abort a
  restore (every restore of a backup that held the cursor themes used to fail on them). **Migration:** backups taken
  before this change have no system half, and `lyona-update rollback` refuses them with a message saying so. Tested
  as root in a disposable container by `tests/test-lyona-update-root-backups.sh` (`make check-update-root-backups`,
  and a new `update-helper-backups` job in the manual Full suite workflow).

- `install-mybash`'s Starship fallback no longer pipes a remote script
  straight into `sudo sh` on a transient `pacman` failure: it now downloads
  `https://starship.rs/install.sh` to a temp file, verifies it against a
  pinned SHA-256, and runs it as the invoking user (the installer itself only
  escalates internally if `/usr/local/bin` is not already writable). The fzf
  fallback now clones a pinned release tag and installs with `--bin`, which
  never needs `sudo`, instead of an unpinned clone plus `sudo ~/.fzf/install`.
  The zoxide curl fallback is dropped entirely in favor of the official Arch
  package, since Lyona targets Arch only.
- `xscreensaver-setup.sh` now writes `lock: True` instead of `lock: False`,
  and `dwm-lock` gained a guarded fallback branch (only taken when the
  daemon is actually running) so a screen that blanks via xscreensaver is
  also actually locked, instead of dismissible with any keypress.
- `lyona-cachyos` now verifies the CachyOS signing key's fingerprint against
  a pinned value before `pacman-key --lsign-key` trusts it, and deletes any
  key that doesn't match rather than signing it. Previously it trusted
  whatever a keyserver returned for the key ID with no independent check.
- `install.sh`'s `yay-bin` AUR bootstrap now clones a specific reviewed
  commit instead of an unpinned moving ref, and no longer passes
  `--noconfirm` to `makepkg -si`, restoring the normal PKGBUILD review pause.
- `config.mk` now builds `dwm` with `-D_FORTIFY_SOURCE=2`,
  `-fstack-protector-strong`, `-fPIE`/`-pie`, `-Wl,-z,relro,-z,now`, and
  `-Wformat -Wformat-security`. Fixed one real issue `-Wformat-security`
  surfaced: `getparentprocess()` never checked `fscanf`'s return value.
- `webapp-create` rejects a name or URL containing a newline before writing
  the generated `.desktop` file, closing a `.desktop`-key-injection path, and
  restricts icon downloads to HTTPS with a 10 MiB cap.
- Added a dedicated polkit `.policy` action
  (`config/polkit/com.lyona.settings-display.policy`) for
  `dwm-settings-display`'s `pkexec` call, replacing the generic
  `org.freedesktop.policykit.exec` prompt with a scoped message and icon.

### Changed

- Reduce hosted CI to one Arch build and desktop smoke job
  (`tests/test-desktop-smoke-xvfb.sh`, `check-desktop-smoke-xvfb`): build
  dwm, then start the real managed Quickshell shell in a private Xvfb+dbus
  session and check its panel, the launcher's Super+R/Escape keys, and an
  application launch. Skip documentation-only pushes. The full Xvfb/Settings
  suite (`scripts/run-tests` / `make check`) stays a local check rather than
  a hosted CI job; local validation and independent review remain the merge
  gate. The previous full desktop suite, `clang-build`, and `quickshell-qml`
  hosted jobs are removed; `workflow_dispatch` now runs the same smoke job.
- Three of the test-harness coupling problems from #93 are fixed. `tests/test-quickshell-settings-loading.sh`'s pane count is
  derived from `SettingsModel.qml`'s `sections` list instead of a hard-coded `9`, so an added or removed section (with a
  matching pane) needs no test edit and a mismatched one is still caught. `tests/test-quickshell-appearance-model.sh` no longer
  restates the S5-01 pending-flag ordering rule with its own awk block; the settings-loading test's generic rule is the one
  place that checks it. `make check-xvfb-runtime` gained the case the issue named: a tiled window that only later gains a
  min==max hint (the existing "fixed" client is fixed from creation, so it is never tiled to begin with, and the
  `!c->isfixed` branch in `togglefloating` was unreachable). It pops out at exactly that fixed size and keeps its top-left
  corner, rather than being shrunk and recentred through `shrinkfloating`'s 85 percent the way an ordinary tiled window is
  (both produce the same 300x200 for a min==max client, since `applysizehints` clamps either way, so the position, not the
  size, is what the case actually has to check). Not done in this pass: the larger, more invasive change of replacing the
  harness's text-patching (blind `"dataLoading: "`/`"DeferredSettingsPane {"`/`"id: root"` replacement, the `core/UiText.qml`
  patch) with production test hooks -- a bigger surface better suited to its own follow-up than folding into this one.

- Open Settings full screen on the active screen, like System Health (Sync
  Sprint 3 S3-06 `#302`, `docs/SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`,
  upstream `#307`/`56ec27b`), and tighten its navigation rows, pane margins,
  capability cards, and display controls so more options remain visible
  without reducing the configured text scale. This supersedes the earlier
  1180x760-with-clamping window size from this same Unreleased section.

### Fixed

- Rapid overview card closes now launch independent commands so each requested
  window is processed even while an earlier close command is running.

- Dark presets (Dracula, Tokyo Night, Nord, and every other shipped dark theme) could render Thunar and other plain GTK apps
  light instead of dark (#348). `lyona-gtk-theme generate-all`, which builds each palette's `Lyona-<theme>` GTK theme, is an
  install-time step (`make install-system`'s `install-gtk-themes`); on any live system where that step has not run, or whose
  `themes.toml` grew a palette since, the generated theme genuinely does not exist, and `theme-apply.sh` fell back to a
  literal `gtk-theme-name=Adwaita-dark` -- a name recent GTK3/GTK4 has no theme by (the dark variant of Adwaita is the
  `gtk-application-prefer-dark-theme` hint, not a second named theme), so it resolved to nothing and rendered light
  regardless of the preset. `theme-apply.sh` now generates the one palette actually in use on demand when it is missing, and
  the fallback (when generation itself fails) is plain `Adwaita` with the hint already set, which is always available. A
  user's own GTK theme override (Settings > Toolkit) is unaffected either way -- it already won over the palette's choice,
  and still does, now that the generated theme is more often actually present to compete with it. New
  `make check-theme-apply-gtk-fallback` (5 cases: on-demand generation, no needless regeneration, a personalization override
  surviving both with and without the generated theme present, and the corrected fallback).

- A Settings pane can no longer be hidden forever by a read that never finishes
  (#76). Since the loading gate (S5-01) a pane stays hidden and disabled until
  every read it waits on has finished, with no upper bound, so one hung helper
  left it on "Loading settings..." for as long as it hung (the System pane can
  wait about 12 s on its own when a discovery watch is slow).
  `DeferredSettingsPane` now has a `loadingTimeoutMs` cap (5 s): when it passes
  with the pane selected and its component ready, the pane is presented with
  what it has. The fast path is unchanged. New stages in the responsiveness
  harness create a pane whose reads never finish and check that it is hidden
  until its cap and usable after; removing the cap fails them.

- `tests/test-quickshell-system-management-xvfb.sh` no longer races the
  discovery subscriptions. It asserted the native provider and state statuses
  (`available`) before waiting for each discovery domain to connect, so on a
  slower host they read `partial` and it failed in the full-suite CI image; it
  now waits for every domain first. Its D-3 check also asked
  `prepareDelegate(accounts-open)` once, straight after the timezone dispatch,
  and got the shared operation model's "busy" message when that was still
  settling; it now asks again until the D-3 reason appears, still requiring
  every attempt to be refused with nothing pending. It failed 4 of 4 runs in
  the CI container before and passed 5 of 5 after.
- `tests/test-quickshell-design-system.sh` checks the CI layout as it is now.
  It still expected the hosted `c-cpp.yml` job to name the `qml-validation`
  package profile twice, which stopped being true when that job became the
  desktop smoke test (it installs `ci-smoke`) and QML validation moved to
  `full-suite.yml`, so `make check` failed there. It now requires each workflow
  to take its packages from the right profile and to hard-code neither
  `quickshell` nor `qt6-declarative`.
- The Settings > System pane now waits for the update card's own reads (#77).
  Entering the section re-runs `updateModel.refresh()` and `refreshBackups()`,
  but the pane only waited on the system-management model, so the installed
  version and the "Available: ..." row could still change after the pane had
  presented. `UpdateModel` has a read-only `initialLoading` for its local
  reads (`versionProcess`, `backupsProcess`; not the network check) and the
  System pane's `dataLoading` includes it. This also corrects the Sprint 5
  entry above, which said those reads only happen at shell start. The
  responsiveness harness delays the version read past the System snapshot and
  checks the pane stays hidden until it finishes.

- A wallpaper preview reconcile that found something blocking it is now retried
  when that clears (#95). `tryReconcileWallpaperPreview()` leaves the request
  queued while the model is busy, a font change is running or another wallpaper
  action is in flight, but the only retry was `refreshWallpaperStatus()`, which
  runs on watcher events or when a status refresh was itself queued. If none
  came along, the preview stayed `failed` for good, which is what made
  `check-quickshell-settings-xvfb` fail intermittently at "wallpaper watchdog
  reconciliation" (also on `main`). `AppearanceModel` now retries when `busy`,
  `fontBusy`, `wallpaperBusy` or `wallpaperStatusBusy` clears. New
  `make check-quickshell-wallpaper-reconcile-xvfb` blocks the reconcile with
  each of those, releases it, and requires exactly one reconcile to start (it
  fails on the previous model, and removing any one handler fails its case); the
  settings test's final check now reports the state it saw instead of failing
  silently. The flake itself could not be reproduced on demand, so this closes
  the lost-retry path rather than proving it was the only cause.

- Settings > Bluetooth device rows no longer clip their address line at large
  text sizes. The row had a fixed height (`Theme.dp(68)`) while its two text
  lines scale with the font, so at 200 percent text with Noto Sans (a line
  height of about 1.36, against about 1.2 for the FreeSans fallback) the second
  line ran a few pixels past the row. The row now grows with its content, never
  below the old height. The responsiveness harness had passed only where the
  host's font is short, and failed in the full suite's CI image; its fixture now
  pins every `UiText` to Noto Sans's line height so a local run answers the same
  way as CI.
- `tests/test-seed-default-apps.sh` no longer depends on the host lacking a real
  Celluloid. Its "handler whose program is not installed" case only removed a
  stub from its own `PATH`, so on a machine with Celluloid installed (the full
  suite's CI image) the real one satisfied the check and the case failed with
  "a handler whose program is not installed was accepted". It now runs that case
  with a `PATH` of only the tools the script needs plus stub programs, after a
  control run proving the setup is sufficient.
- `scripts/ci-local.sh` fails loudly and cleans up after itself (#78). A failing
  `git ls-files` used to be hidden by a process substitution, so tar copied only
  `.git` and the run tested an empty tree; the file list is now written to a
  file, checked, and any files tar could not copy are reported. The build
  context and file list are removed by the EXIT trap even when `docker build`
  fails; the container has a unique name, `--init`, a `lyona-ci` label and
  `--rm`, and lives at most four hours, and the trap removes only a container
  this run started (a reused PID used to make it delete an older `--keep`
  container). Logs go in a `mktemp -d` directory instead of a predictable
  `/tmp` path, host-side reads skip symlinks a test left behind, and the usage
  text and CONTRIBUTING say the tool runs the tree's own code, for trusted
  branches only. It also works from a linked git worktree now: `.git` there is
  a one-line pointer file, so the container got no repository and every
  target that reads git history failed (`check-release-helper`: "not a git
  repository"); the shared repository is shipped as `.git` with the worktree's
  own HEAD and index.

- A tiled selected window no longer covers floating windows and popups
  (`dwm.c` `raiseselectedclient()`, from the "updating floating windows" work
  of 2026-08-29). Every restack raised the selected client above the floating
  clients it had just raised, and above popups an application had raised itself,
  even when the selected client was tiled. It now raises the selected client only
  where `restack()` itself does: when it is floating or the layout is floating,
  which is what that change needed so a selected window is not left under the
  floats. Found because `make check-xvfb-runtime` had failed since that commit
  (an override window raised by an application was buried after a layout
  change); the test now passes end to end, and gained checks that a floating
  window stays above a selected tiled one and that the selected window comes to
  the front in the floating layout.
- The System update UI test fixture (`tests/fixtures/system-update-ui-provider.py`)
  now answers the storage (`watch-mounts`) and security (`watch-units security`)
  watches that Sync Sprint 2 added. It rejected them as invalid arguments, so
  `make check-quickshell-update-ui-xvfb` had failed since the Sprint 2 merge even
  though every QML assertion passed.
- The full-suite workflow and `scripts/ci-local.sh` pick the installable packages
  with one `pacman -Slq` query instead of one `pacman -Si` per package (#79).
  For the 114 packages in the list the loop took 22 s in the CI image and the
  single call under a second, and both select the same 111 (the three multilib
  gaming packages are absent from the container's repositories either way). The
  workflow step was run as the workflow's shell runs it and the generated
  Dockerfile was built with a list of real, bogus and multilib names.

- The Gear Lever installer now verifies the Flathub remote before it installs
  (Sync Sprint 5 S5-02, ported from upstream `#334` `dd64bbf`, issue `#332`).
  It refused a `flathub` remote with the wrong URL already, but accepted one
  with signature verification disabled or one that was disabled, and did not
  check a remote it had just added. A new `scripts/dwm-flatpak-setup
  --user|--system` checks the official URL, `no-gpg-verify` and `disabled`
  (reading disabled remotes too), adds the official remote when there is none
  and verifies it again, and `scripts/install-gearlever` calls it right before
  `flatpak install`. Lyona adaptation: an app that is already installed exits
  before the helper, so a remote problem never makes an installed app report a
  setup failure. The tests script the `flatpak remotes` output in upstream's
  column format; that format was then checked against real Flatpak 1.18.2 in
  the CI image (it prints `disabled,no-gpg-verify` comma-joined, as parsed), and
  the helper refused an unsigned, a disabled and a wrong-URL `flathub` remote
  and added then verified the official one (#80).
- `check-deps.sh` now recognises every terminal `dwm-terminal` can launch
  (Sync Sprint 4 S4-05, ported in part from upstream `#255`/`902a138`). Its
  fallback list stopped at Alacritty, Kitty and st, so a machine whose only
  terminal was `warp-terminal` or `xterm` was reported as having none, though
  `dwm-terminal` and `dwm-diagnostics` accept both. When no terminal is found the
  hint recommends only terminals in the official repositories (Alacritty, Kitty,
  xterm); `st` and `warp-terminal` are AUR-only, so they are detected but not
  suggested, unlike upstream's wording. The `dwmterm` integration itself is
  declined: it is packaged in neither the official repositories nor the AUR
  (re-checked 2026-09-20), and promoting it to the first probe would make
  `dwm-terminal` miss on every launch. The default stays `alacritty`.

- `scripts/install-gearlever` now finds `dwm-flatpak-setup` with `CDPATH=''`,
  like the repo's other scripts. With `CDPATH` exported and a matching
  directory on it, `cd` printed a path, the helper lookup returned two lines and
  the helper was not found (exit 127), which `install.sh` only reports as a
  warning (#80). New case in `tests/test-install-gearlever.sh`.

- Fix two installer and session start-up problems (Sync Sprint 4 S4-04,
  `docs/SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`, ported from upstream
  `#283`/`378f06e` and the autostart hunk of `44800ba`). `dev-sync-install.sh`
  no longer demands a dwm restart after a reinstall that leaves the running
  binary's bytes unchanged: reinstalling unlinks the running executable, and
  the old check treated that unlinked (`(deleted)`) file as a mismatch before
  ever comparing bytes, though `/proc/PID/exe` still exposes the inode.
  It now compares the bytes even when the file is deleted. Separately,
  `autostart.sh` runs `systemctl --user daemon-reload` before starting
  `wm-graphical-session.service` every time, instead of only after a failed
  start, so autostart exclusions an installer seeded after the user manager
  began apply on the very first login. The new dev-sync test uses a private
  child process running a deleted copy of a binary, never the host window
  manager, and registers its cleanup through `lib.sh`'s stack in place of
  upstream's hand-written trap. Both new assertions were confirmed to fail on
  the previous code. Upstream's `test-fedora-packages.sh` hunk is not
  applicable.

- `MountMonitorTests.gone()` in `tests/test-system-management.py` no longer races
  a process that exits while `/proc/PID/stat` is being read (#94). That read
  raises `ProcessLookupError` (ESRCH), which the helper did not treat as "gone",
  so `test_signal_cleanup_and_parent_death` errored about once in three runs in
  the full-suite CI container. New cases pin both outcomes (an ESRCH read counts
  as gone; a process that stays alive still fails).

- Fix `scripts/webapp-launch`, which never worked for a user-scoped browser
  install: unquoted brace expansion ran before tilde expansion, so
  `~/.local/share/applications` and `~/.nix-profile/share/applications` were
  never actually searched, only `/usr/share/applications`. The browser
  resolution was also unquoted (word-split a path containing a space) and
  parsed `Exec=` with a `sed` pattern that mishandled quoted or
  backslash-escaped values. Rewritten with proper quoting, spec-correct
  `Exec=` parsing, and URL validation. A bare `Super+A` ChatGPT launch now
  prefers an installed desktop app and falls back to the web app only when
  asked to, without risking recursion back through the launcher.
- Super+M (fullscreen) no longer shrinks windows when it returns to the floating
  layout (#83). `fullscreen()` switches to monocle and back with the layout
  switch, and since the floating-toggle change (S5-03) that switch shrinks
  every visible tiled window by 15% when it enters the floating layout, so a
  round trip from the floating layout came back at 85% of the monocle size.
  `setlayout()` now takes its shrink from a `shrink` flag: the key and button
  entry point still shrinks, `fullscreen()` does not. New case in
  `tests/test-xvfb-runtime.sh` (it fails on the previous build, and checks that
  an explicit switch still shrinks).

- Fix `dwm-settings-input`'s device scan silently reporting zero devices when
  `xinput --list --short` failed outright, instead of surfacing the failure.
  It now checks the command's exit status before parsing its output and
  exits with `die` on failure.
- `make check-xvfb-runtime` now turns its test's "skipped" exit status (77:
  Xvfb/xdotool missing) into success like the other Xvfb targets do.
  `make check-quickshell-settings-loading` does the same when python3 is
  unavailable, like the other dependency-dependent checks, instead of failing
  a plain `make check` on such a host (#82). A real failure still fails.

- Fix a race in `dwm-settings-appearance`'s inventory scanner: a named
  coprocess's PID and file-descriptor bookkeeping could be unset by bash
  before the caller read them, if the scan finished first. Replaced with
  process substitution, which captures its PID synchronously and keeps it
  valid regardless of whether the process has since exited. The scan also no
  longer inherits the parent shell's stdin.
- dwm no longer exits when an X client asks for an extreme aspect ratio
  (`applysizehints()`, an issue that predates Sprint 5). With a tiny maximum
  aspect and no minimum size the aspect clamp rounded a side to 0, the
  zero-sized `XConfigureWindow` came back as BadValue, and `xerror()` treated it
  as fatal, so any X client could end the session (#81). The result is now
  floored at 1x1. New `extreme-aspect` client mode and case in
  `tests/test-xvfb-runtime.sh`, which fails on the unpatched build.

- Document the command menu's `menu open|close|toggle|summon` IPC surface,
  which shipped undocumented since the fork (`tests/test-quickshell-command-menu.sh`
  asserted the documentation but nothing had ever satisfied it, so
  `make check` failed on a from-scratch checkout).

### Fixed

- The TOML parser no longer corrupts window rules or drops sections (Sync Sprint 12 S12-05, issue `#168`). In a
  multi-line array, a `{` inside a trailing comment (`{ class="a" }, # see {docs}`) opened a phantom table: a window rule
  with no class, instance or title, which matched every window and reset `isterminal`, `noswallow`, `isfloating` and
  `alwaysontop`, undoing earlier rules such as terminal swallowing. Comments are now stripped from array lines. Closing
  an array on the line of its last table (`{ ... } ]`) left the parser in array mode, so every later section, such as
  `[active] theme`, was lost; an array whose first table sat on the opening line lost the rest. `true` and `false` were
  read as `0.0` inside tables and as strings elsewhere, so `isfloating=true` did nothing; they now parse as `1` and
  `0`. A `#` after an escaped quote inside a string no longer cuts the string. dwm also skips any window rule with no
  class, instance or title and logs it. New `tests/test-tomlparser.c` (`make check-tomlparser`, part of `make check`),
  the first test of the parser itself, covers each case and checks that the shipped `hotkeys.toml`,
  `window-rules.toml` and `themes.toml` parse to exactly the tables they contain; `tests/test-dwm-config-fallback.sh`
  checks the rule skip in a running dwm.

- dwm always starts with working keys, and a config file can no longer hang it (Sync Sprint 12 S12-04, issue `#167`).
  An empty, all-comment or otherwise unusable `~/.config/lyona/hotkeys.toml` at login left dwm with no key bindings at
  all, not even quit, while the notification said "loaded defaults". dwm now loads the shipped default instead and says
  so; a file with entries but nothing dwm can bind counts as unusable. On a live reload it keeps the configuration it
  already had and now says "kept the previous config" instead of "loaded defaults". If neither the user file nor the
  default loads at startup, two built-in keys remain (Super+x opens `dwm-terminal`, Super+Shift+q quits). The TOML
  parser opens files without blocking and accepts only regular files up to 1 MiB, so a `hotkeys.toml` that is a
  symlink to `/dev/zero` (which kept dwm at about 54% CPU and stopped it managing windows) or a FIFO falls back to the
  default instead. A `tag_keys` tag outside 0-8 is skipped with a message instead of shifting by an out-of-range
  amount. A SIGUSR1 (reload) or SIGUSR2 (quit) that arrived just before dwm waited for input was not handled until the
  next X event; the handlers now also write to a pipe that the wait watches. New `tests/test-dwm-config-fallback.sh`
  (`make check-dwm-config-fallback`, part of `make check`); `tests/test-xvfb-runtime.sh` expects the live-reload
  message. `docs/src/troubleshooting.md` no longer says invalid TOML fails silently or suggests a `config.h` fallback
  that does not exist.

- Qt applications follow the selected palette when `qt6ct` or `qt5ct` is installed, and GTK 2 applications can find
  the generated theme (Sync Sprint 11 S11-06, upstream `#352`, app-theme half). `theme-apply.sh` used to write only
  `color_scheme_path` into the tool's config, and only if that config already existed; `qt6ct` ignores that path
  unless `custom_palette=true` (verified: with the path alone Qt reported its default light palette, with both keys it
  reported the generated Dracula colours), so installing the tool left Qt light on a dark desktop. It now sets both
  keys, creates a minimal `[Appearance]` config when none exists (`dwm-settings-theme` already snapshots both files,
  so a created one is removed on rollback), preserves every other key and section, points at the palette's own scheme
  (falling back to the tool's `darker.conf` for a dark preset with no generated scheme), and leaves the config alone
  on a runtime-only apply. `scripts/lyona-gtk-theme` now also writes `Lyona-<id>/qt/colors.conf` (the 21 QPalette
  roles, highlighted text picked by contrast, placeholder text readable at 3:1 or better) and
  `Lyona-<id>/gtk-2.0/gtkrc`, and the `check-install` inventory lists them. New tests: `check-app-palettes` (structure
  and contrast for all 15 presets), `check-qt-palette-xvfb` (the generated scheme really becomes Qt's palette under
  `qt6ct`, with a negative control for `custom_palette`), and `check-theme-apply-qt-palette` (the real
  `theme-apply.sh`; fails against the original). Without `qt6ct`/`qt5ct`, Qt already followed the generated GTK theme.
  Not verified: GTK 2 rendering (not installed here), `qt5ct` beyond its config (same keys, only `qt6ct` was run), or
  a rendered Qt app.

- Shell text is readable on hover and selected surfaces in every palette (Sync Sprint 11 S11-01, completes Sync Sprint
  6 S6-03 and issue `#116`, ported from upstream `#352`). The shell's hover surface came from the palette's
  `term_color8`, ANSI bright-black, which is a terminal foreground and not a UI surface, and hover text was the plain
  foreground on top of it. Computed from `config/themes.toml`, all 5 light presets and 6 of the 10 dark ones fell
  below 4.5:1 on hover, and Solarized Light's strong text on hover was 1.00:1. `Theme.qml` now derives a light hover
  surface from the light background (`lightHover()`), and picks each hover, focus, selected and action text role with
  `readableText()` and `readableTextOnSurfaces()`, which keep the palette colour when it reaches 4.5:1 and fall back
  to black or white otherwise (`luminance()` also reads a `#AARRGGBB` string). 13 components take upstream's patch
  unchanged and `LauncherResultDelegate.qml` and `ControlsWindow.qml` needed small hand merges. New `make
  check-quickshell-theme-contrast` loads the real `Theme` singleton for all 15 palettes (built with the key mapping
  read from `dwm-settings-appearance`, so it cannot drift), asserts 174 role/surface pairs at 4.5:1 with its own
  independent contrast maths, and checks a dark-to-light-to-dark switch in one process; against the original
  `Theme.qml` it fails 105 of the 174 assertions across 14 presets. Not verified by eye: check a light preset
  (Solarized Light, Catppuccin Latte) and a dark one on the launcher, control center, network and Settings surfaces.

- `tests/test-xvfb-runtime.sh` no longer raises a critical "dwm: bad config" notification on the real desktop (Sync
  Sprint 11 S11-04, upstream `#354` test half). The test writes a deliberately invalid `hotkeys.toml`, and dwm reports
  it through `notify-send`; the test's separate X display still inherited the caller's D-Bus session, so every run of
  `make check` on a live desktop showed a critical notification. A fake `notify-send` now goes first on dwm's `PATH`
  and logs its arguments, and the test asserts that a valid configuration emits nothing and that the invalid one is
  reported as `-u critical dwm: bad config hotkeys.toml: invalid config - loaded defaults`. dwm reports once per load
  (its file watcher and the test's `USR1` each reload), so the assertion is "at least once". No other test that
  launches dwm writes an invalid configuration.

- The cross-tag window overview's type-to-filter and close-from-card did nothing, and the popup logged
  `WindowOverview.qml: Unable to assign [undefined] to QString` and `TypeError: Cannot read property 'length' of
  undefined` as soon as the shell loaded (Sync Sprint 10 S10-01). PR #138 merged `WindowOverview.qml`,
  `OverviewCard.qml` and `OverviewFilter.js` but not the model half: `OverviewModel.qml` defined no `query`,
  `setQuery()` or `closeCard()` and never imported `OverviewFilter.js`. It now has `query`, `closingIds`,
  `visibleWindows` (the filtered list `groups` is built from), `setQuery()`, `closeCard()`, and clamps `selectedIndex`
  whenever the card list shrinks; `open()`/`close()` reset the query and pending closes. The same error failed
  `check-quickshell-queued-run-xvfb`, `-picom-model-xvfb`, `-settings-responsiveness-xvfb`, `-update-progress-xvfb`
  and `-wallpaper-reconcile-xvfb`, which load the real shell, so `make check` stopped at the first of them and never
  reached the rest. `tests/test-quickshell-overview.sh` now also fails when any member the overview QML reads off the
  model is not defined on it, which is the check that was missing.
- `check-quickshell-command-menu` had been failing since the overview popup landed (#135), which changed
  `shell.qml`'s launcher `onVisibleChanged` block from a one-line `if` to a block that also closes the overview; the
  test pinned the old one-line text. It now pins the behavior (opening the launcher closes the command menu and the
  overview) instead of the formatting (Sync Sprint 10 S10-02).
- `make check` never ran `check-quickshell-health-navigation-xvfb`, `check-quickshell-information-ui-xvfb` or
  `check-quickshell-health-xvfb`, although Sprint 2 and `ROADMAP.md` Phase 6 cite them as evidence; it now does. The
  root-only, container-only `tests/test-settings-display-security.sh` was referenced nowhere; it now has
  `make check-settings-display-security` (skips outside a container, exit 77 convention) and a `display-security` job
  in the manual **Full suite** workflow that runs it as root in a disposable `archlinux:base-devel` container (Sync
  Sprint 10 S10-03).

- The manual **Full suite** workflow passed on `main` at `90f20f1` on 2026-09-26 (https://github.com/technicks89/Lyona/actions/runs/36242445295): `make check`
  (including the 686 `tests/test-system-management.py` tests and `check-quickshell-overview-xvfb`), the new
  `display-security` job, and the clang build all green. It had failed on all three earlier runs (2026-09-21) and had
  not been run since; this is the first passing run since the workflow was introduced (Sync Sprint 10 S10-06).

- The cross-tag window overview (Sync Sprint 7 S7-01 through S7-03, issue `#350`) was broken end to end since
  `scripts/dwm-quickshell-state` and `DwmState.qml` gained a `windowStates`/percent-encoding rework: `client_snapshot()`'s
  awk script called `sanitize_class()` without defining it, a fatal awk error that crashed `windows=`/`apps=` output
  outright whenever any client window existed; `DwmState.windowsByTag()` and `OverviewModel.qml`'s own `groups` property
  both still read a `root.windows`/`root.dwmState.windows` property that had been renamed to `windowStates`, so both threw
  `is not a function`/`undefined` errors even once the crash above was fixed; and `DwmStateWindows.js`'s `groupByTag()` --
  the function `OverviewModel.groups` actually calls -- had been dropped entirely. `client_snapshot()`'s awk script also
  carried three literal duplicate copies of its `_NET_WM_NAME`/`WM_NAME` title-parsing rules, a harmless but clearly
  accidental leftover, now down to one. Finished the in-progress percent-encoding a `WM_CLASS` needs to survive this
  wire format's own `:`/`|` separators intact rather than losing information (unlike a title's own lossy space
  replacement): `sanitize_class()` now actually escapes `%`/`:`/`|` (order matters: `%` first, so the `%` its own
  escaping introduces is never re-escaped), restored consistently in both `client_snapshot()` and `window_class()`, and
  a new `DwmStateWindows.js` `decodeClass()` reverses it on the QML side (`DwmState.qml`'s `apps`/`class` parsing and
  `parseWindows()`'s `appClass`), the same safe try/catch pattern `Icons.qml`'s own `decodeIconPart()` already uses.
  `tests/test-quickshell-state.sh` had its own problems compounding all of this: two contradictory `expect 'windows=...'`
  blocks (one with a class value neither code path ever produced), a fifth `0xee` client window referenced by its
  live-`watch` assertions but never actually given a case in the xprop stub (silently falling through to a generic
  catch-all), and a live-title-update scenario that could never pass because only the stub's `-spy` branch reacted to
  its own touch-file signals, not the regular re-poll a real X server would also reflect after an actual property
  change. Rewritten to be internally consistent, with `0xee` now a real percent-encoding round-trip case, and two
  `check-shell`-failing shellcheck issues in the same file (an unused loop variable in three `for attempt in {1..100}`
  polling loops, converted to the codebase's own `i=0`/`while` idiom; a deferred single-quoted `cleanup_add` expansion
  that is correct by design, now annotated) fixed alongside it -- `make check-shell` itself was failing on `main`.
  `tests/qml/tst_dwm_state_windows.qml` gained matching coverage for `groupByTag()` and `decodeClass()` (9 new tests,
  6/6 mutations caught across both fixes). `tests/test-quickshell-overview.sh` (Sprint 7 S7-03's own structural-pin
  test, which had merged but never actually run since: its last assertion pinned `groupByTag()`'s old 3-argument
  signature, so it always failed silently) is fixed and grown four more pins that would have caught the `windowStates`
  rename and the undefined `sanitize_class()` immediately, including one that greps `client_snapshot()`'s own awk block
  specifically -- the exact per-invocation scoping mistake that let `sanitize_class()` compile fine as a whole file
  while still being undefined where it was actually called. Found by trying to build Sprint 8 on top of what `main`
  already had, not by a report -- every one of these was reproduced directly (a real awk crash, a real qmltestrunner
  `is not a function`, a real shellcheck failure) before being fixed, not inferred from reading the diff.

## [2026.08.0-beta.1] - 2026-08-28

First beta of the Arch Linux line. See
`docs/RELEASE-NOTES-2026.08.0-beta.1.md` for artifacts and qualification
status.

### Changed

- Port the entire distribution target from Fedora to Arch Linux: the
  installer, dependency map, and diagnostics now use `pacman` and Arch
  package names; the Fedora Kickstart/RPM Fusion/COPR image path is replaced
  by a best-effort `archiso`-based install medium
  (`scripts/build-lyona-arch-iso.sh`); an AUR helper (`yay`) is installed
  as a standing convenience tool. Project branding moves to
  `technicks89`/`technicks89.com`. Arch Linux is now the sole supported
  platform.

- Rename the project from `dwm-titus` to `lyona`, to avoid confusion with
  the original Fedora-based `dwm-titus` project this was forked from.
  Renames the compiled-in XDG config/data subdirectory
  (`~/.config/lyona`, `~/.local/share/lyona`), install paths, the archiso
  install medium and its `lyona-install`/`lyona-postinstall.sh` scripts,
  and all documentation. The `dwm` window manager itself and its
  `dwm-*` tool family (`dwm-status`, `dwm-settings-*`, etc.) are unaffected
  -- only the project's own branding changes. No migration path is provided
  from an existing `dwm-titus`-named install; reinstall onto the new paths
  instead.

- Enable the `multilib` repository on the ISO. The archiso `pacman.conf` ships
  it uncommented and the generated archinstall configuration requests it, so
  the installed system has 32-bit packages available without a manual
  `pacman.conf` edit. `install.sh` now treats an already-enabled `multilib` as
  approval, so the ISO's full profile installs the Arch gaming packages it
  advertises instead of skipping them.

- Switch the shipped default theme from Nord to Tokyo Night and drop the
  stale `include ./nord.conf` line from `kitty.conf`, which overrode the
  generated `active-theme.conf` and pinned kitty to the Nord palette
  regardless of the selected theme.

- Apply a display-scale change to the running session instead of only to
  applications started afterwards. `dwm-settings-display dpi-set` still persists
  `Xft.dpi` and merges it into the running resource database, and now also
  publishes the value over XSETTINGS, sets the X server's reported DPI, and
  writes a runtime record the managed shell watches. dwm rescales its border
  width and snap distance when the resource database changes, and the Quickshell
  panel, popups, Control Center, launcher, and Settings window scale their
  metrics from the active DPI. A 96 DPI session renders exactly as before.
  Rescaling applications that are *already open* needs `xsettingsd`, which joins
  the X11 dependency set along with `xorg-xrdb` -- a hard requirement of the DPI
  actions that was missing from the dependency map and failed silently. Without
  `xsettingsd` a scale change still reaches the desktop immediately and reaches
  each application as it restarts. The scale is set from Displays in Settings.

### Fixed

- Keep floating windows above the tiling layout. Restacking placed every visible
  tiled client directly beneath the bar, which is the top of the window stack, so
  any floating window that was not the selected one was buried the moment focus
  moved to a tiled client. Windows that a rule, a transient hint, or a fixed size
  makes floating now stay above the tiled clients, and below the always-on-top,
  panel, override, and fullscreen layers as before. Tiled clients also restack
  correctly on a monitor that has not adopted a panel, where the previous sibling
  chain resolved to no window and the request was discarded without a diagnostic.

- Float windows matching the `RAIL` window rule. The rule set an unrecognised
  `float` key rather than `isfloating`, so it was parsed and then ignored.

- Prefer an installed ChatGPT desktop application for Super+A and hide its duplicate ChatGPT web entry from the managed application launcher, while retaining the web app as the fallback when no native desktop entry exists.

[Unreleased]: https://github.com/technicks89/Lyona/compare/v2026.08.0-beta.1...HEAD
[2026.08.0-beta.1]: https://github.com/technicks89/Lyona/releases/tag/v2026.08.0-beta.1
