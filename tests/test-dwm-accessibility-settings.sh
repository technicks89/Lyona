#!/usr/bin/env bash
# Covers scripts/dwm-accessibility-settings: the persistent contrast/motion
# policy store behind config/quickshell/accessibility/AccessibilityModel.qml
# and Theme.qml's highContrast/reducedMotion properties.

set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace

helper=$repo/scripts/dwm-accessibility-settings
assert_executable "$helper"

home=$work/home
config=$work/config
runtime=$work/runtime
mkdir -p "$home" "$config" "$runtime"

state_file=$config/lyona/accessibility.conf
watch_pid=
# shellcheck disable=SC2016 # deferred: eval expands $watch_pid at cleanup time, not now
cleanup_add 'kill "$watch_pid" 2>/dev/null || true; wait "$watch_pid" 2>/dev/null || true'

run_helper() {
	HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" "$helper" "$@"
}

# Poll for a readiness file rather than sleeping a fixed interval -- the
# helper's test seams (DWM_TEST_ACCESSIBILITY_*_READY/_RELEASE) exist
# precisely so these races don't need a guessed sleep.
wait_for() {
	local path=$1 attempt=0
	while [ ! -e "$path" ]; do
		attempt=$((attempt + 1))
		if [ "$attempt" -ge 200 ]; then
			fail "timed out waiting for $path"
		fi
		sleep 0.01
	done
}

wait_for_line() {
	local file=$1 line=$2 attempt=0
	while ! grep -Fqx "$line" "$file" 2>/dev/null; do
		attempt=$((attempt + 1))
		if [ "$attempt" -ge 200 ]; then
			fail "timed out waiting for $file to contain: $line"
		fi
		sleep 0.01
	done
}

# ── status with nothing configured ───────────────────────────────────────

status=$(run_helper status)
assert_string_contains "$status" $'accessibility-settings-protocol\t1\t0'
assert_string_contains "$status" \
	$'state\tdefaults\tUsing standard contrast and full motion defaults'
assert_string_contains "$status" $'setting\tcontrast\tstandard'
assert_string_contains "$status" $'setting\tmotion\tfull'
assert_string_contains "$status" $'complete\tstatus'
assert_string_contains "$status" $'mutation\tavailable\tAccessibility policy can be updated'
assert_no_file "$state_file" 'status alone must not create persistent state'

# ── the watch handshake fires, and a killed inotifywait is not hidden ───

HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" watch >"$work/first-watch.out" 2>"$work/first-watch.err" &
watch_pid=$!
wait_for_line "$work/first-watch.out" $'ready\taccessibility'
assert_dir "$config/lyona"
watch_child=$(pgrep -P "$watch_pid" -x inotifywait)
kill "$watch_child"
for _ in $(seq 1 200); do
	kill -0 "$watch_pid" 2>/dev/null || break
	sleep 0.01
done
if kill -0 "$watch_pid" 2>/dev/null; then
	fail 'the watcher hid inotifywait termination'
fi
if wait "$watch_pid"; then
	fail 'the watcher unexpectedly succeeded after inotifywait terminated'
fi
watch_pid=

# ── set persists, with an exact action confirmation ──────────────────────

contrast_action=$(run_helper set contrast high)
assert_string_contains "$contrast_action" $'accessibility-settings-action-protocol\t1\t0'
assert_string_contains "$contrast_action" $'result\tset\tcontrast\thigh'
assert_equals 600 "$(stat -c %a "$state_file")" 'a freshly created state file must be mode 600'

motion_action=$(run_helper set motion reduced)
assert_string_contains "$motion_action" $'result\tset\tmotion\treduced'
status=$(run_helper status)
assert_string_contains "$status" \
	$'state\tavailable\tPersistent managed-shell accessibility policy is active'
assert_string_contains "$status" $'setting\tcontrast\thigh'
assert_string_contains "$status" $'setting\tmotion\treduced'

# ── writes preserve whatever mode the file already had ──────────────────

chmod 640 "$state_file"
run_helper set contrast standard >/dev/null
assert_equals 640 "$(stat -c %a "$state_file")" 'set must preserve the existing file mode'

reset_action=$(run_helper reset)
assert_string_contains "$reset_action" $'result\treset\tall\tdefaults'
assert_line "$state_file" $'contrast\tstandard'
assert_line "$state_file" $'motion\tfull'

# ── a live watch reports a change and then a delete ──────────────────────

HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" watch >"$work/watch.out" 2>"$work/watch.err" &
watch_pid=$!
wait_for_line "$work/watch.out" $'ready\taccessibility'

# The mutation-readiness probe creates, exchanges, and removes two dotfiles
# in the same directory the watch is on -- none of that churn may reach the
# watch stream as a false "the policy changed" signal.
run_helper status >/dev/null
sleep 0.1
if grep -Eq '^changed\t' "$work/watch.out" 2>/dev/null; then
	fail 'the mutation-readiness probe leaked a policy change event'
fi
if find "$config/lyona" -maxdepth 1 -name '.accessibility-exchange-*' -print -quit | grep -q .; then
	fail 'the mutation-readiness probe left temporary files behind'
fi

run_helper set contrast high >/dev/null
for _ in $(seq 1 200); do
	grep -Eq '^changed\t' "$work/watch.out" 2>/dev/null && break
	sleep 0.01
done
assert_contains "$work/watch.out" $'changed\t'
rm "$state_file"
rmdir "$config/lyona"
for _ in $(seq 1 200); do
	grep -Fq 'DELETE_SELF' "$work/watch.out" 2>/dev/null && break
	sleep 0.01
done
assert_contains "$work/watch.out" 'DELETE_SELF'
kill "$watch_pid" 2>/dev/null || true
wait "$watch_pid" 2>/dev/null || true
watch_pid=
mkdir "$config/lyona"

# ── a malformed file is preserved verbatim, not rewritten ───────────────

printf 'broken-protocol\n' >"$state_file"
malformed_status=$(run_helper status)
assert_string_contains "$malformed_status" \
	$'state\tpartial\tMalformed accessibility settings were preserved; using safe defaults'
assert_string_contains "$malformed_status" $'setting\tcontrast\tstandard'
assert_string_contains "$malformed_status" $'setting\tmotion\tfull'
assert_string_contains "$malformed_status" $'mutation\tavailable\tAccessibility policy can be updated'
run_helper set motion reduced >/dev/null
assert_line "$state_file" $'contrast\tstandard'
assert_line "$state_file" $'motion\treduced'

# ── a malformed header (an extra field) is also caught ───────────────────

printf 'accessibility-settings-protocol\t1\t0\textra\ncontrast\thigh\nmotion\treduced\n' \
	>"$state_file"
malformed_header_status=$(run_helper status)
assert_string_contains "$malformed_header_status" \
	$'state\tpartial\tMalformed accessibility settings were preserved; using safe defaults'
run_helper reset >/dev/null
assert_line "$state_file" $'accessibility-settings-protocol\t1\t0'
assert_line "$state_file" $'contrast\tstandard'
assert_line "$state_file" $'motion\tfull'

# ── an unsupported protocol version is preserved, not silently upgraded ─

printf 'accessibility-settings-protocol\t2\t0\ncontrast\thigh\nmotion\treduced\n' \
	>"$state_file"
future_status=$(run_helper status)
assert_string_contains "$future_status" \
	$'state\tpartial\tUnsupported accessibility settings version was preserved; using safe defaults'
assert_string_contains "$future_status" \
	$'mutation\tunavailable\tPersistent accessibility state cannot be safely replaced'
assert_line "$state_file" $'accessibility-settings-protocol\t2\t0'
cp "$state_file" "$work/future.before"
if run_helper set contrast high >"$work/future-set.out" 2>"$work/future-set.err"; then
	fail 'a future-version state was unexpectedly replaced by set'
fi
assert_contains "$work/future-set.err" 'unsupported version'
cmp -s "$work/future.before" "$state_file" || fail 'future-version state must survive an attempted set untouched'
if run_helper reset >"$work/future-reset.out" 2>"$work/future-reset.err"; then
	fail 'a future-version state was unexpectedly replaced by reset'
fi
assert_contains "$work/future-reset.err" 'unsupported version'
cmp -s "$work/future.before" "$state_file" || fail 'future-version state must survive an attempted reset untouched'

# ── mutation reports unavailable when the filesystem can't exchange atomically ─

printf 'accessibility-settings-protocol\t1\t0\ncontrast\tstandard\nmotion\tfull\n' >"$state_file"
real_mv=$(command -v mv)
no_exchange_bin=$work/no-exchange-bin
mkdir "$no_exchange_bin"
cat >"$no_exchange_bin/mv" <<EOF
#!/bin/sh
for argument do
	[ "\$argument" != --exchange ] || exit 1
done
exec "$real_mv" "\$@"
EOF
chmod 700 "$no_exchange_bin/mv"
no_exchange_config=$work/no-exchange-config
mkdir "$no_exchange_config"
initial_exchange_unavailable_status=$(HOME="$home" XDG_CONFIG_HOME="$no_exchange_config" \
	XDG_RUNTIME_DIR="$runtime" PATH="$no_exchange_bin:$PATH" "$helper" status)
assert_string_contains "$initial_exchange_unavailable_status" \
	$'mutation\tunavailable\tAtomic accessibility state exchange is unavailable on the configuration filesystem'
assert_no_file "$no_exchange_config/lyona/accessibility.conf"
exchange_unavailable_status=$(HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	PATH="$no_exchange_bin:$PATH" "$helper" status)
assert_string_contains "$exchange_unavailable_status" \
	$'mutation\tunavailable\tAtomic accessibility state exchange is unavailable on the configuration filesystem'
if find "$config/lyona" -maxdepth 1 -name '.accessibility-exchange-*' -print -quit | grep -q .; then
	fail 'the mutation-readiness probe left temporary files behind after a failed exchange'
fi

# ── a single concurrent edit between staging and publish is refused ─────

printf 'accessibility-settings-protocol\t1\t0\ncontrast\tstandard\nmotion\tfull\n' >"$state_file"
baseline_ready=$work/baseline.ready
baseline_release=$work/baseline.release
DWM_TEST_ACCESSIBILITY_BASELINE_READY=$baseline_ready \
	DWM_TEST_ACCESSIBILITY_BASELINE_RELEASE=$baseline_release \
	HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" set contrast high >"$work/baseline-race.out" 2>"$work/baseline-race.err" &
baseline_race_pid=$!
wait_for "$baseline_ready"
printf 'external edit\n' >"$state_file"
: >"$baseline_release"
if wait "$baseline_race_pid"; then
	fail 'a transaction overwrote an edit made before the baseline was captured'
fi
assert_contains "$work/baseline-race.err" 'accessibility state changed during the transaction'
assert_line "$state_file" 'external edit'

# ── the same race, but the edit lands at the exchange itself ────────────

printf 'accessibility-settings-protocol\t1\t0\ncontrast\tstandard\nmotion\tfull\n' >"$state_file"
exchange_ready=$work/exchange.ready
exchange_release=$work/exchange.release
DWM_TEST_ACCESSIBILITY_EXCHANGE_READY=$exchange_ready \
	DWM_TEST_ACCESSIBILITY_EXCHANGE_RELEASE=$exchange_release \
	HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" set contrast high >"$work/exchange-race.out" 2>"$work/exchange-race.err" &
exchange_race_pid=$!
wait_for "$exchange_ready"
printf 'last-moment edit\n' >"$state_file"
: >"$exchange_release"
if wait "$exchange_race_pid"; then
	fail 'an exchange overwrote a last-moment concurrent edit'
fi
assert_contains "$work/exchange-race.err" 'accessibility state changed during the transaction'
assert_line "$state_file" 'last-moment edit'

# ── two edits in a row exhaust the retry budget without ever clobbering ─

printf 'accessibility-settings-protocol\t1\t0\ncontrast\tstandard\nmotion\tfull\n' >"$state_file"
exchange_ready=$work/two-edit-exchange.ready
exchange_release=$work/two-edit-exchange.release
rollback_ready=$work/two-edit-rollback.ready
rollback_release=$work/two-edit-rollback.release
DWM_TEST_ACCESSIBILITY_EXCHANGE_READY=$exchange_ready \
	DWM_TEST_ACCESSIBILITY_EXCHANGE_RELEASE=$exchange_release \
	DWM_TEST_ACCESSIBILITY_ROLLBACK_READY=$rollback_ready \
	DWM_TEST_ACCESSIBILITY_ROLLBACK_RELEASE=$rollback_release \
	HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	"$helper" set contrast high >"$work/two-edit-race.out" 2>"$work/two-edit-race.err" &
two_edit_race_pid=$!
wait_for "$exchange_ready"
printf 'first last-moment edit\n' >"$state_file"
: >"$exchange_release"
wait_for "$rollback_ready"
printf 'second last-moment edit\n' >"$state_file"
: >"$rollback_release"
if wait "$two_edit_race_pid"; then
	fail 'exchange retries overwrote a two-edit race'
fi
assert_contains "$work/two-edit-race.err" 'accessibility state changed during the transaction'
assert_line "$state_file" 'second last-moment edit'

# ── a symlinked state file is refused outright, not followed ────────────

target=$work/target
printf 'do not replace\n' >"$target"
rm "$state_file"
ln -s "$target" "$state_file"
unsafe_status=$(run_helper status)
assert_string_contains "$unsafe_status" \
	$'state\tunavailable\tPersistent accessibility state is unsafe; using safe defaults'
if run_helper set contrast high >"$work/symlink.out" 2>"$work/symlink.err"; then
	fail 'a mutation unexpectedly followed a symlinked state file'
fi
assert_line "$target" 'do not replace'

# ── a hard-linked state file is refused, not replaced out from under it ─

rm "$state_file"
printf 'accessibility-settings-protocol\t1\t0\ncontrast\tstandard\nmotion\tfull\n' >"$state_file"
ln "$state_file" "$work/accessibility-hardlink.conf"
if run_helper reset >"$work/hardlink.out" 2>"$work/hardlink.err"; then
	fail 'a mutation unexpectedly replaced a hard-linked state file'
fi
assert_contains "$work/hardlink.err" 'unsafe persistent state'
rm "$work/accessibility-hardlink.conf"

# ── a relative XDG_RUNTIME_DIR is refused, not silently accepted ────────

if HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR=relative \
	"$helper" status >"$work/runtime.out" 2>"$work/runtime.err"; then
	fail 'a relative XDG_RUNTIME_DIR unexpectedly succeeded'
fi
assert_contains "$work/runtime.err" 'XDG_RUNTIME_DIR must be absolute'

# ── an invalid setting value is refused ──────────────────────────────────

if run_helper set contrast invalid >"$work/invalid.out" 2>"$work/invalid.err"; then
	fail 'an invalid contrast value unexpectedly succeeded'
fi
assert_contains "$work/invalid.err" 'unsupported accessibility setting'

# ── the runtime lock actually excludes a concurrent operation ───────────

lock_ready=$work/lock.ready
lock_release=$work/lock.release
(
	exec 8>"$runtime/dwm-accessibility-settings.lock"
	flock 8
	: >"$lock_ready"
	while [ ! -e "$lock_release" ]; do
		sleep 0.01
	done
) &
lock_holder_pid=$!
wait_for "$lock_ready"
set +e
HOME="$home" XDG_CONFIG_HOME="$config" XDG_RUNTIME_DIR="$runtime" \
	timeout 7 "$helper" set motion reduced >"$work/lock.out" 2>"$work/lock.err"
lock_status=$?
set -e
: >"$lock_release"
wait "$lock_holder_pid"
assert_equals 1 "$lock_status" 'a mutation under a held lock should fail, not silently proceed'
assert_contains "$work/lock.err" 'another accessibility settings operation is still running'

printf 'dwm accessibility settings helper: PASS\n'
