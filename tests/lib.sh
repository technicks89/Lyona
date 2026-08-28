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
