# S12-14 plan -- one reader per shared format, one copy of shared safety logic

Parent: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-14-one-reader-per-shared-format-one-copy-of-shared-safety-logic`.
Issue `#177`. Five parts: four from the review, and one (XDG paths) added from
S12-13. Each step below is reviewable and testable on its own; the order puts the
mechanical, no-behaviour-change steps first. Nothing here is implemented yet.

## What exists today (surveyed 2026-09-29, `main` at `d356657`)

### 1. `themes.toml` has seven readers

| Reader | What it reads | Grammar |
|---|---|---|
| `tomlparser.c` (dwm) | everything | the reference; S12-05 pinned comments, same-line arrays, booleans |
| `theme-apply.sh` `toml_get` | one key of one section, per call (about 25 calls) | awk: first match, `"` stripped anywhere, a `#` after whitespace ends the value |
| `lyona-gtk-theme` `toml_get`, `theme_ids` | keys, and the `[theme.*]` ids | the same awk, copied |
| `dwm-quickshell-controlcenter` `active_theme`, `themes` | `[active] theme`, the ids | its own awk; `$1 == "theme"` needs a space before `=` |
| `dwm-settings-appearance` `parse_themes` | every theme, validated | a Bash line parser with its own limits (4095-byte lines, inline tables) |
| `dwm-settings-theme` `theme_source_structure_is_mutable`, `prepare_theme_file`, `append_managed_theme` | the `[active]` section; one theme section | Bash, and these **edit** the file, keeping its layout |
| `Makefile` (`uninstall`, `check-install-manifest`) | the `[theme.*]` ids of the shipped file | awk |

**Found in the survey:** `tomlparser.c` stops storing entries at
`TOML_MAX_ENTRIES` (512) without saying so. The shipped `themes.toml` has 407
entries in 15 themes, about 27 each, so a user who adds four more themes loses
the ones at the end of the file in dwm, silently.

### 2. The preview and rollback state machine is copied

- `dwm-settings-font` and `dwm-settings-toolkit` have the same eleven functions,
  in the same order: `valid_token`, `preview_exchange_path`,
  `cleanup_preview_exchange`, `write_preview_token`, `clear_preview`,
  `preview_token`, `preview_setup_cleanup`, `expire_preview_locked`,
  `acquire_lock`, `start_preview` and `finish_preview`.
- They differ in three ways:
  - the program name and the `DWM_SETTINGS_<NAME>_NOW` and `_BOOT_ID` test
    hooks;
  - the user-facing labels;
  - the domain model: font has a family and a scale, toolkit a capability map.
- `dwm-settings-display`, `-input`, `-wallpaper` and `-theme` each have a
  different shape (a root rollback, a watchdog, a claim protocol). They are not
  copies of the font and toolkit pair.
- **QML:** the review's "five countdown timers" does not hold up. The timers in
  `AppearanceModel.qml` and `SettingsModel.qml` are settle, retry and restart
  timers. The preview countdown state is 43 references in `AppearanceModel.qml`
  with one retry timer (`previewZeroRetryTimer`), shown by
  `AppearanceSettingsPane.qml` and `shell.qml`.

### 3. The trust checks are copied

- `trusted_parent_chain` is in five scripts: `dwm-settings-display-root`,
  `lyona-update-root`, `dwm-settings-display`, `dwm-system-health` and
  `dwm-settings-provider`.
  - The first three are byte-identical.
  - `dwm-system-health` treats a failed `stat` as untrusted
    (`|| printf 1`), where the others let `[[ "" == 0 ]]` fail.
  - `dwm-settings-provider` is the same logic in POSIX `[ ]`.
- `trusted_file` is in the two root helpers, identical.
- Wrappers built on top of these: `trusted_root_helper` (`lyona-update`,
  `dwm-settings-display`), `trusted_system_command` and `trusted_system_helper`
  (`dwm-system-health`), `trusted_health_helper`, `trusted_installed_file` and
  `trusted_display_helper` (`dwm-settings-provider`).

### 4. Resident watchers

- 16 `Commands.watchCommand` users; 4 use `WatchedProcess.qml`
  (`AccessibilityModel`, `DefaultAppsModel`, `AutostartModel`, `PowerModel`).
- `WatchedProcess` only restarts a settle timer on each line. Watchers that parse
  their lines cannot use it as it is: `DwmState`, `NetworkModel`,
  `ControlsModel` (audio and media), `BluetoothModel`, the system-management
  pair and `SettingsModel`'s three.

### 5. XDG paths

32 scripts compute the XDG directories inline; 20 are Bash and 12 POSIX `sh`.
- **Validated:** `lyona-update:45-52` accepts a set value only if it is absolute,
  as the XDG Base Directory spec requires, and otherwise falls back.
- **Not validated:** most scripts use `${XDG_CONFIG_HOME:-$HOME/.config}`, which
  accepts a relative value.

## Decisions (2026-09-29, asked of the user directly)

- **D-20, the canonical reader:** a C tool, `lyona-toml`, built from dwm's own
  `tomlparser.c`. It is not a second grammar in awk, and not a Bash `dump`
  action.
- **D-21, the root helpers' trust checks:** the two root helpers keep a
  self-contained copy, and a contract test fails if it ever differs from the
  shared library. They source nothing at run time.

## Steps

### Step 1 -- XDG paths from one place (part 5)

1. New `scripts/dwm-xdg.sh`, a library in `INSTALL_LIBS`. It is POSIX, so both
   Bash and `sh` scripts can source it:

   ```sh
   # shellcheck shell=sh
   #
   # The XDG base directories, from the environment or their fallbacks under
   # $HOME (Sync Sprint 12 S12-14). A set value is used only when it is
   # absolute, as the XDG Base Directory spec requires; a relative one is
   # ignored. Sets config_home, data_home, state_home and cache_home; fails
   # when a fallback is needed and HOME is unset.
   lyona_xdg_dirs() {
   	case ${XDG_CONFIG_HOME:-} in
   	/*) config_home=$XDG_CONFIG_HOME ;;
   	*) config_home=${HOME:?HOME is required for XDG_CONFIG_HOME fallback}/.config ;;
   	esac
   	case ${XDG_DATA_HOME:-} in
   	/*) data_home=$XDG_DATA_HOME ;;
   	*) data_home=${HOME:?HOME is required for XDG_DATA_HOME fallback}/.local/share ;;
   	esac
   	case ${XDG_STATE_HOME:-} in
   	/*) state_home=$XDG_STATE_HOME ;;
   	*) state_home=${HOME:?HOME is required for XDG_STATE_HOME fallback}/.local/state ;;
   	esac
   	case ${XDG_CACHE_HOME:-} in
   	/*) cache_home=$XDG_CACHE_HOME ;;
   	*) cache_home=${HOME:?HOME is required for XDG_CACHE_HOME fallback}/.cache ;;
   	esac
   }
   ```

2. Each script replaces its inline block with one call. `lyona-update` shows the
   pattern:

   ```diff
   -config_home=${XDG_CONFIG_HOME:-}
   -data_home=${XDG_DATA_HOME:-}
   -state_home=${XDG_STATE_HOME:-}
   -cache_home=${XDG_CACHE_HOME:-}
   -[[ $config_home == /* ]] || config_home=${HOME:?HOME is required for XDG_CONFIG_HOME fallback}/.config
   -[[ $data_home == /* ]] || data_home=${HOME:?HOME is required for XDG_DATA_HOME fallback}/.local/share
   -[[ $state_home == /* ]] || state_home=${HOME:?HOME is required for XDG_STATE_HOME fallback}/.local/state
   -[[ $cache_home == /* ]] || cache_home=${HOME:?HOME is required for XDG_CACHE_HOME fallback}/.cache
   +# shellcheck source=scripts/dwm-xdg.sh
   +. "$lyona_lib/dwm-xdg.sh"
   +lyona_xdg_dirs
   ```

   - **The 20 Bash scripts** find `$lyona_lib` as S12-13 set up. The ones that
     do not yet define it gain the three lookup lines.
   - **`theme-apply.sh`** reads `${XDG_CONFIG_HOME:-$HOME/.config}` at 25
     sites. They become `$config_home` and friends, computed once.
   - **The 12 POSIX `sh` scripts** use the POSIX lookup
     (`lyona_lib=$script_dir; [ -f "$lyona_lib/dwm-xdg.sh" ] || lyona_lib=${lyona_lib%bin}lib/lyona`),
     with three exceptions.
   - **The exceptions:** `dwm-controlcenter`, `dwm-keybinds` and `dwm-settings`
     stay inline. Each is a four-line wrapper reading one variable, so the
     lookup would be longer than what it replaces. Each gets a comment:
     `# One variable; see dwm-xdg.sh for the shared rule.`
   - `ci-local.sh` and `dev-sync-install.sh` run from a checkout. They source
     `scripts/dwm-xdg.sh` beside themselves.
3. **Behaviour change, stated:** a relative `XDG_*_HOME` now falls back
   everywhere, as `lyona-update` already does. Before, most scripts used it
   relative to the working directory. The CHANGELOG says so.
4. **Test.** `test-shell-contracts.sh` gains checks that:
   - no script outside `dwm-xdg.sh` and the three named wrappers assigns from
     `XDG_(CONFIG|DATA|STATE|CACHE)_HOME`;
   - `lyona_xdg_dirs` with a relative `XDG_CONFIG_HOME` gives `$HOME/.config`.

   The full suite is the behaviour check, since nothing else changes.

**Implemented (2026-09-29, working tree, nothing committed).** Where it differs
from the text above:

- **A lenient mode.** `lyona_xdg_dirs lenient` leaves a directory empty, rather
  than exiting, when its fallback needs an unset `HOME`. HOME is needed only for
  a fallback, so a fully set XDG environment works without it. Lenient is used
  by:
  - `dwm-settings-font` and `-toolkit`, which report a missing HOME through
    their protocol (`require_paths`);
  - `autostart.sh`, where exiting would abort the session start;
  - `dwm-quickshell-controlcenter`, on every panel poll;
  - `dwm-terminal`'s `configured_terminal`;
  - `dwm-session-launch`'s preview check (its theme-environment step stays
    fatal, as before);
  - `dwm-settings-provider`'s process check, where a missing HOME now means "not
    ours" rather than trusting `/.config`;
  - `dwm-quickshell-launcher`'s data directory.
- **Migrated: 29 scripts.**
  - Bash: the 20 listed in the parent item.
  - POSIX `sh`: `autostart.sh`, `lyona-version`,
    `seed-autostart-overrides.sh`, `migrate-graphical-session.sh`,
    `dwm-session-launch`, `dwm-settings-provider`,
    `dwm-quickshell-controlcenter` and `dwm-quickshell-launcher`.
  - `dwm-quickshell-controlcenter`'s `script_dir`/`lyona_lib` lookup moved up
    to its first use.
  - Two functions keep their four variables `local` (`dwm-system-health`,
    `dwm-terminal`).
- **Left inline, each with a comment:**
  - `dwm-system-health`'s two deny patterns, which must never fail and
    deliberately use the raw values;
  - `lyona-install-verify.sh`, which falls back under `USER_HOME`, not `HOME`,
    and refuses relative values through `validate_live_root`;
  - the three one-line wrappers.

  Also left as they are: `dev-sync-install.sh`, which only passes its values
  on; the Python in `seed-default-apps.sh`, `dwm-settings-picom`,
  `dwm-settings-display-profiles` and `dwm-system-management`; and `install.sh`,
  which passes explicit values to `make`.
- **Test:** `test-shell-contracts.sh` fails if any other script computes an XDG
  fallback inline. It also checks that a relative value falls back, that lenient
  gives an empty directory, and that the fatal form fails without HOME.
  Mutation-checked: an inline fallback added to `dwm-panel-settings` fails it.
- **Staged install:** `dwm-xdg.sh` is in `usr/lib/lyona`, and the 23 migrated
  installed commands start from the staged `usr/bin`.
- **Tests that build their own layouts** needed the new library, like the ones
  S12-13 changed for `dwm-paths.sh`:
  - `test-quickshell-controlcenter.sh`, `test-dwm-settings-theme.sh` and
    `test-dwm-settings-appearance.sh`: their installed layouts;
  - `test-quickshell-settings-xvfb.sh`, `test-quickshell-health-xvfb.sh` and
    `test-quickshell-large-surfaces-xvfb.sh`: their fake checkouts. The last two
    also gained the other libraries their copied helpers source;
  - `test-dwm-settings-toolkit.sh`: its stub directory;
  - `test-autostart.sh`: its copies of `autostart.sh`, and the extracted
    `apply_power_settings`, which now reads the `config_home` the script sets;
  - `test-settings.sh`: its five lone copies of the provider. Its source pin on
    the old inline `case` now pins `lyona_xdg_dirs lenient`.
- **Results.** Every `make check` target passes except
  `check-quickshell-watcher-lifetime-xvfb`: the first 61 in a full run, and the
  59 after it run directly, since `make check` stops at the first failure.
  - That test is Sprint 13's flake (S13-01, `#197`). Run alone it failed 1 of 5
    here and 2 of 5 on a clean `main` worktree.
  - The full suite has not passed in one run on this branch for that reason.

### Step 2 -- one copy of the trust checks (part 3)

1. New `scripts/dwm-trust.sh`, a POSIX library in `INSTALL_LIBS`. It holds the
   strictest variant, `dwm-system-health`'s, where a failed `stat` is untrusted:

   ```sh
   # shellcheck shell=sh
   #
   # Trust checks for files run with more rights than the caller's own (Sync
   # Sprint 12 S12-14). The two root helpers keep a byte-identical copy of these
   # functions, since a root helper sources nothing at run time (D-21);
   # tests/test-shell-contracts.sh fails if the copies differ.

   # Every directory from PATH's parent up to / is a real directory, owned by
   # root and not group- or other-writable.
   trusted_parent_chain() {
   	lyona_trust_parent=${1%/*}
   	while :; do
   		[ -d "$lyona_trust_parent" ] && [ ! -L "$lyona_trust_parent" ] || return 1
   		[ "$(stat -c %u -- "$lyona_trust_parent" 2>/dev/null || printf 1)" = 0 ] || return 1
   		find "$lyona_trust_parent" -maxdepth 0 -type d ! -perm /022 -print -quit 2>/dev/null |
   			grep -q . || return 1
   		[ "$lyona_trust_parent" = / ] && return 0
   		lyona_trust_parent=${lyona_trust_parent%/*}
   		[ -n "$lyona_trust_parent" ] || lyona_trust_parent=/
   	done
   }

   # PATH is itself canonical, and a root-owned executable nobody else can
   # write, in a trusted directory chain.
   trusted_file() {
   	lyona_trust_path=$(readlink -f -- "$1" 2>/dev/null) || return 1
   	[ -n "$lyona_trust_path" ] && [ "$lyona_trust_path" = "$1" ] || return 1
   	trusted_parent_chain "$lyona_trust_path" || return 1
   	[ -f "$lyona_trust_path" ] && [ ! -L "$lyona_trust_path" ] && [ -x "$lyona_trust_path" ] || return 1
   	[ "$(stat -c %u -- "$lyona_trust_path" 2>/dev/null || printf 1)" = 0 ] || return 1
   	find "$lyona_trust_path" -maxdepth 0 -type f ! -perm /022 -print -quit 2>/dev/null | grep -q .
   }
   ```

   The variables are prefixed rather than `local`, so the file stays POSIX.
2. `dwm-settings-display`, `dwm-system-health` and `dwm-settings-provider` delete
   their copy and source the library. Their wrappers (`trusted_root_helper` and
   the rest) stay where they are, since each names its own paths.
3. The two root helpers replace their functions with the library's text,
   verbatim, between marker comments:

   ```sh
   # BEGIN dwm-trust.sh (kept identical by tests/test-shell-contracts.sh)
   ...the two functions above...
   # END dwm-trust.sh
   ```

4. **Test.**
   - `test-shell-contracts.sh`: the text between the markers in each root helper
     equals `dwm-trust.sh` from `trusted_parent_chain() {` on, and no other
     script defines either function.
   - The existing tests of the root helpers, the provider and health cover the
     behaviour.
   - Mutation: flip one character in a root helper's copy, and the contract test
     fails.

**Implemented (2026-09-29, working tree, nothing committed).** Where it differs
from the text above:

- **Two more copies than the survey counted.** `lyona-update`'s
  `trusted_root_helper` and `dwm-settings-display`'s repeated `trusted_file`'s
  checks inline in their loops. Both now call `trusted_file`.
  - **Found: `lyona-update`'s copy never checked the directory chain.** It
    checked the file's owner and mode, but not that every directory above it
    is root-owned and not writable by others. With a custom `PREFIX`, it could
    have handed `pkexec` a root helper in a user-writable directory.
    `trusted_file` closes that.
- **`dwm-system-health`'s two wrappers** (`trusted_system_command`,
  `trusted_system_helper`) resolve symlinks first and keep their deny list.
  Their owner, mode and chain checks on the resolved path are now
  `trusted_file "$resolved"`. That adds an executable check to the helper
  lookup, which only checked `-f` before.
- **`dwm-settings-provider`'s `trusted_installed_file`** was `trusted_file`
  under another name. Its three calls use the library.
- **The pinned copy** in each root helper sits between `# BEGIN dwm-trust.sh`
  and `# END dwm-trust.sh`, after a three-line header. It is the library's text
  from `# Every directory from PATH's parent up to` to the end. The root helpers
  gain the stricter `stat` failure handling and the `--` separators with it.
- **Tests that stage their own copies** of the provider, health or display
  helper gained `dwm-trust.sh`: `test-settings.sh`,
  `test-quickshell-settings-xvfb.sh`, `-health-xvfb.sh` and
  `-large-surfaces-xvfb.sh`.
  - **Found: `test-quickshell-system-management-xvfb.sh` ran broken helpers.**
    It passed after step 1 without `dwm-xdg.sh` beside its copies, so the
    provider, health and display helpers it stages were failing at load, and
    the shell showed them as unavailable without failing the test. It now
    stages both libraries.
  - A guard against that whole class (a staged helper whose libraries are
    missing) is not added here; it is noted for S12-14's verification.
- **Contract test:**
  - each root helper's pinned text must equal the library's;
  - neither function may be defined anywhere else.

  Mutation-checked: `-perm /022` changed to `/002` in `lyona-update-root`'s
  copy, and a stray `trusted_file` in another script, each fail it.
- **Source pins** in `test-system-health.sh` and `test-settings.sh` named the
  old functions; they now pin the `trusted_file` calls.
- **Root helpers, run as root:**
  - `check-settings-display-security` and `check-update-root-backups` skip
    outside a container, so they were run as S10-03 documents: `docker run
    --rm --network none -e DWM_SECURITY_CONTAINER=1` on the CI image, with the
    working tree mounted read-only. Both passed.
  - `check-shell-contracts`, `check-system-health` and `check-settings` also
    pass in the CI container (`scripts/ci-local.sh --each`).
- **`scripts/run-tests`:** PASS, in one run. The watcher-lifetime test passed
  this time.

### Step 3 -- `lyona-toml`, the one reader (part 1, the tool)

1. `tomlparser.c` records truncation. `TomlDoc` gains `int truncated`, set where
   an entry is dropped at `TOML_MAX_ENTRIES`:

   ```diff
    typedef struct {
    	TomlEntry entries[TOML_MAX_ENTRIES];
    	int       n;
   +	int       truncated; /* entries were dropped at TOML_MAX_ENTRIES */
    } TomlDoc;
   ```

   ```diff
   -		if (doc->n >= TOML_MAX_ENTRIES) continue;
   +		if (doc->n >= TOML_MAX_ENTRIES) { doc->truncated = 1; continue; }
   ```

   The inline-table path gets the same flag. dwm warns once per load:
   `dwm: <file> has more than 512 entries; the rest were ignored`.
2. New `lyona-toml.c`, built like `dwm-window-thumb` and linked with
   `tomlparser.o`:

   ```c
   /* lyona-toml: the one reader of Lyona's TOML files for scripts (Sync Sprint
    * 12 S12-14, D-20). It uses dwm's own parser, so a file means the same to a
    * script as to dwm.
    *
    *   lyona-toml dump FILE   one line per entry: section TAB index TAB key TAB value
    *                          (array items joined by US, 0x1f); tab, newline and
    *                          backslash in a value are written \t, \n and \\.
    *   lyona-toml get FILE SECTION KEY
    *                          the value alone; exit 1 when the key is absent
    *
    * Exit status: 0 read, 1 absent key, 2 usage, 3 unreadable or not parsed,
    * 4 truncated (the dump is still printed, then the status says so). */
   ```

   `main` parses with `toml_parse`. For `dump` it walks `doc.entries` in file
   order; for `get` it calls `toml_get`, the lookup dwm itself uses. The written
   code goes in this file when the step starts, about 90 lines.
3. `Makefile`:
   - `lyona-toml` joins `all`, with the same stale-input checks as `${THUMB}`;
   - `install-system` installs it to `${LIB_DIR}/lyona-toml`, mode 0755;
   - `uninstall` and `check-install-manifest` gain it.
4. Scripts find it through `$lyona_lib`: `lib/lyona` installed, and the
   checkout's built `lyona-toml` beside `scripts/`
   (`${lyona_lib%/scripts}/lyona-toml`). One helper in `dwm-paths.sh` does that:

   ```bash
   # The one TOML reader (S12-14): PREFIX/lib/lyona/lyona-toml installed, the
   # checkout's built one beside scripts/ otherwise.
   lyona_toml() {
   	local tool=$lyona_lib/lyona-toml
   	[[ -x $tool ]] || tool=${lyona_lib%/scripts}/lyona-toml
   	"$tool" "$@"
   }
   ```

5. **Test.** A new `tests/test-lyona-toml.sh` runs `tests/test-tomlparser.sh`'s
   fixtures through `dump`, and checks:
   - comments, same-line arrays and booleans, as S12-05 pinned them;
   - escaped output, and the exit codes;
   - a 600-entry file exits 4, and dwm logs the truncation warning.

**Implemented (2026-09-30, working tree, nothing committed).** Where it differs
from the text above:

- **Booleans keep their form.** The parser stored `true` and `false` as a
  `TOML_INT` of 1 and 0, so a dump would have printed `0` where
  `theme-apply.sh` compares `dark_mode` against `false`.
  - `TomlValue` gains `is_bool`, set in both boolean branches and cleared for
    every new entry, since entries are reused between loads.
  - dwm's own reads of the type are unchanged.
- **The tool links `util.o` too**: `tomlparser.c` uses `copystr`. The rule
  depends on `tomlparser.o`, `util.o` and both headers, and `install-system`
  refuses a stale build as it does for `dwm-window-thumb`.
- **The release archive** gets `lyona-toml` beside `scripts/`, the checkout
  layout, where step 4's scripts will look.
- **The format as built:**
  - numbers are written `%ld`, and floats `%.17g`, exactly as parsed;
  - array items are joined by US (0x1f);
  - backslash, tab, newline and carriage return are escaped in the section, the
    key and the value.

  `get` of a key that is absent from a truncated file exits 4, not 1, since the
  key may be among the dropped entries.
- **dwm's warning** comes from `toml_doc_ok`, so it covers the user file and
  the shipped default alike, on every load and reload.
- **`lyona_toml`**, in `dwm-paths.sh`, falls back to `$lyona_lib/../lyona-toml`
  rather than stripping `/scripts`, because a checkout's `lyona_lib` can be the
  relative `scripts`. It needs `lyona_lib`, and says so if the caller has none.
- **The live-install check** (`lyona-install-verify.sh`) verifies and backs up
  `PREFIX/lib/lyona/lyona-toml`, as it does `dwm`.
- **Tests:**
  - `tests/test-tomlparser.c` gains `truncation`: 522 plain entries keep 512 and
    set the flag; an inline-table array sets it too; the next parse clears it;
    `true` is `is_bool` and `1` is not. Mutation-checked: removing either site
    that sets the flag fails it.
  - New `tests/test-lyona-toml.sh` (`make check-lyona-toml`, in `make check`)
    covers:
    - the S12-05 grammar (a trailing comment, a boolean, a same-line array,
      an inline-table array);
    - the escaping, and exactly four fields per line;
    - `get`, and exit codes 1, 2, 3 and 4 (600 entries print 512 lines);
    - the three shipped files;
    - `lyona_toml` finding the tool installed and in a checkout.
  - `test-dwm-config-fallback.sh` starts dwm with a 557-entry user
    `themes.toml` and requires the warning line in its log.
- **Checks:** PASS: `check-install-manifest`, `release-check`,
  `check-dev-sync-install`, `check-install-preservation`, `check-shell`,
  `check-format`, `check-shell-contracts` and `check-lyona-update`.
  - `scripts/run-tests`: PASS, in one run.

### Step 4 -- the scripts use `lyona-toml` (part 1, the readers)

1. **Readers that switch:**
   - `theme-apply.sh`'s `toml_get` becomes `lyona_toml get`. Its 25 calls run
     one small C process each, where they ran one awk each.
   - `lyona-gtk-theme`'s `toml_get` does the same, and `theme_ids` becomes
     `lyona_toml dump | awk -F'\t' '$1 ~ /^theme\./ { sub(/^theme\./, "", $1); if (!seen[$1]++) print $1 }'`.
   - `dwm-quickshell-controlcenter`'s `active_theme` and `themes` switch the
     same way. That script is POSIX, so it has its own two-line lookup of the
     tool, as for the config directory in S12-13.
   - `dwm-settings-appearance`'s `parse_themes` builds its records from `dump`
     and keeps its own validation on top: size limits, the colour checks and
     error records. The Bash grammar goes.
2. **Not switched:**
   - **`dwm-settings-theme`'s three functions** rewrite the file keeping its
     layout, which a reader cannot do. Their check for a duplicate `[active]`
     stays in them, but it now also runs `dump` to confirm that dwm reads the
     result the same way: the edited file's `[active] theme` must be the target.
   - **The two `Makefile` awks** read only the shipped file, at install time,
     when the tool may not be built (`uninstall` needs no build). A test pins
     that their id list equals `lyona-toml dump`'s for `config/themes.toml`.
3. **Test.**
   - The existing tests of each script pass unchanged: the three
     `test-theme-apply-*.sh`,
     `test-lyona-gtk-theme.sh`, `test-quickshell-controlcenter.sh`,
     `test-dwm-settings-appearance.sh` and `test-dwm-settings-theme.sh`.
   - A new cross-reader test sends files the old readers disagree on (a
     comment after a value, `key="v"` without spaces, duplicate sections)
     through dwm's own `load_themes_toml` and every script, and requires the
     same active theme and colours. It fails against `main`.

**Implemented (2026-09-30, working tree, nothing committed).** Where it differs
from the text above:

- **Nine readers, not seven.** `lyona-plymouth-theme` and
  `lyona-console-theme` each carry a copy of the same awk reader. Neither was
  in the survey.
- **One load, not one process per value.** `theme-apply.sh` and
  `lyona-gtk-theme` would have run `lyona-toml get` about 25 times each. The
  new `lyona_toml_load` (in `dwm-paths.sh`) runs one `dump` into a map, and
  `lyona_toml_value` reads it:
  - the first plain entry of a key wins, as in dwm;
  - fields are split by parameter expansion, since `IFS` splitting would
    collapse an empty top-level section;
  - values are unescaped with `%b`, which is exact because the dump doubles
    every backslash.

  Each script loads once, in its own shell, since `toml_get` runs in
  `$(...)`.
- **`lyona-gtk-theme`'s output is byte-identical** to `main`'s for all 17
  generated themes. `theme_ids` now skips a `[theme.x]` header that holds no
  entries, which used to produce an empty theme.
- **The Control Center**'s `active_theme` and `themes` read through a POSIX
  `lyona_toml`. Its output matches `main`'s on the shipped file.
- **The appearance provider, decided with the user** (the plan's "the Bash
  grammar goes" did not hold: `parse_themes` is also the linter behind Settings'
  diagnostics, which the dump cannot express):
  - `parse_themes` stays, as the linter.
  - `apply_dwm_reading` then takes every value from `lyona-toml`, but only for
    a file dwm would apply: one whose `[active] theme` names a theme dwm also
    reads.
  - For such a file it lifts the grammar-only "invalid theme" marks, turns a
    grammar-only "unavailable" into "partial", and adds the themes the linter
    skipped after stopping early.
  - `validate_themes`' colour and completeness checks are unchanged. A file dwm
    would not apply (such as an unterminated array that swallows `[active]`)
    keeps the linter's verdict.
  - If `lyona-toml` cannot run, the linter's view stands.
- **Four `test-dwm-settings-appearance.sh` cases changed to the new contract**,
  each keeping its warning:
  - `[theme.dracula] trailing`, which dwm reads as `[theme.dracula]`;
  - an array closed on the line it opens, where the test assumed dwm's parser
    got stuck (S12-05 fixed that);
  - a 4095-byte line, where dwm splits it and reads on;
  - a duplicate `[theme.nord]`, where dwm keeps the first values.

  The split-duplicate case still ends in recovery, since the merged theme is
  incomplete.
- **`dwm-settings-theme`'s editor** now fails the edit if `lyona-toml get` of
  the edited file does not name the target. The test installed layouts for
  `test-dwm-settings-theme.sh` and `-appearance.sh` gained `lyona-toml`.
- **The readers that stay** are pinned in the new test, and their comments say
  why:
  - `lyona-plymouth-theme` and `lyona-console-theme` run only in
    `build-lyona-arch-iso.sh`, on the shipped file, where nothing builds
    `lyona-toml`;
  - the two `Makefile` awks read the shipped file at install time.
- **New `tests/test-theme-readers.sh`** (`make check-theme-readers`, in
  `make check`):
  - three `[active]` forms (no spaces, a trailing comment, a commented
    header) must give the Control Center, Settings and `theme-apply.sh`
    the active theme `lyona-toml` reads. It fails against `main`: "the
    control center read '', dwm reads 'dracula'";
  - the two generators' `toml_get` must return `lyona-toml`'s value for
    every plain entry of every shipped theme. Mutation-checked: without the
    quote-stripping `gsub`, the plymouth pin fails;
  - the Makefile's id list must equal the dump's.
- **Checks:** PASS: `check-theme-readers`, `check-lyona-toml`, `check-shell`,
  `check-format`, `check-shell-contracts` and `check-install-manifest`. The
  existing theme-apply, GTK, Control Center, theme and appearance tests pass.
- **Tests that stage their own helpers needed the tool too:**
  - `test-quickshell-controlcenter.sh`'s installed layout;
  - the fake checkouts of the health, large-surfaces, Settings,
    system-management and plain-text Xvfb tests, plus the watcher-lifetime and
    idle-watcher tests, which now put `lyona-toml` beside `scripts/`.
- **Found:** without the tool, two of the new readers fail quietly. The Control
  Center lists no themes, and the appearance provider keeps the linter's view;
  `theme-apply.sh` and `dwm-settings-theme` fail loudly. That is the same class
  as step 2's finding, a staged helper whose dependency is missing, and it goes
  to the same guard in S12-14's verification.
- **`scripts/run-tests`:** PASS, in one run.

### Step 5 -- one preview state machine for font and toolkit (part 2, shell)

1. New `scripts/dwm-preview.sh`, a Bash library in `INSTALL_LIBS`, holding the
   eleven functions. They move verbatim from `dwm-settings-toolkit` (the more
   general of the two), with three parameters the caller sets before sourcing:

   ```bash
   # The caller sets, before sourcing:
   #   preview_program   the name in messages: dwm-settings-font
   #   preview_env       the test-hook prefix: DWM_SETTINGS_FONT, which gives
   #                     ${preview_env}_NOW and ${preview_env}_BOOT_ID
   #   preview_subject   the label in messages: "font configuration"
   # and defines the domain hooks it calls:
   #   preview_capture   print the current configuration, for the rollback copy
   #   preview_apply     apply a configuration read from stdin
   #   preview_describe  print the configured_detail line for a state
   ```

   Every `DWM_SETTINGS_TOOLKIT_NOW` becomes `${preview_env}_NOW`, read with
   `${!name}`. Every literal "toolkit configuration" becomes
   `$preview_subject`, and every `dwm-settings-toolkit:` becomes
   `$preview_program:`.
2. `dwm-settings-font` and `dwm-settings-toolkit` keep only their domain code:
   - the font side: `meslo_alias`, `font_installed`,
     `default_font_available`, family and scale;
   - the toolkit side: the capability map and `config_body`;
   - on both: the hooks, the settings above, and one `source` line.
3. `dwm-settings-display`, `-input`, `-wallpaper` and `-theme` stay as they are.
   Their state machines differ, and forcing them into this library would change
   safety logic without a reason. The CHANGELOG says which two share it.
4. **Test.**
   - The existing `test-dwm-settings-font.sh` and `test-dwm-settings-toolkit.sh`
     pass unchanged; they cover expiry, locks, tokens and the atomic exchange.
   - `test-shell-contracts.sh` gains a check that none of the eleven functions
     is defined outside `dwm-preview.sh`.

**Implemented (2026-09-30, working tree, nothing committed).** Where it differs
from the text above:

- **37 functions, not eleven.** The two helpers share 50 function names.
  - **Moved:** the 23 byte-identical ones (all but `die`, which each helper
    needs before it sources anything), and the 14 that differ only in the word
    "font" or "toolkit", the config file's name and the test-hook prefix.
  - **Stayed, as domain code:**
    - `start_preview` and `finish_preview`: toolkit re-reads its config, runs
      `theme-apply`, and releases the icon baseline;
    - `mutation_ready`: font also checks for `fc-match`;
    - the models: `read_config`, `write_config`, `write_meta`,
      `selection_hash`, `apply_selection`, `reset_selection`, `emit_status`,
      `validate_selection` and `usage`.
- **Four parameters**, set before sourcing: `preview_program`,
  `preview_label`, `preview_config_name` and `preview_env`. The plan's three
  hooks (`preview_capture`, `preview_apply`, `preview_describe`) were not
  needed: the moved functions already call each helper's own `read_config`,
  `write_config` and the rest by name.
- **How the text was moved:**
  - it was extracted by a script from `dwm-settings-toolkit` and
    parameterised by an explicit list of 18 line replacements;
  - single-quoted messages became double-quoted to take `$preview_label`;
  - the two test hooks are read by name (`${!now_var}`).

  Instantiating the library with each helper's values and diffing it against
  that helper's originals shows only quoting and equivalent `printf`
  arguments: the same 24 line pairs for each, with identical output text.
- **Found: the toolkit test never exercised expiry or token validation.**
  Mutation checks in a scratch copy:
  - with `expire_preview_locked` returning at once, the font test failed and
    the toolkit test passed;
  - with `valid_token` accepting anything, both passed.

  `test-dwm-settings-toolkit.sh` gains an "expiry and tokens" case, driving the
  shared code through its own `DWM_SETTINGS_TOOLKIT_NOW`:
  - a keep after a 5 s deadline is refused ("toolkit preview has expired") and
    the config is rolled back;
  - a `../escape` token is refused;
  - a 97-character token, a safe file name that only `valid_token` refuses, is
    refused.

  Both mutations now fail it.
- **Contract test:** neither helper may define a function `dwm-preview.sh`
  holds, and both must source it. Mutation-checked with a stray
  `clear_preview` in `dwm-settings-font`.
- **No comment was stranded:** none of the moved functions had one above it.
- **`test-quickshell-settings-xvfb.sh`'s fake checkout** needed `dwm-preview.sh`.
  Without it, the Settings font page reported font changes as unavailable, and
  the test failed on that ("Font mutation readiness did not become available").
  That is the third time in this item that a staged helper went without a
  library it sources. The guard noted in step 2 now has three instances.
- **Checks:** PASS: `check-shell`, `check-format`, `check-install-manifest`,
  `check-dev-sync-install` and `check-shell-contracts`. `scripts/run-tests`:
  PASS, in one run.

### Step 6 -- the preview countdown in QML (part 2, QML)

It starts with a survey, since the review's premise did not hold (see "What
exists today"). If two or more surfaces run the same countdown, it goes into one
`core/PreviewSession.qml`, with these properties and signals:
- `token`, `deadline` and `remaining`;
- `start(token, seconds)`, `keep()` and `revert()`;
- `expired()`.

If only `AppearanceModel` does, this step records that and changes nothing.

### Step 7 -- resident watchers on `WatchedProcess` (part 4)

1. `WatchedProcess.qml` gains what the line-parsing watchers need:

   ```diff
   +    /* Emitted for each line the helper writes, before the settle timer
   +     * restarts. A watcher that parses its lines connects here instead of
   +     * owning its own Process (Sync Sprint 12 S12-14). */
   +    signal line(string text)
   ```

   ```diff
            stdout: SplitParser {
   -            onRead: settleTimer.restart()
   +            onRead: data => {
   +                root.line(data);
   +                settleTimer.restart();
   +            }
            }
   ```

   Setting `settleInterval: 0` means "no settle", for watchers that act on
   every line.
2. **Moved to it:** the watchers whose restart rule is "while the surface is
   active": `NetworkModel`, `ControlsModel` (audio and media), `BluetoothModel`,
   `PicomModel`, `AppearanceModel`'s inventory watch, and `SettingsModel`'s
   three.
3. **Not moved:**
   - `DwmState` is always on and restarts on its own terms;
   - the system-management pair is started per operation, not supervised.

   Each gets a comment saying why.
4. **Test.**
   - A QML check in `tests/qml` feeds a `WatchedProcess` three lines and checks
     three `line` signals and one `settled`.
   - `check-quickshell-watcher-lifetime-xvfb` and the idle-watcher test must
     pass, since they measure exactly these processes. A real or nested X11
     session is required before the runtime is called verified (AGENTS.md).

## Verification (whole item)

- `rg` finds no `themes.toml` grammar outside `tomlparser.c`,
  `dwm-settings-theme`'s editors and the pinned `Makefile` awks.
- No trust-check function is defined outside `dwm-trust.sh` and the root
  helpers' pinned copies.
- None of the eleven preview functions is defined outside `dwm-preview.sh`.
- No script outside `dwm-xdg.sh` computes an XDG directory, except the three
  named wrappers.
- The full suite passes. The watcher change is validated in a nested X11
  session, including the idle CPU check AGENTS.md asks for.
