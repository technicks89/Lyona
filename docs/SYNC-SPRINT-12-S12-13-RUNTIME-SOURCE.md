# S12-13 plan -- one runtime source for helpers

Parent: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-13-one-runtime-source-for-helpers`.
Issue `#176`. Decision **D-16, option 3**: the system copy is the only runtime source,
plus one explicit developer override.

This file is S12-13's first task. The item says to write its step-by-step plan, with
the migration for existing installs, before starting. Nothing here is implemented
yet. Each step below is reviewable and testable on its own, and later steps depend on
earlier ones.

## What exists today (surveyed 2026-09-28, `main` at `34a33e1`)

**Two copies of every helper.** `make install-system` puts `INSTALL_COMMANDS` in
`$PREFIX/bin`. `make install-user` then copies all of `config/` and `scripts/` into
`${XDG_DATA_HOME:-~/.local/share}/lyona/` (`Makefile:304-308`), removing the previous
copy first.

**Where each consumer looks:**

| Consumer | Looks at | Where |
|---|---|---|
| dwm, `autostart.sh` and `autostop.sh` | `$XDG_DATA_HOME/lyona/scripts/`, then `~/.lyona/` | `dwm.c:386-390`, `runautoscript` `:2807-2886` |
| dwm, default TOMLs | `$XDG_DATA_HOME/lyona/config/` | `toml_default_dir` |
| `Commands.qml` `helperCommand` | the per-user copy first, for 23 of its 26 helpers (`preferManaged`), then `PATH` | `core/Commands.qml:6-24` |
| `DwmState.qml` and others | `PATH` (`dwm-quickshell-state`, `Quickshell.execDetached`) | |
| Shell libraries | the caller's own directory (`${BASH_SOURCE[0]%/*}`, `$script_dir`, `$SCRIPT_DIR`) | 20 files |
| Managed `themes.toml` | `$XDG_DATA_HOME/lyona/config/themes.toml` | `theme-apply.sh:94`, `dwm-settings-appearance:30`, `dwm-settings-theme:31` |
| Quickshell config lookups | `.../lyona/config/quickshell/shell.qml`, a stale path (the shell lives in `~/.config/quickshell`) | `dwm-controlcenter:7`, `dwm-keybinds:7`, `dwm-settings:7` |

**Only in the per-user copy.** `autostart.sh`, `autostop.sh` and
`migrate-graphical-session.sh` are not in `INSTALL_COMMANDS`, so today a session only
starts properly for an account that ran `install-user`.

**Libraries installed as commands.** `dwm-packages.sh`, `dwm-paths.sh`,
`dwm-utils.sh`, `dwm-watchdog.sh`, `dwm-simple-watch.sh`, `dwm-xsettings-config.sh`
and `dev-sync-install.sh` are in `INSTALL_COMMANDS`, so they land in `$PREFIX/bin`.

**`lyona-update` uses the developer tool.** It sources `dev-sync-install.sh` for
`prepare_expected_files`, `backup_live_install`, `verify_install` and
`runtime_verify` (`scripts/lyona-update:810`, `:1093`). `verify_install`
compares the per-user copy with the checkout (`verify_tree ... "$data_dir/scripts"`,
`... "$data_dir/config"`): drift detection that only exists because there are two
copies.

**No system data directory.** Nothing is installed under `$PREFIX/share/lyona`. The
default TOMLs, the managed themes and `assets/` exist only in the checkout and each
user's copy.

**Tests.** 24 tests (listed in step 6) put stub helpers in
`$XDG_DATA_HOME/lyona/scripts` and rely on the lookup preferring the per-user copy.

**Inline XDG paths.** 32 scripts compute XDG paths inline (the review counted 14;
listed in step 7), and `dwm-paths.sh` has no XDG function yet, only path-safety
checks.

## Target layout

| Path | Holds | Owner |
|---|---|---|
| `$PREFIX/bin/` | commands only: `INSTALL_COMMANDS` minus the libraries below | root |
| `$PREFIX/lib/lyona/` | shell libraries (`dwm-paths.sh`, `dwm-packages.sh`, `dwm-utils.sh`, `dwm-watchdog.sh`, `dwm-simple-watch.sh`, `dwm-xsettings-config.sh`, the new `lyona-install-verify.sh`) and session scripts (`autostart.sh`, `autostop.sh`, `migrate-graphical-session.sh`) | root |
| `$PREFIX/share/lyona/` | `config/` (default TOMLs, the managed `themes.toml`, the Quickshell tree `install-user` copies from) and the `assets/` the session reads | root |
| `$PREFIX/libexec/lyona/` | privileged helpers (unchanged) | root |
| `~/.local/share/lyona/` | user-owned data only; `install-user` no longer writes `scripts/` or `config/` there | user |

**`PREFIX`, not `DATADIR`, for Lyona's own directories.** `install.sh` builds dwm
with the default `DATADIR` and installs with `DATADIR=/usr/share` (`install.sh:952`),
so a path compiled into dwm from `DATADIR` could be wrong. Every consumer finds
`lib/lyona` and `share/lyona` relative to its own location instead:
`dirname(exe)/../lib/lyona`. dwm reads `/proc/self/exe`; a script uses
`${BASH_SOURCE[0]%/*}`. That works for any `PREFIX`, in a `DESTDIR` staging tree
and in a checkout. `DATADIR` stays what it is today: icons, cursors, GTK themes and
the X session file, which must live in system-standard places.

## The developer override

`LYONA_DEV_SCRIPTS=/path/to/checkout/scripts`:

- Set by the developer only, in `~/.xinitrc` or the session environment. No install
  path sets it.
- Checked first by dwm (`autostart.sh` and `autostop.sh`) and by `Commands.qml`. The
  scripts it starts find their siblings next to themselves, as they do in a checkout
  today.
- **Never honoured as root.** dwm ignores it when `geteuid() == 0`. Both privileged
  helpers `unset LYONA_DEV_SCRIPTS` at the top, and neither looks helpers up through
  it anyway.
- **Visible.** `dwm-diagnostics` prints it, `lyona-update check` adds an `override`
  line (JSON: `devScripts`), and Settings -> System shows a note while it is set. A
  forgotten override cannot go unnoticed.
- Must name an existing directory holding `autostart.sh`. Otherwise dwm logs one
  line and uses the system copy.

## Steps

### Step 1 -- a library directory, found relative to the caller

1. `Makefile`: split the libraries out of `INSTALL_COMMANDS` into `INSTALL_LIBS`,
   installed to `${DESTDIR}${PREFIX}/lib/lyona` with mode 644:

   ```diff
   -	scripts/dev-sync-install.sh \
   ...
   -	scripts/dwm-packages.sh \
   -	scripts/dwm-paths.sh \
   -	scripts/dwm-simple-watch.sh \
   -	scripts/dwm-xsettings-config.sh \
   ...
   -	scripts/dwm-watchdog.sh \
   ...
   -	scripts/dwm-utils.sh \
   +INSTALL_LIBS = scripts/dwm-packages.sh scripts/dwm-paths.sh scripts/dwm-simple-watch.sh \
   +	scripts/dwm-utils.sh scripts/dwm-watchdog.sh scripts/dwm-xsettings-config.sh \
   +	scripts/lyona-install-verify.sh
   +LIB_DIR = ${PREFIX}/lib/lyona
   ```

   ```make
   	@echo "==> Installing shared shell code..."
   	for f in ${INSTALL_LIBS}; do \
   		install -Dm644 "$$f" ${DESTDIR}${LIB_DIR}/$$(basename "$$f"); \
   	done
   ```

   `dev-sync-install.sh` is a developer tool that runs from a checkout; it stops being
   installed at all.
2. Every sourcing site (20 files) finds the library through one line:

   ```bash
   # The checkout keeps libraries beside the scripts; an install keeps them in
   # PREFIX/lib/lyona, beside PREFIX/bin.
   lyona_lib=${BASH_SOURCE[0]%/*}
   [[ -f $lyona_lib/dwm-paths.sh ]] || lyona_lib=${lyona_lib%/bin}/lib/lyona
   # shellcheck source=scripts/dwm-paths.sh
   . "$lyona_lib/dwm-paths.sh"
   ```

   Sites: 7 source `dwm-paths.sh` through `${BASH_SOURCE[0]%/*}`, 3
   `dwm-watchdog.sh` through `$script_dir`, 2 `dwm-simple-watch.sh`, 2
   `dwm-xsettings-config.sh`, 2 `dev-sync-install.sh` (`lyona-update`; step 4
   replaces those), and `dwm-packages.sh` and `dwm-utils.sh` in `install.sh` and
   `check-deps.sh` (which run from the checkout and are unchanged).
3. Uninstall and `release-check` learn the new directory. `make release-check`
   pins the staged layout and gains
   `usr/lib/lyona/<each library>`.
4. **Test.** A staged `DESTDIR` install has the libraries in `usr/lib/lyona` and not
   in `usr/bin`. Every installed command that sources one runs from the staged
   `usr/bin` (`--help` or its cheapest read action) with `PATH` holding only
   `usr/bin`. The checkout still works unchanged: the full suite runs from it.

**Implemented (2026-09-28, working tree, nothing committed).** Where it differs
from the text above:

- **`dev-sync-install.sh` is still installed**, to `lib/lyona`: the installed
  `lyona-update` sources it for the live-install check until step 4 replaces that.
  `lyona-install-verify.sh` does not exist yet; it arrives with step 4.
- **18 files changed, not 20.** `check-deps.sh` is an installed command, so it
  changed too (it uses `source`, and `SCRIPT_DIR`); `install.sh` and `ci-local.sh`
  run from the checkout and did not change. The POSIX `sh` callers use
  `[ -f ... ]` and `$script_dir` in place of `[[ ]]` and `BASH_SOURCE`.
- **The fallback is `${lyona_lib%bin}lib/lyona`**, not `%/bin`: it maps
  `/usr/bin` to `/usr/lib/lyona` either way, and also gives `lib/lyona` for a bare
  `bin`.
- **`make install-system` removes the old copies from `PREFIX/bin`**, and
  `make uninstall` removes both places, so an upgrade leaves no stale library on
  `PATH`.
- **`dev-sync-install.sh --check`** reads `INSTALL_LIBS`, verifies each library in
  `PREFIX/lib/lyona`, reports a copy left in `PREFIX/bin` as `STALE`, and backs up
  both places.
- **`tests/test-shell-contracts.sh`** reads both lists through `make` (the old `sed`
  range read past the end of `INSTALL_COMMANDS` once another list followed it).
  It requires:
  - every helper an installed command sources through `$lyona_lib` to be in
    `INSTALL_LIBS`;
  - no installed command to source a helper beside itself;
  - no file to be in both lists.

  Mutation-checked in a scratch copy: dropping `dwm-utils.sh` from `INSTALL_LIBS`,
  and reverting `check-deps.sh` to `$SCRIPT_DIR`, each fail it. The first
  mutation initially passed, because the pattern matched only `.`, not `source`.
- **`tests/test-dev-sync-install.sh`** installs the libraries as `make` does. It
  checks that a library moved from `lib/lyona` back to `bin` is reported as both
  `MISSING INSTALL` and `STALE`.
- **Staged install** (`make install-system DESTDIR=... PREFIX=/usr`):
  - the seven libraries are in `usr/lib/lyona` at 0644, and none are in `usr/bin`;
  - all 14 sourcing commands, run from the staged `usr/bin`, reach their own usage
    text or error;
  - with `usr/lib/lyona` moved away, each fails at its source line.
- **Checks.**
  - PASS: `check-install-preservation`, `release-check`, `check-dev-sync-install`,
    `check-shell`, `check-format` and `check-lyona-update`.
  - `scripts/run-tests` ran twice. Each run hit one failure, in a different test,
    and each test passed three times out of three when rerun alone:
    - `check-quickshell-watcher-lifetime-xvfb`: the survivors were `xprop -spy`
      from `dwm-quickshell-state` and `inotifywait` from
      `dwm-settings-appearance` or `dwm-accessibility-settings`, none of them
      changed here;
    - `check-quickshell-health-xvfb`: "Control Center popup did not open". It
      passed in the first run.
  - Not yet: a clean full run in one pass.

### Step 2 -- a system data directory

1. `install-system` installs `config/*.toml`, the managed `themes.toml`,
   `config/quickshell/` and the session's `assets/` to
   `${DESTDIR}${PREFIX}/share/lyona/`, root-owned.
2. dwm finds its default TOMLs there, relative to its executable:

   ```c
   /* PREFIX/share/lyona, from PREFIX/bin/dwm: found at run time, not compiled in,
    * so it matches wherever install-system put it (Sync Sprint 12 S12-13). */
   static int
   lyona_share_dir(char *out, size_t size)
   {
   	char exe[PATH_MAX], *slash;
   	ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);

   	if (n <= 0)
   		return 0;
   	exe[n] = '\0';
   	if (!(slash = strrchr(exe, '/')))
   		return 0;
   	*slash = '\0';                     /* PREFIX/bin */
   	if (!(slash = strrchr(exe, '/')))
   		return 0;
   	*slash = '\0';                     /* PREFIX */
   	return pathjoin(out, size, exe, "share/lyona");
   }
   ```

   `toml_default_dir` becomes `lyona_share_dir()/config`. A checkout build run in
   place (`./dwm`) has no `../share/lyona`, so dwm also tries `dirname(exe)/config`,
   the checkout's own `config/`. That is how the Xvfb tests run it today.
3. The managed-`themes.toml` readers (`theme-apply.sh`, `dwm-settings-appearance`,
   `dwm-settings-theme`) take `$lyona_lib/../../share/lyona/config/themes.toml`,
   falling back to the checkout's `config/themes.toml` beside `scripts/`. They keep
   their existing `DWM_APPEARANCE_MANAGED_THEMES_FILE` override for tests.
4. `dwm-controlcenter`, `dwm-keybinds` and `dwm-settings` drop the stale
   `.../lyona/config/quickshell/shell.qml` path for
   `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml`, where AGENTS.md says
   the managed shell lives.
5. **Test.** A staged install, with no `~/.local/share/lyona`, starts dwm under Xvfb
   with the default hotkeys loaded (the existing reload test's log line) and themes
   applying from the system copy.

**Implemented (2026-09-28, working tree, nothing committed).** Where it differs
from the text above:

- **Only the three TOMLs are installed** (`INSTALL_DEFAULTS`, to
  `PREFIX/share/lyona/config`, mode 0644). The Quickshell tree and `assets/`
  are not:
  - nothing reads either from a system copy yet: `install-user` copies the shell
    from the checkout;
  - no session script reads `assets/` from the data directory;
  - whichever step first reads them installs them.
- **dwm** (`default_config_dir`):
  - It uses `PREFIX/share/lyona/config` when that directory exists, else
    `dirname(exe)/config`.
  - If `/proc/self/exe` cannot be read, the default paths stay empty. The loaders
    treat an empty path as missing, and the watch is skipped.
  - It logs `dwm: shipped defaults from <dir>`.
- **Shell readers.**
  - `lyona_default_config_dir LIB`, in `dwm-paths.sh`, maps `lib/lyona` to
    `../../share/lyona/config`, and anything else to `../config`. It prints the
    directory resolved with `cd -P`, or fails. Its subshell body keeps the
    caller's working directory.
  - `theme-apply.sh`, `dwm-settings-appearance` and `dwm-settings-theme` use it;
    the latter two now source `dwm-paths.sh`.
  - `dwm-quickshell-controlcenter` is POSIX `sh`, so it has its own copy of the
    lookup. `theme_set` no longer passes `DWM_APPEARANCE_MANAGED_THEMES_FILE`,
    since the theme helper finds the file itself.
  - `DWM_APPEARANCE_MANAGED_THEMES_FILE` still overrides the lookup.
- **Found in the survey: the shell watched the per-user copy.**
  `AppearanceModel.qml` watched `dataHome/lyona/config/themes.toml`, and nothing
  in QML can find `PREFIX`.
  - The appearance snapshot now has a `managed\t<path>` record, and the model
    takes its watch path from that.
  - Older parsers ignore unknown records.
- **The stale Quickshell path** is removed from `dwm-controlcenter`,
  `dwm-keybinds`, `dwm-settings` and `docs/src/control-center.md`.
- **Tests.** The tests that seeded `~/.local/share/lyona/config` to exercise the
  default lookup now run from an installed layout (`bin`, `lib/lyona`,
  `share/lyona/config`):
  - `test-dwm-config-fallback.sh` runs a copied dwm. It checks the log line for
    the installed layout and for `./dwm` in the checkout, and still removes the
    defaults for the emergency-keys case.
  - `test-dwm-settings-appearance.sh`: a dracula copy left in the per-user
    directory is ignored in favour of the installed nord file. It also checks the
    `managed` record.
  - `test-dwm-settings-theme.sh` and `test-quickshell-controlcenter.sh`.

  Tests that still seed the per-user copy (`test-xvfb-runtime.sh`,
  `test-quickshell-session-actions.sh` and others) seed files identical to the
  checkout's, so it is dead setup. Step 6 removes it.
- **Staged install** (`make install-system DESTDIR=... PREFIX=/usr`, empty `HOME`):
  - under Xvfb, dwm logged `shipped defaults from <stage>/usr/share/lyona/config`,
    and Super+2 switched to tag 2;
  - the staged `dwm-settings-appearance` reported `source managed` and `managed`
    with the staged file, and `dwm-quickshell-controlcenter themes` read it;
  - `theme-apply.sh` applied the default theme;
  - no `~/.local/share/lyona` was created.
- **Checks.**
  - `quickshell-qmllint` on `AppearanceModel.qml`: clean.
  - PASS: `check-shell`, `check-format`, `check-install-manifest`,
    `release-check`, `check-install-preservation`, `check-dev-sync-install`,
    `check-lyona-update`, `check-quickshell-appearance-model`, `check-settings`
    and `check-quickshell-settings-xvfb`.
  - `scripts/run-tests`: PASS, in one run.
- **Not verified:**
  - a live session with the real Settings window, including a watched change to
    the shipped `themes.toml` reloading the Appearance page;
  - an upgrade of a real install.

### Step 3 -- one lookup for helpers and session scripts

1. `Commands.qml` loses `preferManaged`. One order for every helper: the override,
   then `PATH`.

   ```diff
    function helperCommand(helper, action, args, preferManaged) {
        const argv = args || [];
   -    const managedScript = "\"$data_dir/scripts/" + helper + "\"";
   -    const dataDir = "data_dir=${XDG_DATA_HOME:-$HOME/.local/share}/lyona";
   -    const runManaged = "[ -x " + managedScript + " ] && exec " + managedScript + " \"$@\"";
   -    const runPath = "command -v " + helper + " >/dev/null 2>&1 && exec " + helper + " \"$@\"";
   -    const fallback = "exec " + managedScript + " \"$@\"";
   -    const orderedChecks = preferManaged
   -        ? [runManaged, runPath, fallback]
   -        : [runPath, runManaged, fallback];
   -    const script = [dataDir].concat(orderedChecks).join("; ");
   +    // The developer override (LYONA_DEV_SCRIPTS, never set by an install), then
   +    // the installed command on PATH: one runtime source (Sync Sprint 12 S12-13).
   +    const script = '[ -n "${LYONA_DEV_SCRIPTS:-}" ] && [ -x "$LYONA_DEV_SCRIPTS/' + helper
   +        + '" ] && exec "$LYONA_DEV_SCRIPTS/' + helper + '" "$@"; exec ' + helper + ' "$@"';
   ```

   The fourth argument stays accepted and ignored, so the 23 call sites do not have
   to change in the same step. A later cleanup can drop it.
2. dwm runs `autostart.sh` and `autostop.sh` from the override when it is set (and
   dwm is not root), else from `lyona_lib_dir()` (`PREFIX/lib/lyona`, found like the
   share directory). The `$XDG_DATA_HOME/lyona/scripts` and `~/.lyona` lookups go.

   ```c
   	const char *dev = geteuid() != 0 ? getenv("LYONA_DEV_SCRIPTS") : NULL;

   	if (dev && *dev && pathjoin(path, sizeof(path), dev, script) && access(path, X_OK) == 0)
   		; /* the override */
   	else if (!lyona_lib_dir(dir, sizeof(dir)) || !pathjoin(path, sizeof(path), dir, script))
   		return 0;
   ```

   `autostartsh` becomes `"autostart.sh"`: the override names the `scripts/`
   directory itself.
3. `autostart.sh`'s `${0%/*}/<helper>` sibling lookups keep working. Under the
   override the siblings are the checkout's scripts; in `PREFIX/lib/lyona` there are
   no siblings, so the existing `command -v` fallback finds the installed commands.
4. **Test.**
   - A staged install with an empty `~/.local/share` starts a working session under
     Xvfb (dwm, autostart, Quickshell with its watchers). This is the
     "never ran `install-user`" case that is broken today.
   - With `LYONA_DEV_SCRIPTS` set, a stub `autostart.sh` there is the one that runs.
   - With dwm run as root in a container, the override is ignored.

### Step 4 -- no more per-user copy

1. `install-user` stops copying:

   ```diff
   -	@echo "==> Syncing local repo to data dir..."
   -	mkdir -p ${DATA_DIR}
   -	if [ "$$(realpath .)" != "$$(realpath ${DATA_DIR})" ]; then \
   -		rm -rf "${DATA_DIR}/config" "${DATA_DIR}/scripts"; \
   -		cp -aL --no-preserve=ownership config scripts "${DATA_DIR}/"; \
   -	fi
   +	@echo "==> Removing the old per-user copy of the scripts and defaults..."
   +	@# The system copy in ${PREFIX}/lib/lyona and ${PREFIX}/share/lyona is the only
   +	@# runtime source (S12-13). These two trees were always replaced on every
   +	@# install, so nothing of the user's is in them.
   +	rm -rf "${DATA_DIR}/config" "${DATA_DIR}/scripts"
   ```

   **Migration.** Existing installs lose the two trees on their next `install-user`
   or `lyona-update apply`, which runs `install-user`. Both trees were already
   deleted and recopied on every install (`Makefile:306`), so they never held
   anything of the user's. Nothing else under `~/.local/share/lyona` is touched.
   The CHANGELOG gets a migration note: a developer who ran from the per-user copy
   now sets `LYONA_DEV_SCRIPTS`.
2. `install-user`'s other `DATA_DIR` uses go: the `find ${DATA_DIR} ... chmod +x`
   pass (`Makefile:384`), and `LYONA_DATA_DIR` in the user record (`:410`) becomes
   `LYONA_DATA_DIR=${PREFIX}/share/lyona`. `lyona-version` reads the record, so it
   and its test change together.
3. The functions `lyona-update` needs move from `dev-sync-install.sh` to
   `scripts/lyona-install-verify.sh` (a library, step 1): `prepare_expected_files`,
   `verify_file`, `verify_executable`, `verify_tree`, `verify_install`,
   `add_system_backup_path`, `backup_live_install` and `runtime_verify`.
   `dev-sync-install.sh` sources that same library, so there is one copy.
4. `verify_install` drops `verify_tree "$repo_dir/scripts" "$data_dir/scripts"` and
   `verify_tree "$repo_dir/config" "$data_dir/config"`, and gains the system trees:
   `verify_tree "$repo_dir/config" "$prefix/share/lyona/config"` and each library
   in `$prefix/lib/lyona`.
5. The backups: `backup_live_install` stops archiving `lyona-data.tar`, since there
   is no managed data tree left. `restore_user_tree` still restores one from an
   older backup, then removes the old `scripts/` and `config/` from it, so a
   rollback past this change does not bring back a stale second copy.
6. **Test.**
   - `test-install-preservation.sh`: after `install-user`, no `~/.local/share/lyona/scripts`
     or `config`, and an existing pair from an older install is removed while a user
     file beside them stays.
   - `test-dev-sync-install.sh` and `test-lyona-update.sh` pass with the moved
     library.
   - `lyona-update` no longer mentions `dev-sync-install.sh`.

### Step 5 -- the override is visible

1. `dwm-diagnostics` prints `LYONA_DEV_SCRIPTS=<path>` (or `not set`).
2. `lyona-update check` adds `override\tdev-scripts\t<path>` when it is set (JSON:
   `devScripts`). `UpdateModel.qml` shows "Running helpers from a development
   checkout: <path>" under Settings -> System.
3. **Test.** `test-lyona-update.sh` checks the line with the variable set and its
   absence without it. A QML check covers the note's visibility.

### Step 6 -- the tests use the override

The 24 tests that put stubs in `$XDG_DATA_HOME/lyona/scripts` keep that directory
and add `LYONA_DEV_SCRIPTS="$data_home/lyona/scripts"` to the environment they start
the shell or dwm with. That is one line each, and the stubs keep working through the
override instead of the managed-first lookup:

`test-lyona-version.sh`, `test-quickshell-settings-responsiveness-xvfb.sh`,
`test-quickshell-large-surfaces-xvfb.sh`, `test-quickshell-health-xvfb.sh`,
`test-quickshell-update-ui-xvfb.sh`, `test-quickshell-queued-run-xvfb.sh`,
`test-quickshell-update-progress-xvfb.sh`, `test-quickshell-wallpaper-reconcile-xvfb.sh`,
`test-quickshell-session-actions.sh`, `test-settings.sh`,
`test-quickshell-plain-text-xvfb.sh`, `test-quickshell-picom-model-xvfb.sh`,
`test-dwm-reload-theme-xvfb.py`, `test-dwm-config-fallback.sh`,
`test-quickshell-system-management-xvfb.sh`, `test-desktop-smoke-xvfb.sh`,
`test-quickshell-watcher-lifetime-xvfb.py`, `test-picom-xvfb.py`,
`test-dwm-settings-theme.sh`, `test-xvfb-runtime.sh`,
`test-quickshell-idle-watchers-xvfb.py`, `fixtures/picom-model.py`,
`fixtures/queued-run.py`, `test-quickshell-settings-xvfb.sh`.

The ones that start dwm with `XDG_DATA_HOME` pointing at a scratch data home (the
reload, lifetime and idle tests) need the scratch `scripts/` there to hold
`autostart.sh`, which they already copy.

### Step 7 -- moved to S12-14

Moving the 32 scripts that compute XDG paths inline onto one `dwm-paths.sh` function
moved to S12-14 ("one copy of shared safety logic"), decided with the maintainer on
2026-09-28. The list and the approach are recorded there.

## Decisions (2026-09-28, asked of the user directly)

1. **Step 7** (inline XDG paths) moved to S12-14.
2. **Older backups' `lyona-data.tar`:** restore it, then strip `scripts/` and
   `config/` from it (step 4.5), so a rollback puts back everything else in the data
   folder without a stale second copy.
3. **`~/.lyona/`**, dwm's last-resort autostart location (an inherited dwm-titus
   convention nothing in Lyona creates or documents), is removed with the rest in
   step 3. `LYONA_DEV_SCRIPTS` covers a hand-made custom `autostart.sh`.

## Verification (whole item)

- A staged install (`DESTDIR`) and a container install of a fresh account that never
  ran `install-user` both reach a working session under Xvfb.
- With `LYONA_DEV_SCRIPTS` set, the checkout's scripts run, and dwm and
  `lyona-update check` both report it. Run as root, it is ignored.
- `rg '\.local/share/lyona/scripts|data_dir/scripts'` finds nothing outside the
  migration note and the old-backup restore.
- The full suite passes.
