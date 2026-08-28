#!/bin/sh
# Covers tests/lib.sh itself. The other tests inherit their failure reporting
# and teardown from it, so a silent regression here degrades every one of them.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace

assert_dir "$repo/tests" 'lib.sh resolved the repo root'
assert_file "$repo/tests/lib.sh"
assert_equals "$repo/tests" "$tests_dir" 'tests_dir points at this directory'
assert_equals test-lib.sh "$test_name" 'test_name is the script basename'

# A test run as `tests/test-foo.sh` from the repo root gets a *relative* $0, so
# `cd "$(dirname "$0")"` consults CDPATH. With a CDPATH entry that also has a
# tests/ directory, an unguarded resolution lands in the wrong tree entirely.
# That is the latent bug in the 18 files that had no guard.
mkdir -p "$work/decoy/tests" "$work/real/tests"
cp -- "$repo/tests/lib.sh" "$work/real/tests/lib.sh"

cat >"$work/real/tests/guarded.sh" <<'SH'
#!/bin/sh
set -eu
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
printf '%s\n' "$repo"
SH
cat >"$work/real/tests/unguarded.sh" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$(cd "$(dirname "$0")/.." && pwd)"
SH
chmod +x "$work/real/tests/guarded.sh" "$work/real/tests/unguarded.sh"

guarded_root=$(cd "$work/real" && CDPATH=$work/decoy tests/guarded.sh)
assert_equals "$work/real" "$guarded_root" \
	'the shared bootstrap ignores CDPATH'

# Proof the case above is real rather than vacuous: the old idiom follows
# CDPATH into the decoy tree, and cd's own echo of the directory it landed in
# corrupts the captured value on top of that.
unguarded_root=$(cd "$work/real" && CDPATH=$work/decoy tests/unguarded.sh 2>/dev/null)
if [ "$unguarded_root" = "$work/real" ]; then
	fail 'the unguarded idiom was expected to be diverted by CDPATH'
fi
assert_string_contains "$unguarded_root" "$work/decoy" \
	'the unguarded idiom lands in the decoy tree'

# ── Assertions report what failed ────────────────────────────────────────

subject=$work/subject.txt
printf 'alpha\nbeta gamma\n' >"$subject"

assert_contains "$subject" 'beta gamma'
assert_not_contains "$subject" 'delta'
assert_line "$subject" alpha
assert_no_line "$subject" 'beta'
assert_matches "$subject" '^beta [a-z]+$'
assert_equals one one
assert_string_contains 'a needle in here' needle

# Each negative case runs as its own script, since a failing assertion exits.
# Running it rather than sourcing it in a subshell is also how a real test uses
# the library.
run_case() {
	case_script=$work/case.sh
	case_out=$work/case.out
	{
		printf '#!/bin/sh\nset -eu\n'
		printf '. "%s/tests/lib.sh"\n' "$repo"
		printf '%s\n' "$1"
	} >"$case_script"
	chmod +x "$case_script"
	set +e
	"$case_script" >"$case_out" 2>&1
	case_status=$?
	set -e
	[ "$case_status" -ne 0 ] || fail "expected a failure from: $1"
	assert_contains "$case_out" "$2"
}

run_case "assert_file '$work/absent'" 'expected a file at'
run_case "assert_no_file '$subject'" 'expected nothing at'
run_case "assert_contains '$subject' delta" 'does not contain delta'
run_case "assert_contains '$subject' delta" 'beta gamma'
run_case "assert_not_contains '$subject' alpha" 'unexpectedly contains alpha'
run_case "assert_line '$subject' beta" 'has no line reading exactly beta'
run_case "assert_no_line '$subject' alpha" 'unexpectedly has a line reading exactly alpha'
run_case "assert_matches '$subject' '^zzz'" 'does not match'
run_case "assert_equals one two" 'expected: one'
run_case "assert_equals one two" 'actual:   two'
run_case "assert_string_contains haystack needle" 'expected to contain: needle'
run_case "fail 'a stated reason'" 'a stated reason'
run_case "assert_contains '$work/absent' anything" 'expected a file at'

# A long file is truncated rather than dumped whole.
long_subject=$work/long.txt
i=1
while [ "$i" -le 40 ]; do
	printf 'line %s\n' "$i" >>"$long_subject"
	i=$((i + 1))
done
run_case "assert_contains '$long_subject' nope" '... (truncated)'
long_out=$work/case.out
assert_contains "$long_out" 'line 20'
assert_not_contains "$long_out" 'line 21'

# ── Cleanup composition ──────────────────────────────────────────────────

# Actions run last-registered-first, so teardown unwinds in the order a test
# would write it by hand: kill the process, then remove the directory it wrote
# into.
order_probe=$work/order-probe.sh
order_log=$work/order.log
cat >"$order_probe" <<SH
#!/bin/sh
set -eu
. "$repo/tests/lib.sh"
cleanup_add "printf 'first-registered\\n' >>'$order_log'"
cleanup_add "printf 'second-registered\\n' >>'$order_log'"
SH
chmod +x "$order_probe"
"$order_probe"
assert_equals 'second-registered
first-registered' "$(cat "$order_log")" 'cleanup runs last-registered-first'

# The workspace is removed on exit, and a non-zero exit status survives the
# trap rather than being masked by it.
workspace_probe=$work/workspace-probe.sh
workspace_record=$work/workspace-path
cat >"$workspace_probe" <<SH
#!/bin/sh
set -eu
. "$repo/tests/lib.sh"
make_workspace
printf '%s\n' "\$work" >'$workspace_record'
exit 3
SH
chmod +x "$workspace_probe"
set +e
"$workspace_probe"
workspace_status=$?
set -e
assert_equals 3 "$workspace_status" 'the EXIT trap preserves the exit status'
assert_no_file "$(cat "$workspace_record")" 'make_workspace removed its directory'

# A killed test still cleans up, and reports the conventional 128+signal.
signal_probe=$work/signal-probe.sh
signal_record=$work/signal-path
signal_ready=$work/signal-ready
cat >"$signal_probe" <<SH
#!/bin/sh
set -eu
. "$repo/tests/lib.sh"
make_workspace
printf '%s\n' "\$work" >'$signal_record'
: >'$signal_ready'
sleep 30
SH
chmod +x "$signal_probe"
"$signal_probe" &
signal_pid=$!
signal_waited=0
while [ ! -e "$signal_ready" ] && [ "$signal_waited" -lt 100 ]; do
	sleep 0.05
	signal_waited=$((signal_waited + 1))
done
assert_file "$signal_ready" 'the signal probe started'
kill -TERM "$signal_pid"
set +e
wait "$signal_pid"
signal_status=$?
set -e
assert_equals 143 "$signal_status" 'a TERMed test exits 128+15'
assert_no_file "$(cat "$signal_record")" 'a TERMed test still removes its workspace'

# A workspace whose path contains a space is still removed.
space_probe=$work/space-probe.sh
space_record=$work/space-path
cat >"$space_probe" <<SH
#!/bin/sh
set -eu
. "$repo/tests/lib.sh"
TMPDIR='$work/tmp dir'
export TMPDIR
mkdir -p "\$TMPDIR"
make_workspace
printf '%s\n' "\$work" >'$space_record'
SH
chmod +x "$space_probe"
"$space_probe"
assert_no_file "$(cat "$space_record")" 'a workspace path with a space is removed'

# ── PATH stubs ───────────────────────────────────────────────────────────

stub_command probe-tool <<'SH'
#!/bin/sh
printf 'probe-tool %s\n' "$*"
SH
assert_executable "$work/bin/probe-tool"
assert_equals 'probe-tool one two' "$(PATH=$work/bin:$PATH probe-tool one two)" \
	'stub_command wrote a working stub'

DWM_TEST_LOG=$work/stub.log
export DWM_TEST_LOG
: >"$DWM_TEST_LOG"
stub_logging_command logged-tool
PATH=$work/bin:$PATH logged-tool alpha beta
assert_line "$DWM_TEST_LOG" 'logged-tool alpha beta'

run_case "work=; stub_command anything </dev/null" 'needs a workspace'

printf '%s\n' 'Shared test library: PASS'
