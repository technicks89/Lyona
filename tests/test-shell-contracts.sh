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
# A helper is looked up beside $0, so a script that sources one and is
# installed without it does not run at all -- it fails at load, before any
# argument handling. Anything installed onto PATH must bring its helpers.
installed=$work/installed
sed -n '/^INSTALL_COMMANDS = /,/^$/p' "$repo/Makefile" |
	tr -d '\134' | tr ' \t' '\n' | grep '^scripts/' >"$installed" || true
[ -s "$installed" ] || fail 'could not read INSTALL_COMMANDS from the Makefile'

for script in "$repo"/scripts/*; do
	[ -f "$script" ] || continue
	name=scripts/$(basename "$script")
	grep -Fqx "$name" "$installed" || continue
	# shellcheck disable=SC2016 # the $ is literal source text, not an expansion
	sed -n 's|^\. "\$script_dir/\([A-Za-z0-9_.-]*\)".*|\1|p' "$script" |
		while IFS= read -r helper; do
			[ -n "$helper" ] || continue
			[ -f "$repo/scripts/$helper" ] ||
				fail "$name sources scripts/$helper, which does not exist"
			grep -Fqx "scripts/$helper" "$installed" ||
				fail "$name is installed but scripts/$helper is not; it would fail at load"
		done
done

# Vacuity check: at least one script really does source a helper this way.
# shellcheck disable=SC2016 # the $ is literal source text, not an expansion
sourcing=$(grep -l '^\. "\$script_dir/' "$repo"/scripts/* 2>/dev/null | wc -l)
[ "$sourcing" -ge 1 ] ||
	fail 'no script sources a sibling helper; the check above proves nothing'

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

printf '%s\n' 'Shell contracts: PASS'
