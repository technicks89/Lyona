# Whole-repo review, 2026-10-10

Six read-only reviews of `main` at `1bfafac`, which is also the commit the tag
`v2026.10.0-beta.6` points at:
- architecture, engineering and security;
- user experience;
- efficiency and documentation.

The previous review, [2026-10-09](2026-10-09-whole-repo-review.md), was of
`34c8021`. Since then there have been 8 commits and about 1,550 changed lines in
43 files: the documentation catch-up (#329), the desktop fixes (#318-#321), the
bar-by-strut and XRender thumbnail work (#331, for #322 and #323), and the
install, update and rollback hardening (#332, for #324-#328). Each reviewer read
`AGENTS.md` and `SPEC.md` first, covered the whole repo with priority on that
diff, said for every 2026-10-09 finding whether it is fixed, and verified its own
findings against the code. The engineering reviewer built the tree and ran the
targeted test targets for every changed area (listed under "What was run"). The
findings marked **(checked)** below were checked again against the code when
this report was written.

Nothing in the repository was changed by the reviews. This report is the record;
fixing is a separate decision.

## Since the last review

Nearly everything the 2026-10-09 review asked for is done, and done where the
review asked for it: shell policy left the C event loop, the bar is an EWMH
declaration instead of a class-name guess, one layout reader per privilege
domain, one Quickshell start sequence, and a rollback that restores the shared
code whole.

| Area | Fixed | Partly fixed | Still open |
| --- | --- | --- | --- |
| Architecture | 13 | 0 | 0 |
| Engineering | 9 | 0 | 0 |
| Security | 6 | 2 (root gets a password hash; sudoers rule still `NOPASSWD: ALL`) | 0 (N6 accepted) |
| User experience | 11 | 2 (shell-down hint cannot be seen; two package areas in Settings, now explained) | 0 |
| Efficiency | 5 | 1 (two documented fixed sleeps remain) | 1 (installer 1 s redraw, accepted) |
| Documentation | 11 | 1 (ROADMAP image list stops at beta.5) | 0 |

The three "Fix first" items with the widest effect last time (focus lost when a
window closes on another monitor, a rollback restoring a mixed-version install,
and a broken `hotkeys.toml` loading silently) are fixed with tests that fail
without the fix, and the targeted test targets all pass.

## Tracking

The findings below are grouped into seven issues and four pull requests:

| PR | Issues |
| --- | --- |
| 1. Update failure story and downgrade wording | #333 (a failed update says "authentication required"; a part-way `install-system` says "untouched"; `sudo` after a dismissed dialog), #334 (a downgrade is called an update; the downgrade and signature rules undocumented) |
| 2. Release record | #335 (beta.6 tagged at `1bfafac` while CHANGELOG says Unreleased; SPEC and `install.md` promise one base-system download; the smaller doc drift) |
| 3. Root helper hardening | #336 (a dedicated build identity instead of `nobody`; fail-closed downgrade guard; `make` through `trusted_file`; `tar --verbatim-files-from`), #337 (the Makefile owns the palette list and the build-target split, frozen in SPEC 6 and tested across versions) |
| 4. Shell recovery and yay | #338 (the shell-down hint goes through the shell's own notification daemon), #339 (yay installed by two copies; a non-interactive install never installs it) |

## Fix first

These came up in more than one review, or sit on the most common path. None is
a regression in what was fixed; each is the next thing behind it.

1. **A failed update is reported as an authentication problem, and a failure
   inside `make install-system` is reported as "untouched"** (user experience
   Frustrating, engineering Important). **(checked)**
   - **Where:** `scripts/lyona-update:30-33` (`die` only prints),
     `:176-186` (the EXIT trap records `"$status_detail (exit N)"`, never
     `die`'s reason), `:986` (the detail at that point is "Installing V
     (authentication required)"), `:1006-1007`;
     `scripts/lyona-update-root:516-524`.
   - **What the user sees:** for any failure after the password prompt (a
     build error, a missing package, a verify failure, a disk full), the
     progress window and the critical notification say "Installing
     2026.10.0-beta.7 (authentication required) (exit 1)"
     (`UpdateModel.qml:368-371`, `:130-133`). Seen in the VM
     (`docs/evidence/324-328-install-update-rollback.md:118-121`, "seen, not
     changed"). The real reason is only in the log.
   - **Worse case:** the helper exits 1 both when it refuses before touching
     anything and when `make install-system` dies part-way (`:523`).
     `install-system` writes the GTK themes, cursors, `bin/`, `lib/lyona`,
     `libexec` in sequence (`Makefile:290-345`), so a failure after the first
     files leaves new `bin/` over old `lib/lyona`. `cmd_apply` cannot tell the
     two apart and prints "the live install is untouched" (`:1007`), and
     `docs/src/updating.md:225-227` promises "never a half-applied system".
     The backup exists (`backup_system_files` at `lyona-update-root:511`), but
     the user is not pointed at `rollback`.
   - **Fix:** have `die` store its message in a variable the trap writes as
     the outcome, falling back to the phase text only when it is empty. In the
     helper, exit a distinct code (3) from the `install-system failed` branch
     and print the backup id; in `cmd_apply`, map it to "the system install
     stopped part-way; run `lyona-update rollback` (backup `$backup_id`)" and
     record `failed` with that text. Fix the doc sentence.
   - **Test:** `tests/test-lyona-update.sh` already stubs `pkexec`'s exit
     status in `priv_probe`; add exit 3 and assert the rollback message. In
     `tests/test-lyona-update-root-backups.sh`, make `install-system` fail
     (read-only `$datadir/themes`) and assert exit 3 and the backup present.
2. **A downgrade is called an update until the password dialog** (user
   experience Frustrating, security Low, documentation Important, architecture
   Minor). **(checked)**
   - **Where:** `config/quickshell/settings/SystemSettingsPane.qml:234`
     ("Update to " + version), `:247-248` ("Install X over the running
     system?"); `config/quickshell/system/UpdateModel.qml:295` (always passes
     `--allow-downgrade`); `config/polkit/com.lyona.update.policy:36`.
   - **What the user sees:** after a channel switch Settings offers an older
     release (the VM did beta.7 to beta.5). The button says "Update to
     2026.10.0-beta.5", the confirm text never says it is older, and then the
     polkit dialog says "install an OLDER lyona release ... lyona-update named
     both". In Settings nothing named both: that warning (`lyona-update:996`)
     goes to stderr and the log.
   - **Docs:** `docs/src/updating.md:275-276` describes `--allow-downgrade`
     only. The separate prompt, the rule that an older release installs only
     with its signature verified (`lyona-update:916-922`; so the
     `--allow-downgrade --sha256` offline path the guide describes at
     `:286-290` is now refused), and "to go back, run `lyona-update rollback`"
     appear only in CHANGELOG and the polkit file. `lyona-update --help` lists
     the flag with no description (`:40`). `SPEC.md:589-596` and `:339-360`
     say nothing about the downgrade action or the build identity (the two
     decisions of 2026-10-09).
   - **Fix:** when `updateState === "downgrade-offered"`, label the button
     "Go back to X (older than the installed Y)" and say so in the confirm
     text; pass `--allow-downgrade` only on that path. Drop "lyona-update named
     both" from the polkit message, or set `status_detail` to name both
     versions before the prompt so the popup shows them. One paragraph in
     `updating.md` and one sentence each in SPEC 5.5 and 5.10.
3. **The published beta.6 is this commit, but the changelog and release notes
   describe the previous one** (engineering Minor, documentation).
   **(checked)**
   - **What:** `git ls-remote --tags origin` puts `v2026.10.0-beta.6` at
     `1bfafac`, published 2026-10-10 with `lyona-2026.10.0-beta.6.tar.gz`.
     `CHANGELOG.md:9` still lists #322-#328 under `[Unreleased]`;
     `docs/RELEASE-NOTES-2026.10.0-beta.6.md` last changed at `c81980f`,
     before #331 and #332; `docs/evidence/324-328-install-update-rollback.md:76`
     tested the update as a future beta.7.
   - **Related record drift:** `SPEC.md:310-313` and
     `docs/src/install.md:345-349` still promise the base system is "downloaded
     once, not twice"; since #328 the medium adds only the baseline CachyOS
     repository (`lyona-install.sh:781-788`) and the postinstall's
     `raise-level` (`lyona-postinstall.sh:68-72`) re-downloads the 184 base
     packages as v3 builds on any CPU above baseline (evidence `:66-69`, 37 s,
     accepted). `CHANGELOG.md:53-57` describes the new behavior; the source of
     truth describes the old one. `docs/roadmap/ROADMAP.md:496-497` lists
     published images up to beta.5.
   - **Fix:** either move the `[Unreleased]` entries under a dated
     `## [2026.10.0-beta.6]` and add them to the release notes, or re-cut as
     beta.7. Rewrite the two "once" paragraphs to say what happens and name
     `sudo lyona-cachyos raise-level` as the recovery. Extend the ROADMAP list.
   - **Test:** a changelog check that `config.mk`'s `VERSION` has a dated
     section when its tag exists.
4. **The unprivileged `config.h` build runs as the shared `nobody` account,
   and the helper's downgrade guard fails open** (security Low with high
   impact, engineering Minor). **(checked)**
   - **Where:** `scripts/lyona-update-root:226-233` (`cp -a` the tree,
     `chown -R nobody:nobody`, `setpriv --reuid=nobody` `make dwm`), `:237-242`
     (read back and install system-wide, then `touch` so `install-system`'s
     staleness check passes).
   - **What:** `nobody` (uid 65534) is a system-wide shared identity. Anything
     already running as `nobody` can write into the build directory during the
     build and have root install its `dwm` for every account on the routine
     prompt. The comment at `:212-219` reasons about what nobody can *read*,
     not what another nobody process can *write*. A stock lyona desktop runs
     nothing as `nobody`, so the likelihood is low; the impact is persistent
     code execution as every desktop user. Decision #327 chose `setpriv`; this
     is the residual.
   - **Fail-open guard:** `:473-483` compares ranks only when both
     `release_rank` calls succeed. A signed release whose `VERSION` does not
     rank (`2026.10.0+hotfix`, admitted by the regex at `:428`) skips the age
     check on `install-system`. Needs a release signed by the project's own
     workflow, so defence in depth only.
   - **Also:** `make`, which evaluates `$(shell ...)` as root, is taken from
     `PATH` (`:148`) while `cosign` and `setpriv` go through `trusted_file`
     (`:220-224`, `:367-375`); SPEC 5.10 (`SPEC.md:593-594`) says the tools
     root runs are checked. The manifest `tar -T` (`:337`) would read a line
     starting with `-` as an option; the stamp is root-only, so not reachable.
   - **Fix:** build as a dedicated identity: a `lyona-build` system user
     created by `install-system` with `systemd-sysusers`, or `systemd-run
     --wait --pipe -p DynamicUser=yes -p PrivateTmp=yes`; optionally refuse
     when `pgrep -u nobody` finds anything. When the installed version is
     known, treat a failed `release_rank` on either side as fatal.
     `readonly make_path=/usr/bin/make` through `trusted_file`;
     `--verbatim-files-from` on the backup `tar`.
   - **Test:** a container test with a `nobody` process touching
     `$build/dwm.c` during the build; a version-pair table fed to both
     `version_rank` (`lyona-update:198-220`) and `release_rank`
     (`lyona-update-root:194-211`), which today share no test.
5. **The "shell is not running" hint goes through the shell's own
   notification daemon** (user experience Frustrating, architecture Minor).
   **(checked)**
   - **Where:** `scripts/lyona-shell:52-61`. When the IPC call fails it runs
     `notify-send -u critical`. The only notification server in the product is
     Quickshell (`config/quickshell/notifications/NotificationModel.qml:391`;
     `scripts/dwm-packages.sh` ships no dunst or mako). On a bus with no
     server `notify-send` fails and exits 1. `tests/test-lyona-shell.sh:17-21`
     stubs `notify-send`, so the test passes while the real path does nothing,
     exactly as before #320. The CHANGELOG line "show how to get it back ...
     instead of doing nothing" is the one claim in it the product does not
     meet.
   - **Also:** the chords are hardcoded (`:57-58`) while the bindings live in
     `config/hotkeys.toml:88,140`, user-editable with hot reload. The hint is
     wrong exactly when the shell is down, for a user who rebound them.
   - **Fix:** do not rely on the shell's daemon: restart the shell directly
     (`dwm-quickshell-controlcenter action restart-quickshell`) and retry the
     call, or show the hint with `xmessage` or dwm's own notify path. Resolve
     the chord from `hotkeys.toml` with `lyona-toml`, or phrase the hint by
     action name. Make the test fail when `notify-send` exits 1.
6. **The root helper and the Makefile share four unspoken agreements**
   (architecture Significant x2). **(checked)**
   - **The palette list:** `[theme.<id>]` headers are extracted by an
     identical awk regex at `scripts/lyona-update-root:291` and
     `Makefile:393,619,1281`, although decision D-20 made `lyona-toml` the
     scripts' one TOML reader and `scripts/lyona-gtk-theme:50-58` already
     derives the same list from `lyona-toml dump`. What a rollback restores,
     and what `remove-legacy-shared-data` deletes as root, is a regex that must
     match the Makefile's; a quoted key or trailing comment silently drops the
     GTK themes from the backup.
   - **The build graph:** `lyona-update-root:502` names the new release's
     Makefile variables (`$(THUMB) $(TOML_TOOL) $(XWATCH) $(filter-out
     dwm.o,$(OBJ))`) to decide what root may build and what includes
     `config.h`; `:283,:287` name `CAPITAINE_*_THEME` and `POLKIT_ACTIONS`.
     The helper running from version N decides this for version N+1; nothing
     in SPEC or the Makefile says these names are frozen, and the only test
     runs helper and tree at the same version
     (`tests/test-lyona-update-root-backups.sh:303-311`). A release that adds
     a helper program or a second object including `config.h` breaks or
     weakens every installed system's update.
   - **Fix:** a Makefile `GTK_THEME_IDS` (computed once) used by
     `install-gtk-themes`, `uninstall`, `remove-legacy-shared-data` and the
     release manifest, read by the helper through `tree_make_values` like the
     other two; Makefile targets `all-root` (everything that never includes
     `config.h`) and `dwm`, so the helper calls two names only. Record the
     frozen names in SPEC 6 as the release-tree contract, and test the previous
     release's helper against the current tree.
7. **yay is installed by two copies of the same code, and a scripted install
   silently gets none** (architecture Significant, user experience Minor,
   documentation Minor). **(checked)**
   - **Where:** `install.sh:731-775` `ensure_yay_installed` and
     `archiso/airootfs/root/lyona-postinstall.sh:92-108` `install_yay` both
     wrap `dwm-aur.sh build-pinned yay-bin` then `pacman -U`, with their own
     sudo, noconfirm and warning policy; `--skip-yay` (`install.sh:123,
     173-176, 1411-1414`) exists only to suppress one copy. The postinstall
     hardcodes `base-devel git` (`:228, :388`) though the map owns them
     (`scripts/dwm-packages.sh:10,18`). Topgrade solved the same problem with
     one shared script (`scripts/install-topgrade --build-only`).
   - **User effect:** `./install.sh --non-interactive --yes --profile full`
     (the documented command, `docs/src/install.md:283`) runs `sudo -k` then
     `sudo -n pacman -U` (`:742, :757-768`), which fails wherever sudo needs a
     password; the summary at `:880-884` still prints "AUR helper: yay-bin,
     built from its pinned AUR PKGBUILD", and `install.md:480` says yay "is
     installed automatically". `docs/AUR-PACKAGES.md:46` names only
     `install.sh` as where yay is built; CHANGELOG has no line for
     `--skip-yay`.
   - **Fix:** one `scripts/install-yay` (or `dwm-aur.sh install-pinned`) used
     by both, taking `base-devel git` from a `dwm_packages` profile; drop
     `--skip-yay` once the ISO calls it directly. Until then, have the summary
     say "yay-bin (interactive runs only; a non-interactive run needs
     passwordless sudo)" and note it in `install.md`.

## Architecture

All thirteen earlier findings are fixed (`isaltbar` is `isdock && hasbarstrut`
at `dwm.c:1961-1976`; `normalizexdgenv` at `dwm.c:3464-3493` is the only place
dwm's environment changes; `scripts/dwm-quickshell-lifecycle.sh:118-129` is the
one start sequence; `scripts/lyona-shell` is the one IPC door; the ISO's
partial upgrade is narrowed to `-Sy` plus the dependency-free keyring and
mirrorlist packages at `lyona-cachyos:254-262`). The only new QML `Timer` is
one-shot (`UpdateModel.qml:446-450`); the C core gained no desktop policy; the
new dependencies (`libxrender`, `setpriv`) are in the shared map.

Remaining, beyond Fix first 6 and 7:

- **Two version-order implementations with no shared test.** `version_rank`
  (`lyona-update:198-220`) and `release_rank` (`lyona-update-root:194-211`);
  the helper is self-contained by design, so the copy is the accepted price,
  but no test feeds both the same pairs. A disagreement is a downgrade the user
  authenticates for and the helper then refuses, or the reverse.
- **One dock rule at three sites in `dwm.c`.** `leavedock` (`:1989-1992`) and
  the two inline `XSelectInput` calls "as leavedock()" at `:2977, :2989`. A
  `watchdock(win)` used by all three.

## Engineering

All nine earlier findings are fixed, each with a test that fails without it:
`unmanage()` moves focus only when `m == selmon` (`dwm.c:4337-4342`, test
`tests/test-dwm-activate-xvfb.py:238-274`); the restore requires every member
to be in the root-owned manifest (`lyona-update-root:573-580,627`) and sets
aside `lib/lyona` and `share/lyona` whole with an undo on tar failure
(`:633-659`); `skip_array_rest` (`tomlparser.c:49-71`) and `toml_doc_ok` refuse
a never-closed array (`tests/test-tomlparser.c:313-364`); the state bridge
reopens its fd read-only so a dead watcher is an EOF (`dwm-quickshell-state:607`).
One inherent residual: a backup taken by a pre-#324 helper still lacks
`lib/lyona`, and the new restore accepts those manifests (same format).

The new findings are Fix first 1 (the failure story after the backup), 4 (the
`nobody` identity) and 3 (the release record). Checked and sound:
`dwm-window-thumb.c:serverscale` frees pictures and pixmaps on every path and
falls back to the client path on any Render failure; `hasbarstrut` checks type,
format and `n >= 4` before reading `v[2]`, `v[3]`; `build_dwm_unprivileged`'s
`clean` keeps `config.h` (`Makefile:206-207`) and `dwm.c:394` is the sole
includer; `cancel_privileged` honours `status_written`.

## Security

Closed since 2026-10-09: the timezone lookup now asks first
(`lyona-install.sh:497-510`, HTTPS, zone validated against `/usr/share/zoneinfo`);
N1 (root compiled `config.h`), N2 (no anti-rollback; `install-downgrade` is its
own action with `argv1` pinned), N4 (the sudoers rule now has a `tmpfiles.d`
`r` line so a hard power-off cannot keep it, `lyona-postinstall.sh:492-496`),
N5 (restore allowlist and `remove-legacy-shared-data`'s `safe_dir`). Still
partly: the installer's `PASSWORD` variable is never `unset` (`:435`; residual
risk is a root-only process's memory, acceptable), and N3's sudoers rule is
still `ALL=(ALL) NOPASSWD: ALL` (`:499`) though yay is now built before it
exists and `install.sh` runs `sudo -k` before `makepkg`. N6 remains accepted:
any client can now become "the bar" by setting a dock type and a strut, which
X11 already permits.

New findings are Fix first 4 (the `nobody` build, the fail-open rank guard,
`make` from `PATH`, `tar -T`) and Fix first 2 (Settings always sends
`--allow-downgrade`). Checked and fine: the helper's trust chain (self path,
argv counts and regexes per subcommand `:394-428`, user files read only via
`runuser ... cat` into root-private copies, digest then signature on root's
copy); four polkit actions with `allow_active auth_admin` and pinned
`exec.path`/`exec.argv1`; `lyona_install_layout` is unprivileged and not
sourced by any root helper; `dwm-window-thumb.c`'s output buffer is sized
`dw*dh*3` with both clamped to the preview box. ShellCheck at `-S warning` on
the three root-facing scripts found nothing security-relevant.

## User experience

Eleven earlier findings fixed, including the cancelled polkit prompt
("Update cancelled: authorization was not given. Nothing was changed.",
`lyona-update:582-613`, VM-verified), the lost failure reason
(`SystemSettingsPane.qml:302-305`), the stale outcome (one day in Settings,
ten minutes for the popup, `UpdateModel.qml:57-71`), the hotkeys notification
("N problems, the rest loaded - unknown key 'Retrun'", `config.c:205-229`), and
the full-length `--help` for `lyona-version` and `dwm-diagnostics`. The two
package areas in Settings > System are still two, now explained in text
(`:441-444`), which is what the CHANGELOG claims.

Beyond Fix first 1, 2, 5 and 7:

- **Cancelling the polkit dialog from a terminal gives a second, sudo
  prompt.** `lyona-update:589-592`: with a terminal and `DISPLAY`, a dismissed
  dialog (126) warns "falling back to sudo" and asks for the sudo password;
  `updating.md:255-258` says sudo is used only "when there is no polkit agent
  to ask". Treat 126 as cancel everywhere; fall back on 127 only.
- **Custom-panel migration is only in CHANGELOG.** "A panel of your own needs
  a non-zero exclusiveZone" (#322) has no user-doc counterpart (`grep
  exclusiveZone docs/src` is empty); `docs/SHELL-STATE-PROTOCOL.md:49-52` is
  contributor-facing. A user running another bar with no strut sees it float
  as a window and finds nothing explaining why. SPEC 5.2 (`SPEC.md:121-123`)
  also does not state the strut contract.

Working well: the Picom one-time notice, the thumbnail fallback (silent, as it
should be), rollback's "different environment" refusal and the "run
lyona-update rollback" guidance on a half-applied user install
(`lyona-update:1012, 1018`), the postinstall's `raise-level` fallback hint.

## Efficiency

Fixed: the power watch is a `dbus-monitor` stream run only while the section
is visible (`PowerModel.qml:712-713`); thumbnails read about 118 KB instead of
33 MB for a 4K window (`dwm-window-thumb.c:221-279`, 6 ms vs 23 ms under
Xvfb); the 25 MB per update is removed after `verify_install`
(`lyona-update:1026-1031`); title churn is capped at one rebuild per 200 ms;
leftover test processes are found by a 48 ms `/proc` scan and fail the run
(`scripts/run-tests:106-132`). Partly: the font test's 5.2 s sleep is a poll
now, while `sleep 7.5` (`test-dwm-settings-font.sh:530-532`) and `sleep 6`
(`test-dwm-settings-theme.sh:885`) remain as documented deadline tests. The
installer's 1 s status redraw is unchanged and accepted.

No High or Medium. Three Lows, none needing a fix before a release:

1. **An update builds the release three times and copies a 16 MB tree to
   tmpfs for a 300 KB result.** User-side `make clean && make all`
   (`lyona-update:932-935`), root's rebuild (`lyona-update-root:499-507`), and
   `build_dwm_unprivileged`'s `cp -a` of the whole verified tree (`:226-243`;
   15.7 MB of which assets 4.7 MB, tests 3.4 MB, docs 2.9 MB) into a
   `mktemp -d` on tmpfs. About 5-20 s and 32 MB transient per update. Copy only
   `*.c`, `*.h`, `Makefile`, `config.mk` and the built `.o` files; keep the
   user-side preflight, which fails before the password prompt by design.
2. **Every ConfigureNotify on an unmanaged, strutless dock costs four X round
   trips** (`dwm.c:1017-1019`, `isaltbar` `:1966-1971`, `isdock` `:1974-1977`,
   `hasbarstrut` `:1936-1961`). Zero idle cost; a 60 fps toast animation would
   be about 2-3% of a core for its duration. Nothing needed unless it shows in
   a profile.
3. **System backups are about 2-3x larger, 45% of it an unchanging cursor
   theme.** About 6-7 MB each, five kept (`lyona-update-root:304-316, :155`),
   about 35 MB bounded; it replaces 25 MB per update unbounded, so a net win.
   Hardlink or skip the cursors when their checksum matches. Fine to leave.

## Documentation

The catch-up (#317) closed every 2026-10-09 documentation finding except the
ROADMAP image list: `dwm.1` now describes this dwm (bindings match
`config/hotkeys.toml`, emergency keys match `dwm.c:3524-3527`); the beta.6
notes, `RELEASING.md`, `TASKS.md` and the sprint records are current to
2026-10-09; SPEC 6 documents `/etc/lyona-release` (`SPEC.md:789-810` matches
`Makefile:414-422` and `dwm-paths.sh:181-204`); the three protocol docs are
linked from `SHELL-STATE-PROTOCOL.md:88-98`. The three evidence docs state
their "not tested" items precisely.

The gap is the three later PRs: the CHANGELOG is accurate on all of them, and
SPEC, `updating.md` and `install.md` still describe the old behavior. Beyond
Fix first 2 and 3:

- **Important: the guide omits the unprivileged `config.h` build.**
  `updating.md:196-203` says the helper "unpacks and rebuilds only that copy";
  the password prompt now says "compiled in as an unprivileged user"
  (`com.lyona.update.policy:12`), and a `#include` of a private file fails
  with "Permission denied" (evidence `:93-95`) with no troubleshooting entry.
  Add to step 6 that dwm with your `config.h` is built as `nobody`, so
  `config.h` can include only world-readable files, and that the step needs
  `setpriv` and a `nobody` user.
- **Minor:** `TASKS.md:106` says "Settings was not opened in a VM"; the
  2026-10-10 run used it (evidence `:89-101`). `updating.md:336-351` does not
  say the system half of a rollback now covers `lib/lyona`, `share/lyona`, the
  polkit actions, the GTK themes and `install.state`. `CONTRIBUTING.md:48-51`
  gives `/usr/...` as the default layout; `config.mk:3` sets
  `PREFIX ?= /usr/local`. `CHANGELOG.md:90` has a blank line splitting the
  Unreleased "Changed" list. The two #327 decisions (setpriv, separate action)
  are in the review report and code comments (`lyona-update-root:215,473`)
  but not in `UPSTREAM-SYNC.md`'s decisions table, which got D-30 for #328.
  Sprint 9 is marked Done at `UPSTREAM-SYNC.md:31` but its file is not in
  `docs/sprints/completed/`. `dwm.c:391` `altbarclass` now serves only
  `scantray()` (`:3062`) while `PATCH-OWNERSHIP.md:33-34` says dwm guesses
  nothing from a class; rename it `traywinclass` or comment it.

## What was run

All through the managed runner, exit codes as recorded by the engineering
reviewer:

```
scripts/run-tests make clean all                     -> 0
scripts/run-tests make check-tomlparser              -> 0
scripts/run-tests make check-dwm-config-fallback     -> 0
scripts/run-tests make check-lyona-update            -> 0
scripts/run-tests make check-quickshell-update-model -> 0
scripts/run-tests make check-cachyos                 -> 0
scripts/run-tests make check-quickshell-state        -> 0
scripts/run-tests make check-dwm-activate-xvfb       -> 0 (1 and 2 monitors)
scripts/run-tests make check-dwm-bar-docks-xvfb      -> 0
scripts/run-tests make check-window-thumb-xvfb       -> 0
scripts/run-tests make check-lyona-shell             -> 0
shellcheck (changed scripts)                         -> 1 (pre-existing SC1091/SC2154/SC2086 info only, none in changed lines)
shfmt -d (changed scripts)                           -> 0
```

Not run: `tests/test-lyona-update-root-backups.sh` (container-only, needs
root), any real X11 session, the desktop, the image, or a real update. The VM
evidence in `docs/evidence/324-328-install-update-rollback.md` covers those for
the 2026-10-10 run.

## Suggested grouping (now the Tracking table above)

1. **Update failure story and downgrade wording** (Fix first 1, 2; the sudo
   fallback on 126): `lyona-update`, `lyona-update-root` exit codes,
   `SystemSettingsPane.qml`, `UpdateModel.qml`, the polkit message,
   `updating.md`, SPEC 5.5 and 5.10.
2. **Release record** (Fix first 3; the Documentation Minors): CHANGELOG and
   beta.6 notes, SPEC and `install.md` on the base-system download, ROADMAP,
   TASKS, CONTRIBUTING, decisions table, Sprint 9 file.
3. **Root helper hardening** (Fix first 4, 6): a dedicated build identity,
   the fail-closed rank guard, `make` through `trusted_file`,
   `--verbatim-files-from`, `GTK_THEME_IDS` and `all-root` as the frozen
   release-tree contract in SPEC 6, a previous-helper-against-current-tree
   test, a shared version-pair test.
4. **Shell recovery and yay** (Fix first 5, 7): `lyona-shell`'s hint path
   and chord lookup, one `install-yay` script, the non-interactive summary.
