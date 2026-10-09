# shellcheck shell=sh
#
# Shared helpers for the tests in this directory.
#
# Source it as the first thing a test does, before `set -eu`:
#
#     . "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
#
# which leaves $tests_dir and $repo set. Every test here is executed rather
# than sourced, so "$0" is the script's own path under both sh and bash, and
# one bootstrap line covers both shebangs.
#
# Everything below is POSIX shell: most of the tests are #!/bin/sh.

# shellcheck disable=SC2034 # these three are the library's output, read by callers
tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 1
repo=$(CDPATH='' cd -- "$tests_dir/.." && pwd) || exit 1
test_name=${0##*/}

# Workspaces go under ${DWM_TEST_TMP_ROOT:-$HOME/tmp} (AGENTS.md), including for a
# test run on its own (a plain `make check-...`), not only under scripts/run-tests,
# which points TMPDIR at its per-run workspace. Without this, mktemp uses /tmp.
if [ -z "${TMPDIR:-}" ]; then
	TMPDIR=${DWM_TEST_TMP_ROOT:-${HOME:-}/tmp}
	mkdir -p -- "$TMPDIR" || exit 1
	export TMPDIR
fi

# The HOME this test was started with, which kill_session_tree never touches.
lyona_real_home=${HOME:-}

# ── Session teardown ─────────────────────────────────────────────────────
#
# kill_session_tree HOME: stop every process whose environment has exactly this
# HOME. An Xvfb test gives its session a HOME of its own, so this reaches what
# stopping dwm and Quickshell does not: what dwm's autostart detached (setsid),
# what a killed Quickshell orphaned, and the D-Bus services started for it.
# TERM first, KILL whatever is left after 2 s. Refuses the test's own HOME, / and
# an empty path.

kill_session_tree_pids() {
	grep -Flxz -- "HOME=$1" /proc/[0-9]*/environ 2>/dev/null |
		sed -n 's#^/proc/\([0-9][0-9]*\)/environ$#\1#p' | grep -vx -- "$$"
}

kill_session_tree() {
	kst_home=$1
	case $kst_home in '' | / | "$lyona_real_home") return 0 ;; esac
	kst_pids=$(kill_session_tree_pids "$kst_home") || return 0
	# shellcheck disable=SC2086 # one pid per word
	kill -TERM $kst_pids 2>/dev/null
	kst_try=0
	while [ "$kst_try" -lt 20 ]; do
		kst_pids=$(kill_session_tree_pids "$kst_home") || return 0
		sleep 0.1
		kst_try=$((kst_try + 1))
	done
	# shellcheck disable=SC2086 # one pid per word
	kill -KILL $kst_pids 2>/dev/null
	return 0
}

# ── Failure reporting ────────────────────────────────────────────────────
#
# The dominant style in these tests is a bare `grep` under `set -e`, which
# reports a non-zero exit and nothing about what was being checked. Every
# assertion here says what it wanted and what it found instead.

fail() {
	printf '%s: %s\n' "$test_name" "$*" >&2
	exit 1
}

# Up to 20 lines of a file, labelled, for a failure message.
lyona_show_file() {
	if [ ! -e "$1" ]; then
		printf '  (%s does not exist)\n' "$1" >&2
		return
	fi
	printf '  %s contains:\n' "$1" >&2
	sed -n '1,20p' -- "$1" | sed 's/^/    /' >&2
	if [ "$(wc -l <"$1")" -gt 20 ]; then
		printf '    ... (truncated)\n' >&2
	fi
}

assert_file() {
	[ -f "$1" ] || fail "expected a file at $1${2:+ ($2)}"
}

assert_no_file() {
	[ ! -e "$1" ] || fail "expected nothing at $1${2:+ ($2)}"
}

assert_dir() {
	[ -d "$1" ] || fail "expected a directory at $1${2:+ ($2)}"
}

assert_executable() {
	[ -x "$1" ] || fail "expected $1 to be executable${2:+ ($2)}"
}

# Fixed-string containment.
assert_contains() {
	assert_file "$1"
	grep -Fq -- "$2" "$1" && return 0
	printf '%s: %s does not contain %s\n' "$test_name" "$1" "$2" >&2
	lyona_show_file "$1"
	exit 1
}

assert_not_contains() {
	assert_file "$1"
	grep -Fq -- "$2" "$1" || return 0
	printf '%s: %s unexpectedly contains %s\n' "$test_name" "$1" "$2" >&2
	lyona_show_file "$1"
	exit 1
}

# A whole line, matched exactly.
assert_line() {
	assert_file "$1"
	grep -Fqx -- "$2" "$1" && return 0
	printf '%s: %s has no line reading exactly %s\n' "$test_name" "$1" "$2" >&2
	lyona_show_file "$1"
	exit 1
}

assert_no_line() {
	assert_file "$1"
	grep -Fqx -- "$2" "$1" || return 0
	printf '%s: %s unexpectedly has a line reading exactly %s\n' \
		"$test_name" "$1" "$2" >&2
	lyona_show_file "$1"
	exit 1
}

# Extended regular expression.
assert_matches() {
	assert_file "$1"
	grep -Eq -- "$2" "$1" && return 0
	printf '%s: %s does not match %s\n' "$test_name" "$1" "$2" >&2
	lyona_show_file "$1"
	exit 1
}

assert_equals() {
	[ "$1" = "$2" ] && return 0
	printf '%s: %s\n  expected: %s\n  actual:   %s\n' \
		"$test_name" "${3:-values differ}" "$1" "$2" >&2
	exit 1
}

# For values already in variables rather than in a file.
assert_string_contains() {
	case $1 in
	*"$2"*) return 0 ;;
	esac
	printf '%s: %s\n  expected to contain: %s\n  actual: %s\n' \
		"$test_name" "${3:-string does not contain the expected text}" "$2" "$1" >&2
	exit 1
}

# ── Cleanup composition ──────────────────────────────────────────────────
#
# A single EXIT trap that runs registered actions last-registered-first, so a
# workspace registered before a background process is removed after that
# process has been killed. Tests that layer extra teardown -- killing PIDs,
# dumping a log on failure -- add to the stack instead of replacing the trap.

lyona_cleanup_stack=

cleanup_add() {
	lyona_cleanup_stack="$*
$lyona_cleanup_stack"
}

lyona_run_cleanup() {
	lyona_cleanup_status=$?
	set +e
	printf '%s\n' "$lyona_cleanup_stack" | while IFS= read -r lyona_cleanup_action; do
		[ -n "$lyona_cleanup_action" ] || continue
		eval "$lyona_cleanup_action"
	done
	return "$lyona_cleanup_status"
}

# Cleanup runs on EXIT. The signal traps exist so a killed test still reaches
# it: a shell terminated by an uncaught signal does not run its EXIT trap, and
# 14 of the tests were carrying `EXIT HUP INT TERM` by hand for exactly that.
# Exiting with the conventional 128+signal keeps the caller's view intact.
trap lyona_run_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Creates $work and arranges for it to be removed. $work/bin exists but is not
# put on PATH: tests scope stubs to individual invocations.
make_workspace() {
	work=$(mktemp -d) || fail 'could not create a temporary workspace'
	cleanup_add "rm -rf -- '$work'"
	mkdir -p "$work/bin" || fail "could not create $work/bin"
}

# ── PATH stubs ───────────────────────────────────────────────────────────

# Reads the stub body from stdin:
#
#     stub_command feh <<'SH'
#     #!/bin/sh
#     printf 'feh %s\n' "$*" >>"$log"
#     SH
stub_command() {
	[ -n "${work:-}" ] || fail 'stub_command needs a workspace; call make_workspace first'
	mkdir -p "$work/bin"
	cat >"$work/bin/$1" || fail "could not write the $1 stub"
	chmod +x "$work/bin/$1"
}

# The common case: a stub that records its own invocation and does nothing
# else. Needs $DWM_TEST_LOG set when the stub runs.
stub_logging_command() {
	stub_command "$1" <<'SH'
#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >>"$DWM_TEST_LOG"
SH
}

# ── Staging helpers into a test's own layout ─────────────────────────────
#
# stage_helpers LAYOUT DEST HELPER...: copy each helper from scripts/, and what
# it needs to load, into a layout a test runs it from (Sync Sprint 12 S12-21).
# Before this, each test listed the libraries by hand, and a helper that gained
# one failed at load in every test whose list went stale, often silently.
#
#   checkout  DEST is a fake checkout's scripts/: helpers and libraries go in
#             it, lyona-toml beside it (DEST/..), as in a real checkout.
#   prefix    DEST is a PREFIX: helpers go to bin/, libraries and lyona-toml to
#             lib/lyona/, the Python package to lib/lyona/python/.
#
# A file's libraries are the ones it sources through $lyona_lib, plus the one it
# tests for (`-f $lyona_lib/X`) to find that directory, followed recursively
# because libraries source libraries. lyona-toml is staged when a staged file
# uses it, and the system-management package when a staged file imports it.
# Then a load check: every $lyona_lib reference in every staged file must
# resolve, and every staged shell file must parse. It is static, so it runs
# nothing a helper would do on load. A failure names the helper and the file.
stage_helpers() {
	sh_layout=$1
	sh_dest=$2
	shift 2
	case $sh_layout in
	checkout)
		sh_bin=$sh_dest
		sh_lib=$sh_dest
		sh_tool_dir=$sh_dest/..
		sh_python_dir=$sh_dest
		;;
	prefix)
		sh_bin=$sh_dest/bin
		sh_lib=$sh_dest/lib/lyona
		sh_tool_dir=$sh_lib
		sh_python_dir=$sh_lib/python
		;;
	*) fail "stage_helpers: unknown layout '$sh_layout' (checkout or prefix)" ;;
	esac
	mkdir -p "$sh_bin" "$sh_lib" || fail "stage_helpers: cannot create $sh_dest"
	# One path per line, preserving spaces and backslashes in destinations.
	sh_pending=
	for sh_helper in "$@"; do
		[ -f "$repo/scripts/$sh_helper" ] || fail "stage_helpers: scripts/$sh_helper does not exist"
		cp -p "$repo/scripts/$sh_helper" "$sh_bin/$sh_helper" ||
			fail "stage_helpers: cannot copy $sh_helper"
		sh_pending="${sh_pending:+$sh_pending
}$sh_bin/$sh_helper"
	done
	sh_staged=$sh_pending
	sh_needs_tool=0
	sh_needs_python=0
	while [ -n "$sh_pending" ]; do
		sh_next=
		while IFS= read -r sh_file; do
			grep -Eq 'lyona_toml|lyona-toml' "$sh_file" && sh_needs_tool=1
			grep -q 'lyona_system_management' "$sh_file" && sh_needs_python=1
			for sh_library in $(stage_helper_libraries "$sh_file"); do
				[ -e "$sh_lib/$sh_library" ] && continue
				[ -f "$repo/scripts/$sh_library" ] ||
					fail "stage_helpers: ${sh_file##*/} needs scripts/$sh_library, which does not exist"
				cp -p "$repo/scripts/$sh_library" "$sh_lib/$sh_library" ||
					fail "stage_helpers: cannot copy $sh_library"
				sh_next="${sh_next:+$sh_next
}$sh_lib/$sh_library"
				sh_staged="$sh_staged
$sh_lib/$sh_library"
			done
		done <<EOF
$sh_pending
EOF
		sh_pending=$sh_next
	done
	if [ "$sh_needs_tool" = 1 ]; then
		[ -x "$repo/lyona-toml" ] ||
			fail 'stage_helpers: a staged helper uses lyona-toml, which is not built (run make all)'
		cp -p "$repo/lyona-toml" "$sh_tool_dir/lyona-toml" || fail 'stage_helpers: cannot copy lyona-toml'
	fi
	if [ "$sh_needs_python" = 1 ]; then
		if ! mkdir -p "$sh_python_dir/lyona_system_management" ||
			! cp -p "$repo/scripts/lyona_system_management/"*.py "$sh_python_dir/lyona_system_management/"; then
			fail 'stage_helpers: cannot copy the lyona_system_management package'
		fi
	fi
	# The load check.
	while IFS= read -r sh_file; do
		[ -n "$sh_file" ] || continue
		for sh_library in $(stage_helper_libraries "$sh_file"); do
			[ -f "$sh_lib/$sh_library" ] ||
				fail "stage_helpers: ${sh_file##*/} would not load: $sh_lib/$sh_library is missing"
		done
		case $(head -n 1 -- "$sh_file") in
		*bash*) bash -n "$sh_file" || fail "stage_helpers: ${sh_file##*/} does not parse" ;;
		'#!'*/sh | '#!'*/sh' '* | '# shellcheck shell=sh'*) sh -n "$sh_file" || fail "stage_helpers: ${sh_file##*/} does not parse" ;;
		esac
	done <<EOF
$sh_staged
EOF
}

# The libraries FILE reaches through $lyona_lib: sourced, run (dwm-aur.sh,
# #281), or tested for as the marker of that directory. One name per line.
stage_helper_libraries() {
	# shellcheck disable=SC2016 # the $ is literal source text, not an expansion
	grep -oE '\$lyona_lib/[A-Za-z0-9_.-]+' "$1" | sed 's#^\$lyona_lib/##' |
		grep -vx 'lyona-toml' | LC_ALL=C sort -u
}
