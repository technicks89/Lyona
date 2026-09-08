#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
repo=${DWM_SYSTEM_MANAGEMENT_XVFB_REPO:-$repo}

for command_name in Xvfb quickshell xprop getconf pgrep; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

if [ "$(id -u)" -eq 0 ] && [ "${DWM_SYSTEM_MANAGEMENT_XVFB_UNPRIVILEGED:-0}" != 1 ]; then
	command -v setpriv >/dev/null 2>&1 || {
		printf 'Quickshell system-management Xvfb requires setpriv on a root runner\n' >&2
		exit 1
	}
	unprivileged_uid=$(id -u nobody)
	unprivileged_gid=$(id -g nobody)
	root_runner_work=$(mktemp -d /var/tmp/dwm-system-management-root.XXXXXX)
	trap 'rm -rf -- "$root_runner_work"' EXIT
	fixture_repo=$root_runner_work/repo
	mkdir -p "$root_runner_work/cache" "$root_runner_work/config" \
		"$root_runner_work/data" "$root_runner_work/runtime" \
		"$root_runner_work/state" "$fixture_repo/tests"
	cp -a "$repo/config" "$repo/scripts" "$fixture_repo/"
	cp "$repo/tests/lib.sh" "$fixture_repo/tests/lib.sh"
	mkdir -p "$fixture_repo/assets"
	cp -a "$repo/assets/logo" "$fixture_repo/assets/logo"
	cp "$repo/dwm" "$fixture_repo/dwm"
	cp "$0" "$fixture_repo/tests/test-quickshell-system-management-xvfb.sh"
	chown -R "$unprivileged_uid:$unprivileged_gid" "$root_runner_work"
	chmod 700 "$fixture_repo/dwm" "$root_runner_work/runtime"
	if HOME="$root_runner_work" TMPDIR="$root_runner_work" \
		DWM_SYSTEM_MANAGEMENT_XVFB_REPO="$fixture_repo" \
		DWM_SYSTEM_MANAGEMENT_XVFB_UNPRIVILEGED=1 \
		XDG_CACHE_HOME="$root_runner_work/cache" \
		XDG_CONFIG_HOME="$root_runner_work/config" \
		XDG_DATA_HOME="$root_runner_work/data" \
		XDG_RUNTIME_DIR="$root_runner_work/runtime" \
		XDG_STATE_HOME="$root_runner_work/state" \
		setpriv --reuid "$unprivileged_uid" --regid "$unprivileged_gid" \
		--clear-groups "$fixture_repo/tests/test-quickshell-system-management-xvfb.sh" "$@"; then
		root_runner_status=0
	else
		root_runner_status=$?
	fi
	rm -rf -- "$root_runner_work"
	trap - EXIT
	exit "$root_runner_status"
fi

if [ "${DWM_SYSTEM_MANAGEMENT_XVFB_DBUS_SESSION:-0}" != 1 ]; then
	if ! command -v dbus-run-session >/dev/null 2>&1; then
		printf 'SKIP: dbus-run-session is unavailable\n'
		exit 77
	fi
	exec env DWM_SYSTEM_MANAGEMENT_XVFB_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
display=":$((($$ % 300) + 1400))"
runtime_alias_dir=
test_stage='initializing fixture'
cleanup() {
	cleanup_status=$?
	set +e
	if [ "$cleanup_status" -ne 0 ]; then
		printf 'System-management Xvfb failed while %s (status %s)\n' \
			"${test_stage:-stage unknown}" "$cleanup_status" >&2
		[ ! -f "$work/quickshell.log" ] || tail -80 "$work/quickshell.log" >&2
		[ ! -f "$work/dwm.log" ] || tail -40 "$work/dwm.log" >&2
	fi
	[ -n "${quickshell_pid:-}" ] && kill "$quickshell_pid" 2>/dev/null
	[ -n "${dwm_pid:-}" ] && kill "$dwm_pid" 2>/dev/null
	[ -n "${xvfb_pid:-}" ] && kill "$xvfb_pid" 2>/dev/null
	if [ -n "${runtime_alias_dir:-}" ]; then
		rm -f -- "$runtime_alias_dir/runtime"
		rmdir -- "$runtime_alias_dir" 2>/dev/null || true
	fi
	rm -rf "$work"
	trap - EXIT HUP INT TERM
	exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 143' HUP INT TERM

home=$work/home
runtime_storage=$work/runtime
runtime=$runtime_storage
config_home=$home/.config
data_home=$home/.local/share
mkdir -p "$config_home/quickshell" "$config_home/lyona" "$home/.cache" \
	"$data_home/lyona/scripts" "$runtime"
chmod 700 "$runtime_storage"
if [ "${#runtime}" -gt 64 ]; then
	runtime_alias_dir=$(mktemp -d /tmp/dwm-system-management-runtime.XXXXXX)
	ln -s "$runtime_storage" "$runtime_alias_dir/runtime"
	runtime=$runtime_alias_dir/runtime
fi
cp -a "$repo/config/quickshell/." "$config_home/quickshell/"
cp "$repo/config/"*.toml "$config_home/lyona/"
cp "$repo/scripts/dwm-settings-provider" "$repo/scripts/dwm-system-health" \
	"$data_home/lyona/scripts/"

# A stub dwm-system-management: one pending kernel update (exercising the
# restart heuristic's "system" branch, docs/SYNC-P2-UPDATE-SNAPSHOT.md
# section 5) and one dependency-preview row, so the pane's counts and IPC
# probes have real content to assert against without a live PackageKit
# daemon.
cat >"$data_home/lyona/scripts/dwm-system-management" <<'SH'
#!/bin/sh
set -eu
case "${1:-}" in
snapshot)
	printf 'system-management-protocol\t1\t0\n'
	printf 'snapshot-generation\t%s\n' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
	printf 'provider\tupdates\tpartial\tdelegated\tPackageKit\tRead-only update discovery is available\n'
	printf 'provider\trecovery\tunsupported\tuser-session\tdwm-system-management\tManaged update recovery is not enabled in this build\n'
	printf 'state\tupdate-summary\tavailable\t1\tPackageKit update discovery completed\n'
	printf 'state\tupdate-last-refresh\tavailable\t120\tSeconds since PackageKit last refreshed metadata\n'
	printf 'state\tupdate-restart\tavailable\tsystem\tHeuristic guidance over pending package names\n'
	printf 'action\tupdates-refresh\tunavailable\tdelegated\tupdates\tRefresh updates\tManaged update operations are not enabled in this build\n'
	printf 'action\tupdates-install-all\tunavailable\tdelegated\tupdates\tInstall all updates\tManaged update operations are not enabled\n'
	printf 'action\tupdates-cancel\tunavailable\tdelegated\tupdates\tCancel update\tNo managed update operation is active\n'
	printf 'update\tlinux-cachyos;6.18.1-1;x86_64;core\tunknown\tinstallable\tlinux-cachyos\t6.18.1-1\tCachyOS kernel\n'
	printf 'package-change\tlinux-cachyos;6.18.1-1;x86_64;core\tupdate\tlinux-cachyos\t6.18.1-1\tCachyOS kernel\n'
	printf 'complete\tsnapshot\n'
	;;
*)
	exit 2
	;;
esac
SH
chmod +x "$data_home/lyona/scripts/dwm-system-management"

Xvfb "$display" -screen 0 1280x800x24 -nolisten tcp -extension GLX >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!

i=0
while [ "$i" -lt 100 ]; do
	DISPLAY=$display xprop -root >/dev/null 2>&1 && break
	i=$((i + 1))
	sleep 0.05
done
DISPLAY=$display xprop -root >/dev/null

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime DWM_AUTOSTART_NO_INPUT_WATCH=1 \
	"$repo/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_CACHE_HOME="$home/.cache" XDG_RUNTIME_DIR="$runtime" \
	QSG_RHI_BACKEND=software QT_QUICK_BACKEND=software \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!
config=$config_home/quickshell/shell.qml

ipc() {
	DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_CACHE_HOME=$home/.cache \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call "$@"
}

test_stage='waiting for settings IPC'
i=0
while [ "$i" -lt 200 ]; do
	ipc settings status >/dev/null 2>&1 && break
	i=$((i + 1))
	sleep 0.05
done
ipc settings status >/dev/null

test_stage='loading the system-management snapshot'
ipc settings open >/dev/null
ipc settings select system >/dev/null
[ "$(ipc settings currentSection)" = system ]

snapshot_state=
i=0
while [ "$i" -lt 100 ]; do
	snapshot_state=$(ipc settings systemManagementSnapshotState 2>/dev/null || true)
	[ "$snapshot_state" = loaded ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$snapshot_state" != loaded ]; then
	printf 'System management snapshot did not load: %s\n' "$snapshot_state" >&2
	exit 1
fi

test_stage='validating parsed snapshot content'
[ "$(ipc settings systemManagementUpdateCount)" -eq 1 ]
[ "$(ipc settings systemManagementPackageChangeCount)" -eq 1 ]
# Confirms the Arch-only restart heuristic's "system" value (a linux-cachyos
# update pending) round-trips through the model's own enum validation.
[ "$(ipc settings systemManagementRestartState)" = 'available:system' ]

# These assert directly on systemManagementModel.settingsVisible (exposed
# for exactly this) rather than on timing or process survival. A stub delay
# or "does the next fetch complete" proxy cannot isolate this: every real
# reopen path (open(), openOnScreen(), toggle()) resets to the "displays"
# section first, and *that* transition always correctly calls
# closeSettings() via activateSection regardless of whether close() itself
# does -- so by the time "system" is reselected, activateSection's own
# transition has already masked the bug. The only place the omission is
# actually observable is settingsVisible staying true immediately after
# close(), before any other section transition has a chance to paper over
# it. checkedCommand's `output=$("$@")` also means killing the wrapping
# process does not kill the real helper (an orphaned command-substitution
# child keeps running to its own completion), so process-liveness checks
# cannot substitute for reading the model's own state either.

test_stage='validating that closing the section resets settingsVisible'
ipc settings select displays >/dev/null
[ "$(ipc settings systemManagementSettingsVisible)" = false ]
ipc settings select system >/dev/null
[ "$(ipc settings systemManagementSettingsVisible)" = true ]
ipc settings select displays >/dev/null
if [ "$(ipc settings systemManagementSettingsVisible)" != false ]; then
	printf 'systemManagementModel.settingsVisible stayed true after navigating away from "system"\n' >&2
	exit 1
fi

test_stage='validating that closing the whole Settings window resets settingsVisible'
# close() (the whole-window path, distinct from selecting a different
# section) does not route through activateSection -- it must still pair
# openSettings()/closeSettings() for every Settings-only model, including
# systemManagementModel, or settingsVisible/snapshotProcess never reset
# while the window stays closed.
ipc settings open >/dev/null
ipc settings select system >/dev/null
[ "$(ipc settings systemManagementSettingsVisible)" = true ]
ipc settings close >/dev/null
if [ "$(ipc settings systemManagementSettingsVisible)" != false ]; then
	printf 'systemManagementModel.settingsVisible stayed true after closing the Settings window\n' >&2
	exit 1
fi

if ! kill -0 "$dwm_pid" 2>/dev/null; then
	printf 'dwm exited before system-management validation completed\n' >&2
	tail -40 "$work/dwm.log" >&2
	exit 1
fi
if ! kill -0 "$quickshell_pid" 2>/dev/null; then
	printf 'Quickshell exited before system-management validation completed\n' >&2
	tail -60 "$work/quickshell.log" >&2
	exit 1
fi

printf 'Quickshell system-management pane Xvfb: PASS\n'
