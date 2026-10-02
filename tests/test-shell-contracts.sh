#!/bin/sh
# Cross-script invariants for the shell helpers: the ones that are shared, and
# the ones that must not drift back apart.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace

# ── Atomic replacement ───────────────────────────────────────────────────
#
# Plain `mv -f src dst` moves *into* dst when dst has become a directory,
# leaving the real target untouched and the caller none the wiser. Every
# replace-a-file-in-place site must say -T (or --no-target-directory), which is
# what makes mv refuse rather than descend.
unsafe=$work/unsafe-mv
grep -rn 'mv -f ' "$repo/scripts" "$repo/install.sh" 2>/dev/null |
	grep -v -- '--no-target-directory' >"$unsafe" || true
if [ -s "$unsafe" ]; then
	printf '%s: these sites replace a file with a bare mv -f:\n' "$test_name" >&2
	sed 's/^/  /' "$unsafe" >&2
	printf 'Use mv -fT so mv refuses when the destination is a directory.\n' >&2
	exit 1
fi

# The guard is only meaningful while such sites still exist.
safe=$work/safe-mv
grep -rn 'mv -fT \|mv -f --no-target-directory' "$repo/scripts" >"$safe" || true
[ "$(wc -l <"$safe")" -ge 20 ] ||
	fail "expected the atomic-replace idiom across scripts/, found $(wc -l <"$safe") sites"

# ── The behaviour that flag buys ─────────────────────────────────────────
#
# Asserted against real mv rather than assumed, since the whole point is what
# the tool does when the destination is a directory.
printf 'payload\n' >"$work/source"
mkdir -p "$work/destination"
if mv -fT "$work/source" "$work/destination" 2>/dev/null; then
	fail 'mv -fT overwrote a directory destination'
fi
assert_file "$work/source" 'mv -fT left the source in place'
assert_no_file "$work/destination/source" 'mv -fT did not move into the directory'

# And that the bare form really does descend, so the guard above is not
# protecting against an imaginary failure.
mv -f "$work/source" "$work/destination"
assert_file "$work/destination/source" 'bare mv -f moves into a directory'

# ── Sourced helpers travel with their callers ────────────────────────────
#
# A helper is looked up in $lyona_lib (beside the caller in a checkout,
# PREFIX/lib/lyona once installed; Sync Sprint 12 S12-13), so a script that
# sources one and is installed without it does not run at all -- it fails at
# load, before any argument handling. Anything installed onto PATH must bring
# its helpers, and they must be installed as libraries, not as commands.
make_list() {
	make -s -C "$repo" --no-print-directory \
		--eval="test-print-list: ; @printf '%s\\n' \$($1)" test-print-list
}
installed=$work/installed
libraries=$work/libraries
make_list INSTALL_COMMANDS >"$installed"
make_list INSTALL_LIBS >"$libraries"
[ -s "$installed" ] || fail 'could not read INSTALL_COMMANDS from the Makefile'
[ -s "$libraries" ] || fail 'could not read INSTALL_LIBS from the Makefile'

for script in "$repo"/scripts/*; do
	[ -f "$script" ] || continue
	name=scripts/$(basename "$script")
	grep -Fqx "$name" "$installed" || continue
	# shellcheck disable=SC2016 # the $ is literal source text, not an expansion
	sed -n -E 's#^[[:space:]]*(\.|source) "\$lyona_lib/([A-Za-z0-9_.-]*)".*#\2#p' "$script" |
		while IFS= read -r helper; do
			[ -n "$helper" ] || continue
			[ -f "$repo/scripts/$helper" ] ||
				fail "$name sources scripts/$helper, which does not exist"
			grep -Fqx "scripts/$helper" "$libraries" ||
				fail "$name is installed but scripts/$helper is not in INSTALL_LIBS; it would fail at load"
		done
	# The old form looked beside $0, which an install no longer satisfies.
	# shellcheck disable=SC2016 # the $ is literal source text, not an expansion
	if grep -Eq '^[[:space:]]*(\.|source) "\$(script_dir|SCRIPT_DIR)/[A-Za-z0-9_.-]+\.sh"' "$script"; then
		fail "$name sources a helper beside itself; use \$lyona_lib"
	fi
done
while IFS= read -r library; do
	! grep -Fqx "$library" "$installed" ||
		fail "$library is in both INSTALL_COMMANDS and INSTALL_LIBS"
done <"$libraries"

# Vacuity check: at least one script really does source a helper this way.
# shellcheck disable=SC2016 # the $ is literal source text, not an expansion
sourcing=$(grep -El '^[[:space:]]*(\.|source) "\$lyona_lib/' "$repo"/scripts/* 2>/dev/null | wc -l)
[ "$sourcing" -ge 1 ] ||
	fail 'no script sources a helper through lyona_lib; the check above proves nothing'

# ── Path safety is defined once ──────────────────────────────────────────
#
# These had drifted into a gradient like the mv one. dwm-settings-font's
# valid_absolute_path accepted tabs and ../ traversal while validating HOME
# and the XDG directories; the other two copies rejected both for the same
# class of input. The shared helper is the strict form.
for helper in valid_absolute_path path_has_no_symlink_components \
	existing_path_chain_is_safe directory_path_ready ensure_owned_directory; do
	assert_contains "$repo/scripts/dwm-paths.sh" "$helper() {"
	duplicate=$(grep -l "^$helper() {" "$repo"/scripts/* 2>/dev/null |
		grep -v 'dwm-paths.sh' || true)
	if [ -n "$duplicate" ]; then
		printf '%s: %s is defined outside dwm-paths.sh:\n' "$test_name" "$helper" >&2
		printf '%s\n' "$duplicate" | sed 's/^/  /' >&2
		exit 1
	fi
done

# And the strictness is real, not just written down: run the shipped script
# against a traversal path and require it to refuse.
probe_home=$work/probe/home
mkdir -p "$probe_home/.config" "$probe_home/.local/state"
if HOME=$probe_home XDG_CONFIG_HOME=$probe_home/.config \
	XDG_STATE_HOME=$probe_home/../home/.local/state \
	"$repo/scripts/dwm-settings-font" status >/dev/null 2>&1; then
	fail 'dwm-settings-font accepted an XDG path with a traversal component'
fi
HOME=$probe_home XDG_CONFIG_HOME=$probe_home/.config \
	XDG_STATE_HOME=$probe_home/.local/state \
	"$repo/scripts/dwm-settings-font" status >/dev/null 2>&1 ||
	fail 'dwm-settings-font rejected clean XDG paths'

# ── The udev watcher is defined once ─────────────────────────────────────
for helper in simple_watch_process_starttime simple_watch_identity_is_live \
	simple_watch_capture_child simple_watch_cleanup simple_watch_events; do
	assert_contains "$repo/scripts/dwm-simple-watch.sh" "$helper() {"
	duplicate=$(grep -l "^$helper() {" "$repo"/scripts/* 2>/dev/null |
		grep -v 'dwm-simple-watch.sh' || true)
	if [ -n "$duplicate" ]; then
		printf '%s: %s is defined outside dwm-simple-watch.sh:\n' "$test_name" "$helper" >&2
		printf '%s\n' "$duplicate" | sed 's/^/  /' >&2
		exit 1
	fi
done
# The subsystem is the parameter that made one watcher serve both.
assert_contains "$repo/scripts/dwm-settings-display" 'simple_watch_events drm display'
assert_contains "$repo/scripts/dwm-settings-input" 'simple_watch_events input input'

# ── XDG directories come from one place ──────────────────────────────────
#
# Sync Sprint 12 S12-14: dwm-xdg.sh holds the rule (an absolute value, else the
# fallback under HOME). The exceptions each say why: dwm-system-health's deny
# list must never fail, lyona-install-verify.sh falls back under USER_HOME and
# refuses relative values, and three one-variable wrappers stay inline.
xdg_inline=$(grep -nE '\$\{XDG_(CONFIG|DATA|STATE|CACHE)_HOME:[-+]|case \$\{XDG_(CONFIG|DATA|STATE|CACHE)_HOME' \
	"$repo"/scripts/* 2>/dev/null |
	grep -vE '^[^:]*/scripts/(dwm-xdg\.sh|dwm-system-health|lyona-install-verify\.sh|dwm-controlcenter|dwm-keybinds|dwm-settings):' || true)
if [ -n "$xdg_inline" ]; then
	printf '%s: XDG directories computed outside dwm-xdg.sh:\n%s\n' "$test_name" "$xdg_inline" >&2
	exit 1
fi
# shellcheck disable=SC2016 # expanded by the inner shell
xdg_result=$(env -i HOME=/h XDG_CONFIG_HOME=relative XDG_DATA_HOME=/d /bin/sh -c \
	'. "$1"; lyona_xdg_dirs; printf "%s %s %s %s" "$config_home" "$data_home" "$state_home" "$cache_home"' \
	sh "$repo/scripts/dwm-xdg.sh")
[ "$xdg_result" = '/h/.config /d /h/.local/state /h/.cache' ] ||
	fail "lyona_xdg_dirs gave '$xdg_result'; a relative value must fall back"
# shellcheck disable=SC2016 # expanded by the inner shell
xdg_result=$(env -i /bin/sh -c '. "$1"; lyona_xdg_dirs lenient; printf "[%s]" "$config_home"' \
	sh "$repo/scripts/dwm-xdg.sh")
[ "$xdg_result" = '[]' ] || fail "lyona_xdg_dirs lenient without HOME gave $xdg_result"
# shellcheck disable=SC2016 # expanded by the inner shell
if env -i /bin/sh -c '. "$1"; lyona_xdg_dirs; exit 0' sh "$repo/scripts/dwm-xdg.sh" 2>/dev/null; then
	fail 'lyona_xdg_dirs without HOME did not fail'
fi

# ── The trust checks are defined once ────────────────────────────────────
#
# Sync Sprint 12 S12-14 (D-21): dwm-trust.sh holds trusted_parent_chain and
# trusted_file. The two root helpers source nothing at run time, so each keeps a
# verbatim copy between its BEGIN and END markers, which must equal the
# library's functions exactly.
trust_lib=$repo/scripts/dwm-trust.sh
sed -n "/^# Every directory from PATH's parent up to/,\$p" "$trust_lib" >"$work/trust-lib"
[ -s "$work/trust-lib" ] || fail 'could not read the functions from dwm-trust.sh'
for root_helper in lyona-update-root dwm-settings-display-root dwm-system-health-root; do
	sed -n '/^# BEGIN dwm-trust.sh/,/^# END dwm-trust.sh$/p' "$repo/scripts/$root_helper" |
		sed '1,/^# tests\/test-shell-contracts.sh fails if this copy differs/d; $d' >"$work/trust-copy"
	cmp -s "$work/trust-lib" "$work/trust-copy" || {
		printf '%s: %s trust checks differ from dwm-trust.sh:\n' "$test_name" "$root_helper" >&2
		diff "$work/trust-lib" "$work/trust-copy" >&2 || true
		exit 1
	}
done
for helper in trusted_parent_chain trusted_file; do
	duplicate=$(grep -l "^$helper() {" "$repo"/scripts/* 2>/dev/null |
		grep -vE '/(dwm-trust\.sh|lyona-update-root|dwm-settings-display-root|dwm-system-health-root)$' || true)
	if [ -n "$duplicate" ]; then
		printf '%s: %s is defined outside dwm-trust.sh:\n%s\n' "$test_name" "$helper" "$duplicate" >&2
		exit 1
	fi
done

# ── One preview state machine for font and toolkit ───────────────────────
#
# Sync Sprint 12 S12-14: dwm-preview.sh holds the lock, token, watchdog, expiry
# and atomic-exchange machinery the two helpers share; neither may define its
# own copy. (Other helpers have different machines, some with the same names.)
grep -oE '^[a-z_]+\(\) \{' "$repo/scripts/dwm-preview.sh" | sed 's/() {$//' >"$work/preview-functions"
[ "$(wc -l <"$work/preview-functions")" -ge 30 ] || fail 'could not read dwm-preview.sh functions'
for preview_helper in dwm-settings-font dwm-settings-toolkit; do
	while IFS= read -r preview_function; do
		! grep -q "^$preview_function() {" "$repo/scripts/$preview_helper" ||
			fail "$preview_helper defines $preview_function, which dwm-preview.sh holds"
	done <"$work/preview-functions"
	# shellcheck disable=SC2016 # the $ is literal source text, not an expansion
	grep -Fq '. "$lyona_lib/dwm-preview.sh"' "$repo/scripts/$preview_helper" ||
		fail "$preview_helper does not source dwm-preview.sh"
done

# Sync Sprint 12 S12-16: the product shell's settings IPC target has only the
# commands dwm-settings and the command menu use. The tests' getters and
# drivers are on settingsTest, which shell.qml creates only under
# LYONA_SHELL_TEST_IPC=1.
shell_qml=$repo/config/quickshell/shell.qml
settings_functions=$(awk '
	/^    IpcHandler \{$/ { handler = 1; target = ""; next }
	handler && /^        target: / { target = $2 }
	handler && target == "\"settings\"" && /^        function / {
		sub(/^        function /, ""); sub(/\(.*/, ""); print
	}
	/^    }$/ { handler = 0 }
' "$shell_qml" | LC_ALL=C sort | tr '\n' ' ')
[ "$settings_functions" = "close open refresh select status toggle " ] ||
	fail "the settings IPC target has: $settings_functions(only the six product commands belong there)"
case_line=$(grep -E '^open \| close \| toggle \| refresh \| status\) ;;$' "$repo/scripts/dwm-settings" || true)
[ -n "$case_line" ] || fail 'dwm-settings accepts commands other than open, close, toggle, refresh and status'
menu_actions=$(grep -oE '"target": "settings", "action": "[a-z]+"' \
	"$repo/config/quickshell/launcher/CommandMenuCatalog.js" | sed 's/.*"action": "//; s/"$//' | LC_ALL=C sort -u | tr '\n' ' ')
[ "$menu_actions" = "open select " ] ||
	fail "the command menu calls settings actions: $menu_actions"
grep -Fq 'active: Quickshell.env("LYONA_SHELL_TEST_IPC") === "1"' "$shell_qml" ||
	fail 'shell.qml does not gate SettingsTestIpc on LYONA_SHELL_TEST_IPC'
grep -Fqx '        target: "settingsTest"' "$repo/config/quickshell/settings/SettingsTestIpc.qml" ||
	fail 'SettingsTestIpc.qml is not the settingsTest target'
! grep -rn 'LYONA_SHELL_TEST_IPC' "$repo/scripts" "$repo/config" "$repo/install.sh" "$repo/archiso" 2>/dev/null |
	grep -v 'config/quickshell/shell.qml' | grep -v 'config/quickshell/settings/SettingsTestIpc.qml' | grep -q . ||
	fail 'something outside the shell and the tests sets or reads LYONA_SHELL_TEST_IPC'

# Sync Sprint 12 S12-17: a document the code or the user-facing docs cite must
# exist, or, once retired, be cited as a `git show` argument naming a commit
# that holds it: <commit>:docs/<name>.md (docs/UPSTREAM-SYNC.md, "Retired plan
# documents"). The commit form is checked only in a git checkout.
in_git=0
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 && in_git=1
doc_refs=$(cd "$repo" && grep -rhoE '([0-9a-f]{7,40}:)?docs/[A-Za-z0-9_./-]+\.md' \
	scripts config tests archiso install.sh Makefile README.md SPEC.md AGENTS.md \
	CONTRIBUTING.md SECURITY.md docs/src docs/RELEASING.md 2>/dev/null | sort -u)
printf '%s\n' "$doc_refs" >"$work/doc-refs"
while IFS= read -r reference; do
	[ -n "$reference" ] || continue
	case $reference in
	*:docs/*)
		[ "$in_git" = 0 ] || git -C "$repo" cat-file -e "$reference" 2>/dev/null ||
			fail "$reference: that commit does not hold that document"
		;;
	*)
		[ -e "$repo/$reference" ] ||
			fail "$reference is cited but does not exist; cite a retired one as <commit>:$reference"
		;;
	esac
done <"$work/doc-refs"

printf '%s\n' 'Shell contracts: PASS'
