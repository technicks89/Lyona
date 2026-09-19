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
# daemon. Sync Phase 9 follow-up (docs/SYNC-P9-REGIONAL-MUTATION.md §5.7)
# adds protocol minor 1's native rows plus fixed regional-choices/
# regional-preview/timezone-set/ntp-set/locale-set/*-open responses, so
# SystemRegionalControls has real content for a full preview -> confirm ->
# dispatch -> verified-result cycle, not just idle defaults.
cat >"$data_home/lyona/scripts/dwm-system-management" <<'SH'
#!/bin/sh
set -eu
generation='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
opid='op-11111111111111111111111111111111'
case "${1:-}" in
snapshot | snapshot-core | snapshot-without-storage)
	# Sync Sprint 2 S2-05 (#286): a required (recovery-only) read always asks
	# for snapshot-core (native rows, no information/storage/security block,
	# protocol stays at NATIVE_SNAPSHOT_MINOR); an optional read asks for
	# snapshot-without-storage until the storage domain's own watch-mounts
	# subscription is ready (filesystem-summary stays partial, no filesystem
	# rows), then snapshot once it is.
	printf 'system-management-protocol\t1\t%s\n' "$([ "$1" = snapshot-core ] && printf 1 || printf 2)"
	printf 'snapshot-generation\t%s\n' "$generation"
	printf 'provider\tupdates\tpartial\tdelegated\tPackageKit\tRead-only update discovery is available\n'
	printf 'provider\trecovery\tunsupported\tuser-session\tdwm-system-management\tManaged update recovery is not enabled in this build\n'
	printf 'provider\tregional\tavailable\tdelegated\torg.freedesktop.timedate1\tRegional status is available\n'
	printf 'provider\taccounts\tavailable\tdelegated\torg.freedesktop.Accounts\tAccount status is available\n'
	printf 'provider\tprinters\tavailable\tdelegated\torg.freedesktop.systemd1\tPrinter status is available\n'
	printf 'provider\tsources\tavailable\tdelegated\torg.freedesktop.PackageKit\tSoftware source status is available\n'
	if [ "$1" != snapshot-core ]; then
		printf 'provider\tinformation\tavailable\tread-only\tdwm-system-management\tBounded read-only observations; inspect individual state details\n'
		printf 'provider\tstorage\tavailable\tread-only\tdwm-system-management\tBounded read-only observations; inspect individual state details\n'
		printf 'provider\tsecurity\tavailable\tread-only\tdwm-system-management\tBounded read-only observations; inspect individual state details\n'
		printf 'provider\tdiagnostics\tavailable\tuser-session\tdwm-system-health\tExisting health scan, diagnostics, and fixed repair workflow\n'
	fi
	printf 'state\tupdate-summary\tavailable\t1\tPackageKit update discovery completed\n'
	printf 'state\tupdate-last-refresh\tavailable\t120\tSeconds since PackageKit last refreshed metadata\n'
	printf 'state\tupdate-restart\tavailable\tsystem\tHeuristic guidance over pending package names\n'
	printf 'state\ttimezone\tavailable\tEtc/UTC\tSystem timezone\n'
	printf 'state\tntp-enabled\tavailable\tyes\tNetwork time enablement\n'
	printf 'state\tntp-synchronized\tavailable\tyes\tNetwork time synchronization at this read\n'
	printf 'state\tlocale\tavailable\tC\t\n'
	printf 'state\taccounts-count\tavailable\t1\tAccount count\n'
	printf 'state\tcups-service\tavailable\tstopped\tCUPS state\n'
	if [ "$1" != snapshot-core ]; then
		printf 'state\tos-name\tavailable\tFixture Linux\tOperating system identity\n'
		printf 'state\tos-version\tavailable\trolling\tOperating system identity\n'
		printf 'state\tkernel-release\tavailable\t6.18.1-fixture\tKernel identity\n'
		printf 'state\tarchitecture\tavailable\tx86_64\tKernel identity\n'
		printf 'state\thardware-vendor\tavailable\tFixture Vendor\tHardware identity\n'
		printf 'state\thardware-model\tavailable\tFixture Model\tHardware identity\n'
		printf 'state\tcpu-model\tavailable\tFixture CPU\tProcessor model\n'
		printf 'state\tlogical-cpus\tavailable\t8\tLogical processors\n'
		printf 'state\tmemory-total-bytes\tavailable\t16000000000\tMemory bytes at this read\n'
		printf 'state\tmemory-available-bytes\tavailable\t8000000000\tMemory bytes at this read\n'
		printf 'state\tswap-total-bytes\tavailable\t0\tMemory bytes at this read\n'
		printf 'state\tswap-free-bytes\tavailable\t0\tMemory bytes at this read\n'
		printf 'state\tuptime-seconds\tavailable\t3600\tWhole seconds since boot, including suspend\n'
		printf 'state\tselinux\tavailable\tdisabled\tInformation source is absent\n'
		printf 'state\tsecure-boot\tavailable\tdisabled\tEFI Secure Boot variable\n'
		printf 'state\tfirewalld\tavailable\tdisabled\tFirewalld status\n'
		printf 'state\tufw\tavailable\tdisabled\tufw status\n'
		printf 'state\tnftables\tavailable\tdisabled\tnftables status\n'
		printf 'state\troot-encryption\tavailable\tunencrypted\tResolved root block-device ancestry only\n'
		printf 'state\tscreen-lock\tavailable\tenabled\tAutomatic screen locking from the shared power helper\n'
		if [ "$1" = snapshot ]; then
			printf 'state\tfilesystem-summary\tavailable\t1\tMounted real filesystems\n'
		else
			printf 'state\tfilesystem-summary\tpartial\tunknown\tMount monitoring is not ready; reload storage status to retry\n'
		fi
	fi
	printf 'action\tupdates-refresh\tunavailable\tdelegated\tupdates\tRefresh updates\tManaged update operations are not enabled in this build\n'
	printf 'action\tupdates-install-all\tunavailable\tdelegated\tupdates\tInstall all updates\tManaged update operations are not enabled\n'
	printf 'action\tupdates-cancel\tunavailable\tdelegated\tupdates\tCancel update\tNo managed update operation is active\n'
	printf 'action\ttimezone-set\tavailable\tdelegated\tregional\tChange timezone\tChange the system timezone\n'
	printf 'action\tntp-set\tavailable\tdelegated\tregional\tConfigure network time\tToggle network time synchronization\n'
	printf 'action\tlocale-set\tavailable\tdelegated\tregional\tChange locale\tChange the system locale\n'
	# D-3 (docs/UPSTREAM-SYNC.md#open-decisions): accounts-open/sources-open
	# are permanently unavailable on Arch; the stub reports exactly that
	# real shape so the pane's disabled buttons are exercised for real.
	printf 'action\taccounts-open\tunavailable\tdelegated\taccounts\tAccounts\tNo account-management tool is packaged for Arch\n'
	printf 'action\tpassword-open\tavailable\tdelegated\taccounts\tPassword\tChange your password\n'
	printf 'action\tprinters-open\tavailable\tdelegated\tprinters\tPrinters\tManage printers\n'
	printf 'action\tsources-open\tunavailable\tdelegated\tsources\tSoftware sources\tNo interactive repository editor is packaged for Arch\n'
	if [ "$1" != snapshot-core ]; then
		printf 'action\thealth-open\tavailable\tuser-session\tdiagnostics\tOpen system health\tOpen the existing health view and read-only scan\n'
	fi
	printf 'update\tlinux-cachyos;6.18.1-1;x86_64;core\tunknown\tinstallable\tlinux-cachyos\t6.18.1-1\tCachyOS kernel\n'
	printf 'package-change\tlinux-cachyos;6.18.1-1;x86_64;core\tupdate\tlinux-cachyos\t6.18.1-1\tCachyOS kernel\n'
	# One account record, matching the accounts-count=1 declared above --
	# without this the reconciliation cross-check (#259) would itself mark
	# the accounts domain malformed (a declared count with no matching rows).
	printf 'account\tu1000\tcurrent\tTest User\ttestuser\n'
	printf 'repository\tcore\tenabled\tArch Linux core repository\n'
	if [ "$1" = snapshot ]; then
		printf 'filesystem\t1\tavailable\t/dev/fixture\t/\text4\t1000000000\t200000000\t800000000\tFilesystem bytes at this read\n'
	fi
	printf 'complete\tsnapshot\n'
	;;
watch-updates)
	# Real bus signals are exercised for real by
	# tests/test-system-management.py's UpdateEventMonitorTests; this stub
	# only needs to prove the QML side coalesces through discoveryModel
	# correctly once a monitor reaches ready.
	printf 'update-event\tready\n'
	trap 'exit 0' TERM
	while :; do sleep 0.1; done
	;;
watch-regional)
	# Sync Sprint 1 S1-03 (#261): localeDiscoveryModel runs "watch-regional
	# locale" -- the "time" domain moved to its own watch-time command below
	# in S1-08 (#275), so this case now only ever sees locale.
	printf 'regional-event\tready\n'
	trap 'exit 0' TERM
	while :; do sleep 0.1; done
	;;
watch-time)
	# Sync Sprint 1 S1-08 (#275): a separate command and record prefix from
	# watch-regional, distinguishing an authenticated owner arrival
	# ("owner-arrived", uncertainty) from an actual timedate1 property
	# change ("changed", certainty). Report one arrival shortly after
	# readiness so timeReconciliationModel's real arrived()/requestPending()/
	# finish() path runs against a real Quickshell process, not just idle
	# defaults.
	printf 'time-event\tready\n'
	(
		sleep 0.2
		printf 'time-event\towner-arrived\n'
	) &
	trap 'exit 0' TERM
	while :; do sleep 0.1; done
	;;
watch-accounts)
	printf 'accounts-event\tready\n'
	trap 'exit 0' TERM
	while :; do sleep 0.1; done
	;;
watch-units)
	printf 'units-event\tready\n'
	trap 'exit 0' TERM
	while :; do sleep 0.1; done
	;;
watch-mounts)
	printf 'mount-monitor-ready\n'
	trap 'exit 0' TERM
	while :; do sleep 0.1; done
	;;
time-status)
	# Sync Sprint 1 S1-08 (#275): the finite reconciliation read
	# timeReconciliationModel dispatches after an owner arrival or a fresh
	# snapshot. Matches the snapshot's own timezone/ntp-enabled/ntp-synchronized
	# state exactly, so reconciliation settles quietly instead of treating
	# every read as a real configuration change.
	printf 'time-status-protocol\t1\t0\n'
	printf 'time\tEtc/UTC\tyes\tyes\tyes\n'
	printf 'complete\ttime-status\n'
	;;
ntp-sample)
	# Sync Sprint 1 S1-08 (#276): the periodic/on-demand sample read.
	printf 'ntp-sample-protocol\t1\t0\n'
	printf 'sample\tyes\tyes\n'
	printf 'complete\tntp-sample\n'
	;;
regional-choices)
	case "$2" in
	timezone)
		printf 'regional-choices-protocol\t1\t0\ttimezone\n'
		printf 'choice\tAmerica/Chicago\n'
		printf 'choice\tEtc/UTC\n'
		;;
	locale)
		printf 'regional-choices-protocol\t1\t0\tlocale\n'
		printf 'choice\tC\n'
		printf 'choice\ten_US.utf8\n'
		;;
	esac
	printf 'complete\tregional-choices\n'
	;;
regional-preview)
	# $2=action $3=argument -- fixed target/detail per action, matching
	# SystemRegionalPreflightProtocol.js's validPreview() exactly (target
	# must equal the argument for timezone-set/ntp-set, or its LANG= value
	# for locale-set).
	printf 'regional-preview-protocol\t1\t0\n'
	case "$2" in
	timezone-set) printf 'preview\ttimezone-set\t%s\t%s\tEtc/UTC\t%s\tSystem timezone\n' "$3" "$generation" "$3" ;;
	ntp-set) printf 'preview\tntp-set\t%s\t%s\tyes\t%s\tNetwork time synchronization setting\n' "$3" "$generation" "$3" ;;
	locale-set) printf 'preview\tlocale-set\t%s\t%s\tC\t%s\tLANGUAGE=C\n' "$3" "$generation" "${3#LANG=}" ;;
	esac
	printf 'complete\tregional-preview\n'
	;;
timezone-set | ntp-set | locale-set)
	# $2=value $3=generation -- a fixed succeeded operation stream, matching
	# SystemOperationProtocol.js's transition/audit/complete grammar exactly
	# (the same shape RegionalMutation's real journal-backed dispatch emits).
	action=$1
	kind=timezone
	[ "$action" = ntp-set ] && kind=ntp
	[ "$action" = locale-set ] && kind=locale
	printf 'system-management-protocol\t1\t0\n'
	printf 'operation\t%s\t%s\t%s\tpending\tunknown\tno\tStarting %s\n' "$opid" "$action" "$kind" "$action"
	printf 'operation\t%s\t%s\t%s\trunning\tunknown\tno\tDispatching %s\n' "$opid" "$action" "$kind" "$action"
	printf 'operation\t%s\t%s\t%s\tsucceeded\tunknown\tno\tRegional change verified\n' "$opid" "$action" "$kind"
	printf 'audit\t%s\t%s\t%s\tsucceeded\t2026-09-16T12:00:00Z\t2026-09-16T12:00:01Z\tRegional change verified\n' "$opid" "$action" "$kind"
	printf 'complete\toperation\n'
	;;
password-open | printers-open)
	action=$1
	printf 'system-management-protocol\t1\t0\n'
	printf 'operation\t%s\t%s\tdelegate\tpending\tunknown\tno\tStarting %s\n' "$opid" "$action" "$action"
	printf 'operation\t%s\t%s\tdelegate\trunning\tunknown\tno\tOpening %s\n' "$opid" "$action" "$action"
	printf 'operation\t%s\t%s\tdelegate\tsucceeded\tunknown\tno\tLaunch accepted; continue in the tool\n' "$opid" "$action"
	printf 'audit\t%s\t%s\tdelegate\tsucceeded\t2026-09-16T12:00:00Z\t2026-09-16T12:00:01Z\tLaunch accepted; continue in the tool\n' "$opid" "$action"
	printf 'complete\toperation\n'
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
	QT_ENABLE_HIGHDPI_SCALING=0 QT_SCALE_FACTOR=1 \
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

test_stage='validating the shared clock (#270): the stub timezone reached ClockModel'
# ClockModel.timezoneState is bound to systemManagementModel.nativeStates.timezone
# (config/quickshell/shell.qml); once the snapshot above loaded the stub's
# "Etc/UTC" timezone state, the clock must have observed it and produced real
# formatted text through the real Quickshell runtime -- this can't be unit
# tested directly (import Quickshell resolves only inside the real binary).
panel_clock=$(ipc settings clockPanelText)
settings_clock=$(ipc settings clockSettingsText)
# "ddd dd MMM - HH:mm", e.g. "Tue 16 Sep - 14:32".
case $panel_clock in
???" "[0-9][0-9]" "???" - "[0-9][0-9]":"[0-9][0-9]) ;;
*)
	printf 'clockPanelText did not match the expected "ddd dd MMM - HH:mm" shape: %s\n' "$panel_clock" >&2
	exit 1
	;;
esac
if [ -z "$settings_clock" ]; then
	printf 'clockSettingsText was empty\n' >&2
	exit 1
fi

test_stage='validating protocol minor 1 native content (#259)'
# The stub's four native providers, five native states, one account and one
# repository record all parse and reconcile cleanly -- proving compose
# cumulative native discovery (#259) is wired end to end, not just that the
# update domain still works.
[ "$(ipc settings systemManagementNativeProviderStatus regional)" = available ]
[ "$(ipc settings systemManagementNativeProviderStatus accounts)" = available ]
[ "$(ipc settings systemManagementNativeProviderStatus printers)" = available ]
[ "$(ipc settings systemManagementNativeProviderStatus sources)" = available ]
[ "$(ipc settings systemManagementNativeStateValue timezone)" = 'available:Etc/UTC' ]
[ "$(ipc settings systemManagementNativeStateValue ntp-enabled)" = 'available:yes' ]
[ "$(ipc settings systemManagementNativeStateValue locale)" = 'available:C' ]
[ "$(ipc settings systemManagementNativeStateValue accounts-count)" = 'available:1' ]
[ "$(ipc settings systemManagementNativeStateValue cups-service)" = 'available:stopped' ]
[ "$(ipc settings systemManagementAccountsCount)" -eq 1 ]
[ "$(ipc settings systemManagementRepositoriesCount)" -eq 1 ]

test_stage='validating protocol minor 2 information/storage/security content (S2-05 #286)'
# The stub's information/storage/security block and one filesystem record
# all parse cleanly at minor 2 -- proving the QML side actually activates
# the cumulative minor once storage's own watch-mounts subscription is
# ready, not just that the Python provider can emit it.
[ "$(ipc settings systemManagementNativeProviderStatus information)" = available ]
[ "$(ipc settings systemManagementNativeProviderStatus storage)" = available ]
[ "$(ipc settings systemManagementNativeProviderStatus security)" = available ]
[ "$(ipc settings systemManagementNativeProviderStatus diagnostics)" = available ]
[ "$(ipc settings systemManagementNativeStateValue os-name)" = 'available:Fixture Linux' ]
[ "$(ipc settings systemManagementNativeStateValue selinux)" = 'available:disabled' ]
[ "$(ipc settings systemManagementNativeStateValue firewalld)" = 'available:disabled' ]
[ "$(ipc settings systemManagementNativeStateValue ufw)" = 'available:disabled' ]
[ "$(ipc settings systemManagementNativeStateValue nftables)" = 'available:disabled' ]
[ "$(ipc settings systemManagementNativeStateValue root-encryption)" = 'available:unencrypted' ]
[ "$(ipc settings systemManagementNativeStateValue screen-lock)" = 'available:enabled' ]
[ "$(ipc settings systemManagementNativeStateValue filesystem-summary)" = 'available:1' ]
[ "$(ipc settings systemManagementFilesystemsCount)" -eq 1 ]

test_stage='validating the six native discovery domains reach ready (#261, extended S2-05 #286)'
# openSettings() opened all discovery models together (#261); the update one
# already proved ready above via the loaded snapshot -- these six are new
# (storage and security joined in S2-05). Each one's own stub watch-* command
# (added alongside these assertions) must actually be reached, not just
# tolerated as "failed" by discoveryReady()'s deliberately permissive batch
# gate.
for domain in time locale accounts printers storage security; do
	native_discovery_status=
	i=0
	while [ "$i" -lt 100 ]; do
		native_discovery_status=$(ipc settings systemManagementNativeDiscoveryStatus "$domain" 2>/dev/null || true)
		case $native_discovery_status in idle:ready) break ;; esac
		i=$((i + 1))
		sleep 0.05
	done
	if [ "$native_discovery_status" != idle:ready ]; then
		printf '%s discovery did not reach idle:ready: %s\n' "$domain" "$native_discovery_status" >&2
		exit 1
	fi
done

test_stage='sampling idle CPU with all six watch-* domains subscribed (S2-07 qualification)'
# Every domain above (updates, time, locale, accounts, printers -- plus
# storage/security, S2-05) is now idle:ready: its own bounded watch-*
# subprocess is live and subscribed, but nothing is polling. Matches Phase
# 5's own closed-shell CPU methodology (utime+stime delta over a fixed
# window), applied here to Quickshell's own process while every discovery
# domain's subscription is active and settled, not just closed.
clock_ticks=$(getconf CLK_TCK)
cpu_before=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
sleep 2
cpu_after=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
cpu_percent=$(awk -v delta="$((cpu_after - cpu_before))" -v ticks="$clock_ticks" \
	'BEGIN { printf "%.2f", (delta * 100) / (ticks * 2) }')
if ! awk -v cpu="$cpu_percent" 'BEGIN { exit !(cpu < 10.0) }'; then
	printf 'Idle CPU with all six watch-* domains subscribed exceeded budget: %s%%\n' "$cpu_percent" >&2
	exit 1
fi
printf 'Idle CPU with all six watch-* domains subscribed: %s%%\n' "$cpu_percent"

test_stage='validating time reconciliation settles after the stubbed owner arrival (S1-08 #275)'
# watch-time's own stub reports one "owner-arrived" record shortly after
# readiness (uncertainty, not a confirmed change); timeReconciliationModel
# must reconcile it with a real time-status read through the real Quickshell
# runtime and Process/StdioCollector lifecycle, then release back to idle --
# this can't be unit tested (import Quickshell resolves only in the real
# binary). The initial post-snapshot reconciliation cycle can still be
# in flight too, so this tolerates settling from either trigger.
reconciliation_blocked=
i=0
while [ "$i" -lt 200 ]; do
	reconciliation_blocked=$(ipc settings systemManagementTimeReconciliationBlocked 2>/dev/null || true)
	[ "$reconciliation_blocked" = false ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$reconciliation_blocked" != false ]; then
	printf 'Time reconciliation never settled after the stubbed owner arrival: %s (%s)\n' \
		"$reconciliation_blocked" "$(ipc settings systemManagementTimeReconciliationDetail)" >&2
	exit 1
fi
[ "$(ipc settings systemManagementNativeStateValue ntp-synchronized)" = 'available:yes' ]

test_stage='validating an on-demand network time sample settles cleanly (S1-08 #276)'
ipc settings systemManagementTimeSampleNow >/dev/null
reconciliation_blocked=
i=0
while [ "$i" -lt 200 ]; do
	reconciliation_blocked=$(ipc settings systemManagementTimeReconciliationBlocked 2>/dev/null || true)
	[ "$reconciliation_blocked" = false ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$reconciliation_blocked" != false ]; then
	printf 'On-demand network time sample never settled: %s (%s)\n' \
		"$reconciliation_blocked" "$(ipc settings systemManagementTimeReconciliationDetail)" >&2
	exit 1
fi
[ "$(ipc settings systemManagementNativeStateValue ntp-synchronized)" = 'available:yes' ]

test_stage='validating the Sync Phase 7 operation surface mounted cleanly'
# The stub reports recovery as unsupported and both update actions as
# unavailable, so operationModel never has evidence to recover and
# SystemUpdateControls' prepare buttons stay disabled -- this stub cannot
# exercise a live confirm/dispatch/watch/cancel/ack cycle (that needs a
# PackageKit-transaction-capable stub, tracked in docs/SYNC-P7-OPERATION-SURFACE.md).
# What this does prove: SystemOperationModel and SystemUpdateControls mount
# and settle to their idle defaults against a real Quickshell process,
# without a binding error or crash.
[ "$(ipc settings systemManagementOperationState)" = idle ]
[ "$(ipc settings systemManagementOperationResult)" = '' ]

# The snapshot only loaded because the discovery monitor reached ready and
# coalesced the read through it (SystemManagementModel no longer fires a
# read directly on open) -- confirm the monitor itself is actually up, not
# just that a read eventually happened some other way.
discovery_status=$(ipc settings systemManagementDiscoveryStatus)
case $discovery_status in
idle:ready) ;;
*)
	printf 'Discovery monitor did not reach idle:ready: %s\n' "$discovery_status" >&2
	exit 1
	;;
esac

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

test_stage='validating health-open closes Settings and reaches the existing dwm-system-health view (S2-05 #286)'
# openHealth() itself owns the healthModel-null/settingsVisible/action-status
# checks, already unit-verifiable, but reaching the real, wired
# systemHealthModel instance and its onHealthOpened: settingsModel.close()
# side effect through shell.qml can only be proven against the real
# Quickshell runtime.
ipc settings open >/dev/null
ipc settings select system >/dev/null
snapshot_state=
i=0
while [ "$i" -lt 100 ]; do
	snapshot_state=$(ipc settings systemManagementSnapshotState 2>/dev/null || true)
	[ "$snapshot_state" = loaded ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$snapshot_state" = loaded ]
[ "$(ipc settings systemManagementOpenHealth)" = true ]
if [ "$(ipc settings systemManagementSettingsVisible)" != false ]; then
	printf 'systemManagementModel.settingsVisible stayed true after systemManagementOpenHealth\n' >&2
	exit 1
fi

test_stage='validating no watch-updates monitor survives the closed window'
# Unlike the bounded snapshot fetch (checkedCommand's orphaned
# command-substitution child makes "did the process exit" an unreliable
# proxy -- see above), the stub's watch-updates only exits on SIGTERM, so
# this actually proves stopMonitor()'s signal(15)-then-signal(9) reaches the
# real long-running process rather than just resetting QML-side state.
i=0
still_running=1
while [ "$i" -lt 30 ]; do
	if ! pgrep -f "$work.*dwm-system-management watch-updates" >/dev/null 2>&1; then
		still_running=0
		break
	fi
	i=$((i + 1))
	sleep 0.1
done
if [ "$still_running" -eq 1 ]; then
	printf 'dwm-system-management watch-updates survived the Settings window closing\n' >&2
	exit 1
fi

# Sync Phase 9 follow-up (docs/SYNC-P9-REGIONAL-MUTATION.md §5.7): a full
# preview -> confirm -> dispatch -> verified-result cycle, and delegated-
# launch availability matching D-3 -- run last, after every existing
# assertion above, since operationModel/discoveryModel are shared with the
# update-confirm surface those already checked at their own idle baseline.
test_stage='reopening Settings for the regional preview/confirm cycle'
ipc settings open >/dev/null
ipc settings select system >/dev/null
[ "$(ipc settings systemManagementSettingsVisible)" = true ]

test_stage='loading the timezone choices catalog (#268: prepare() requires a loaded, matching catalog)'
[ "$(ipc settings systemManagementRegionalRequestChoices timezone)" = true ]
timezone_choices=0
i=0
while [ "$i" -lt 100 ]; do
	timezone_choices=$(ipc settings systemManagementRegionalChoicesCount timezone 2>/dev/null || echo 0)
	[ "$timezone_choices" -gt 0 ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$timezone_choices" -eq 0 ]; then
	printf 'Timezone choices catalog never loaded\n' >&2
	exit 1
fi

test_stage='validating the regional confirmation step itself (#268): prepare then discard'
# Regional preview/confirm now lives on SystemRegionalSettingsModel, the
# same split S1-04 already gave delegated actions -- prove discard() clears
# a pending preview without ever dispatching, before proving confirm() does.
if [ "$(ipc settings systemManagementRegionalPreview timezone-set America/Chicago)" != true ]; then
	printf 'systemManagementRegionalPreview(timezone-set, America/Chicago) did not accept the read\n' >&2
	exit 1
fi
discard_preview=
i=0
while [ "$i" -lt 100 ]; do
	discard_preview=$(ipc settings systemManagementRegionalPreviewResult 2>/dev/null || true)
	[ -n "$discard_preview" ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$discard_preview" != 'timezone-set:Etc/UTC:America/Chicago' ]; then
	printf 'Regional preview (discard path) did not report the expected current/target: %s\n' "$discard_preview" >&2
	exit 1
fi
ipc settings systemManagementRegionalDiscard >/dev/null
discard_result=$(ipc settings systemManagementRegionalPreviewResult 2>/dev/null || true)
if [ -n "$discard_result" ]; then
	printf 'systemManagementRegionalDiscard did not clear the pending preview: %s\n' "$discard_result" >&2
	exit 1
fi
if [ "$(ipc settings systemManagementOperationResult)" = 'timezone-set:succeeded' ]; then
	printf 'discardRegional() dispatched an operation instead of discarding it\n' >&2
	exit 1
fi

test_stage='reloading timezone choices (discard()/invalidate("") also clears the loaded catalog)'
[ "$(ipc settings systemManagementRegionalRequestChoices timezone)" = true ]
timezone_choices=0
i=0
while [ "$i" -lt 100 ]; do
	timezone_choices=$(ipc settings systemManagementRegionalChoicesCount timezone 2>/dev/null || echo 0)
	[ "$timezone_choices" -gt 0 ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$timezone_choices" -eq 0 ]; then
	printf 'Timezone choices catalog did not reload after discard\n' >&2
	exit 1
fi

test_stage='requesting a regional preview'
[ "$(ipc settings systemManagementRegionalPreview timezone-set America/Chicago)" = true ]

preview_result=
i=0
while [ "$i" -lt 100 ]; do
	preview_result=$(ipc settings systemManagementRegionalPreviewResult 2>/dev/null || true)
	[ -n "$preview_result" ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$preview_result" != 'timezone-set:Etc/UTC:America/Chicago' ]; then
	printf 'Regional preview did not report the expected current/target: %s\n' "$preview_result" >&2
	exit 1
fi

test_stage='confirming and dispatching the regional change'
[ "$(ipc settings systemManagementRegionalConfirm)" = true ]

operation_result=
i=0
while [ "$i" -lt 100 ]; do
	operation_result=$(ipc settings systemManagementOperationResult 2>/dev/null || true)
	[ "$operation_result" = 'timezone-set:succeeded' ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$operation_result" != 'timezone-set:succeeded' ]; then
	printf 'Regional dispatch did not reach a verified succeeded result: %s\n' "$operation_result" >&2
	exit 1
fi

test_stage='validating the delegated confirmation step itself (#266): prepare then discard'
# Sync Sprint 1 S1-04 (#266): delegated actions no longer dispatch on the
# first click -- prepareDelegate() must show a pending confirmation that
# discardDelegate() can retire without ever starting an operation. Retry
# preparation to ride out any transient busy-ness left over from the
# earlier regional dispatch (operationModel is shared state).
prepared=false
i=0
while [ "$i" -lt 100 ]; do
	if [ "$(ipc settings systemManagementPrepareDelegate printers-open)" = true ]; then
		prepared=true
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if [ "$prepared" != true ]; then
	printf 'systemManagementPrepareDelegate(printers-open) never became preparable\n' >&2
	exit 1
fi
if [ "$(ipc settings systemManagementNativeConfirmationPending)" != true ]; then
	printf 'prepareDelegate(printers-open) did not leave a pending confirmation\n' >&2
	exit 1
fi
ipc settings systemManagementDiscardDelegate >/dev/null
if [ "$(ipc settings systemManagementNativeConfirmationPending)" != false ]; then
	printf 'discardDelegate() did not clear the pending confirmation\n' >&2
	exit 1
fi
if [ "$(ipc settings systemManagementOperationResult)" = 'printers-open:succeeded' ]; then
	printf 'discardDelegate() dispatched an operation instead of discarding it\n' >&2
	exit 1
fi

test_stage='validating the delegated confirmation step itself: prepare then confirm'
prepared=false
i=0
while [ "$i" -lt 100 ]; do
	if [ "$(ipc settings systemManagementPrepareDelegate printers-open)" = true ]; then
		prepared=true
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if [ "$prepared" != true ]; then
	printf 'systemManagementPrepareDelegate(printers-open) never became preparable (second attempt)\n' >&2
	exit 1
fi
if [ "$(ipc settings systemManagementConfirmDelegate)" != true ]; then
	printf 'systemManagementConfirmDelegate() did not dispatch a prepared confirmation\n' >&2
	exit 1
fi

test_stage='validating that accounts-open is D-3 unsupported, not merely busy'
# accounts-open must never reach a pending confirmation at all -- D-3 keeps
# it permanently unsupported, so prepareDelegate() itself must refuse it and
# report the helper's own reason text, matching delegated_command()'s exact
# "No account-management tool is packaged for Arch" message.
if [ "$(ipc settings systemManagementPrepareDelegate accounts-open)" != false ]; then
	printf 'systemManagementPrepareDelegate(accounts-open) prepared despite D-3\n' >&2
	exit 1
fi
if [ "$(ipc settings systemManagementNativeConfirmationPending)" != false ]; then
	printf 'prepareDelegate(accounts-open) left a pending confirmation despite being refused\n' >&2
	exit 1
fi
case $(ipc settings systemManagementNativeConfirmationMessage) in
*"No account-management tool is packaged for Arch"*) ;;
*)
	printf 'prepareDelegate(accounts-open) did not surface the D-3 reason text\n' >&2
	exit 1
	;;
esac

test_stage='validating delegated-launch availability matches D-3'
# printers-open is available against the stub; accounts-open is
# permanently unsupported (D-3) regardless of timing -- retry printers-open
# alone to ride out any transient busy-ness from the timezone-set dispatch
# settling (operationModel is shared state), then re-check accounts-open
# once things are quiet to prove its "false" is D-3, not leftover busy-ness.
launched=false
i=0
while [ "$i" -lt 100 ]; do
	if [ "$(ipc settings systemManagementDelegatedLaunch printers-open)" = true ]; then
		launched=true
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if [ "$launched" != true ]; then
	printf 'systemManagementDelegatedLaunch(printers-open) never became dispatchable\n' >&2
	exit 1
fi

delegated_result=
i=0
while [ "$i" -lt 100 ]; do
	delegated_result=$(ipc settings systemManagementOperationResult 2>/dev/null || true)
	[ "$delegated_result" = 'printers-open:succeeded' ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$delegated_result" != 'printers-open:succeeded' ]; then
	printf 'Delegated launch did not reach a verified succeeded result: %s\n' "$delegated_result" >&2
	exit 1
fi

if [ "$(ipc settings systemManagementDelegatedLaunch accounts-open)" != false ]; then
	printf 'systemManagementDelegatedLaunch(accounts-open) dispatched despite D-3\n' >&2
	exit 1
fi

test_stage='running the regional preflight owner lifecycle harness'
# Sync Sprint 1 S1-08 (#274): SystemRegionalPreflightModel.qml is a Scope
# importing Quickshell.Io -- it cannot be instantiated under bare
# qmltestrunner (verified: `module "qs.systemmanagement" is not installed`
# outside a real Quickshell process), so its full request/cancel/timeout/
# overflow lifecycle is exercised here by spawning quickshell directly
# against the bespoke tests/qml/SystemRegionalPreflightOwner.qml harness,
# the same mechanism upstream uses. This closes the coverage gap Sync
# Phase 9 deferred.
mkdir -p "$work/regional-preflight-owner" "$work/preflight-data/lyona/scripts" "$work/preflight-empty-path"
mkdir -p "$work/preflight-shell-path" "$work/preflight-missing-data"
ln -s "$(command -v sh)" "$work/preflight-shell-path/sh"
cp -a "$repo/config/quickshell/core" "$repo/config/quickshell/systemmanagement" "$work/regional-preflight-owner/"
cp "$repo/tests/qml/SystemRegionalPreflightOwner.qml" "$work/regional-preflight-owner/shell.qml"
preflight_helper="$work/preflight-data/lyona/scripts/dwm-system-management"
cp "$repo/tests/fixtures/system-regional-preflight-provider.py" "$preflight_helper"
chmod +x "$preflight_helper"
preflight_quickshell=$(command -v quickshell)
for preflight_mode in regional time-status ntp-sample; do
	for preflight_scenario in success typed-error unsupported-error wrong-exit protocol-exit-127 malformed truncated stdout-overflow stderr-overflow \
		close kill-close close-stdout-overflow close-stderr-overflow timeout cancel-queued cancel-claim close-result failed-start missing-helper; do
		preflight_directory="$work/preflight-$preflight_mode-$preflight_scenario"
		mkdir -p "$preflight_directory"
		preflight_path=$PATH
		preflight_data="$work/preflight-data"
		[ "$preflight_scenario" != failed-start ] || preflight_path="$work/preflight-empty-path"
		if [ "$preflight_scenario" = missing-helper ]; then
			preflight_path="$work/preflight-shell-path"
			preflight_data="$work/preflight-missing-data"
		fi
		timeout --foreground --kill-after=2s 45s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
			XDG_DATA_HOME="$preflight_data" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= PATH="$preflight_path" \
			DWM_PREFLIGHT_DIRECTORY="$preflight_directory" DWM_PREFLIGHT_SCENARIO="$preflight_scenario" DWM_PREFLIGHT_MODE="$preflight_mode" \
			"$preflight_quickshell" --no-duplicate --path "$work/regional-preflight-owner/shell.qml" \
			>"$preflight_directory/output.log" 2>&1 &
		preflight_quickshell_pid=$!
		preflight_status=0
		wait "$preflight_quickshell_pid" || preflight_status=$?
		preflight_quickshell_pid=
		case "$preflight_scenario" in
		success)
			preflight_calls=8
			[ "$preflight_mode" = regional ] || preflight_calls=2
			;;
		close | kill-close | close-stdout-overflow | close-stderr-overflow | timeout | close-result) preflight_calls=2 ;;
		failed-start | missing-helper) preflight_calls=0 ;;
		*) preflight_calls=1 ;;
		esac
		preflight_actual=$(sed -n '1p' "$preflight_directory/calls" 2>/dev/null || true)
		if [ "$preflight_status" -ne 0 ] || ! grep -F 'Regional preflight owner tests: PASS' "$preflight_directory/output.log" ||
			grep -Fq 'Regional preflight owner FAILED:' "$preflight_directory/output.log" ||
			[ "${preflight_actual:-0}" != "$preflight_calls" ] || [ -e "$preflight_directory/invalid-arguments" ] ||
			[ -e "$preflight_directory/overlap" ] || pgrep -f "$preflight_helper" >/dev/null 2>&1; then
			cat "$preflight_directory/output.log" >&2
			exit 1
		fi
	done
done

test_stage='validating the primary session survived the preflight owner harness'
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
