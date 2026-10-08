#!/usr/bin/env bash
set -euo pipefail

# #258: install.sh enables systemd-timesyncd when nothing else keeps the clock.
# Another NTP service, enabled or running, is kept, as is a masked
# systemd-timesyncd; a second run changes nothing. time_sync_state and
# configure_time_sync are extracted from install.sh and run against stubs:
# systemctl answers from STUB_* variables, and sudo only logs.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

{
	sed -n '/^time_sync_marker() {$/,/^}$/p' "$repo/install.sh"
	sed -n '/^time_sync_state() {$/,/^}$/p' "$repo/install.sh"
	sed -n '/^mark_time_sync() {$/,/^}$/p' "$repo/install.sh"
	sed -n '/^configure_time_sync() {$/,/^}$/p' "$repo/install.sh"
} >"$work/time-sync.sh"
grep -q '^time_sync_state() {$' "$work/time-sync.sh" || fail 'time_sync_state not found in install.sh'
grep -q '^configure_time_sync() {$' "$work/time-sync.sh" || fail 'configure_time_sync not found in install.sh'
grep -q '^mark_time_sync() {$' "$work/time-sync.sh" || fail 'mark_time_sync not found in install.sh'
# The marker that records lyona has seen time sync on (#268): STUB_MARKED=1
# makes it exist; sudo install only logs.
marker=$work/var/lib/lyona/time-sync

# STUB_MARKED: the marker exists. STUB_ENABLED, STUB_STATIC and STUB_ACTIVE: the units that are enabled, static
# or running. STUB_CHROOT: running in the image install's chroot.
# STUB_TIMESYNCD: what is-enabled prints for systemd-timesyncd, as systemd 262
# does (not-found, with exit 4, when the unit does not exist). STUB_ENABLE_FAILS:
# sudo systemctl enable fails.
# The variables are read, and the stubs called, by the extracted functions.
# shellcheck disable=SC2034,SC2329
run_case() {
	: >"$work/out.log"
	(
		ok() { printf 'ok %s\n' "$1" >>"$work/out.log"; }
		info() { printf 'info %s\n' "$1" >>"$work/out.log"; }
		warn() { printf 'warn %s\n' "$1" >>"$work/out.log"; }
		systemctl() {
			local quiet=false
			[[ $2 != --quiet ]] || {
				quiet=true
				set -- "$1" "$3"
			}
			case $1 in
			is-enabled)
				if [[ $2 == systemd-timesyncd.service ]]; then
					$quiet || printf '%s\n' "$STUB_TIMESYNCD"
					[[ $STUB_TIMESYNCD != not-found ]] || return 4
					[[ $STUB_TIMESYNCD == enabled* ]]
				elif [[ " ${STUB_ENABLED:-} " == *" $2 "* ]]; then
					$quiet || printf 'enabled\n'
				elif [[ " ${STUB_STATIC:-} " == *" $2 "* ]]; then
					# static exits 0 as well, though nothing starts it at boot.
					$quiet || printf 'static\n'
				else
					$quiet || printf 'disabled\n'
					return 1
				fi
				;;
			is-active) [[ " ${STUB_ACTIVE:-} " == *" $2 "* ]] ;;
			*) return 2 ;;
			esac
		}
		systemd-detect-virt() { [[ ${STUB_CHROOT:-0} == 1 ]]; }
		sudo() {
			printf 'sudo %s\n' "$*" >>"$work/out.log"
			[[ ${STUB_ENABLE_FAILS:-0} != 1 ]]
		}
		export LYONA_TIME_SYNC_MARKER=$marker
		rm -f "$marker"
		if [[ ${STUB_MARKED:-0} == 1 ]]; then
			mkdir -p "${marker%/*}"
			: >"$marker"
		fi
		# shellcheck disable=SC1091 # generated above
		. "$work/time-sync.sh"
		configure_time_sync
	)
}
expect() { # LOG-LINE MESSAGE
	grep -Fxq -- "$1" "$work/out.log" || {
		lyona_show_file "$work/out.log"
		fail "$2"
	}
}
no_sudo() { # MESSAGE
	if grep -q '^sudo ' "$work/out.log"; then
		lyona_show_file "$work/out.log"
		fail "$1"
	fi
}

# Off: enabled and started, and said so.
STUB_TIMESYNCD=disabled run_case
expect 'info Enabling time synchronization (systemd-timesyncd)...' 'enabling it is not announced'
expect 'sudo systemctl enable --now systemd-timesyncd.service' 'systemd-timesyncd was not enabled and started'
expect 'ok systemd-timesyncd enabled and started.' 'enabling it is not reported'
expect "sudo install -D -m 0644 /dev/null $marker" 'enabling it did not record the marker'

# Already enabled and running (a second run): nothing changes.
STUB_TIMESYNCD=enabled STUB_ACTIVE=systemd-timesyncd.service STUB_MARKED=1 run_case
expect 'ok Time synchronization (systemd-timesyncd) is already enabled.' 'an enabled systemd-timesyncd is not reported'
no_sudo 'an enabled systemd-timesyncd was enabled again'

# Enabled before lyona recorded it (an install from before #268, or the image's
# archinstall): only the marker is written.
STUB_TIMESYNCD=enabled STUB_ACTIVE=systemd-timesyncd.service run_case
expect "sudo install -D -m 0644 /dev/null $marker" 'an enabled systemd-timesyncd did not record the marker'
if grep -q '^sudo systemctl' "$work/out.log"; then
	fail 'recording the marker changed the service'
fi

# Turned off after lyona set it up (Settings, or timedatectl set-ntp false):
# left off, and said so (#268).
STUB_TIMESYNCD=disabled STUB_MARKED=1 run_case
expect 'info Time synchronization is off: it was turned off after lyona set it up, so it stays off (turn it on in Settings or with timedatectl set-ntp true).' \
	'time sync the user turned off is not reported'
no_sudo 'time sync the user turned off was turned back on'

# Enabled but not running: started, and said so.
STUB_TIMESYNCD=enabled run_case
expect 'sudo systemctl start systemd-timesyncd.service' 'an enabled, stopped systemd-timesyncd was not started'
expect 'ok systemd-timesyncd started.' 'starting it is not reported'
STUB_TIMESYNCD=enabled STUB_ENABLE_FAILS=1 run_case || fail 'a failed start stopped the install'
expect 'warn systemd-timesyncd could not be started; it starts at the next boot.' 'a failed start is not warned about'

# Enabled, in the image install's chroot (archinstall's "ntp": true), where
# systemctl start is ignored: nothing is run, and it starts at boot.
STUB_TIMESYNCD=enabled STUB_CHROOT=1 run_case
expect 'ok Time synchronization (systemd-timesyncd) is enabled; it starts at boot.' 'the chroot case is not reported'
if grep -q '^sudo systemctl' "$work/out.log"; then
	fail 'systemd-timesyncd was started in a chroot'
fi
expect "sudo install -D -m 0644 /dev/null $marker" 'the image install did not record the marker'

# Another NTP service, enabled or only running, is kept, and timesyncd is not
# enabled beside it.
for unit in chronyd.service ntpd.service openntpd.service; do
	STUB_TIMESYNCD=disabled STUB_ENABLED=$unit run_case
	expect "ok Time synchronization: keeping $unit." "an enabled $unit was not kept"
	no_sudo "systemd-timesyncd was enabled beside $unit"
done
# A static unit is not enabled to start at boot: timesyncd is enabled instead.
STUB_TIMESYNCD=disabled STUB_STATIC=chronyd.service run_case
expect 'sudo systemctl enable --now systemd-timesyncd.service' 'a static chronyd counted as keeping the clock'
STUB_TIMESYNCD=disabled STUB_ACTIVE=chronyd.service run_case
expect 'ok Time synchronization: keeping chronyd.service.' 'a running chronyd was not kept'
no_sudo 'systemd-timesyncd was enabled beside a running chronyd'

# Masked: the user's choice, left alone.
STUB_TIMESYNCD=masked run_case
expect 'info systemd-timesyncd is masked, so time synchronization was left off (sudo systemctl unmask systemd-timesyncd to use it).' \
	'a masked systemd-timesyncd is not reported'
no_sudo 'a masked systemd-timesyncd was changed'

# Missing: a warning, nothing run.
STUB_TIMESYNCD=not-found run_case
expect 'warn systemd-timesyncd was not found, so time synchronization was left off.' 'a missing systemd-timesyncd is not warned about'
no_sudo 'a missing systemd-timesyncd was enabled'

# Enabling fails: a warning, and the install goes on.
STUB_TIMESYNCD=disabled STUB_ENABLE_FAILS=1 run_case || fail 'a failed enable stopped the install'
expect 'warn systemd-timesyncd could not be enabled; turn time synchronization on in Settings or with timedatectl set-ntp true.' \
	'a failed enable is not warned about'

# The summary says when a re-run leaves it off.
grep -Fq "turned-off) printf '  Time synchronization: turned off since lyona set it up, left off" "$repo/install.sh" ||
	fail 'the install summary does not cover time sync the user turned off'

# install.sh runs it, in every profile, as its own timed step.
grep -Fxq 'step_timer "Time synchronization"' "$repo/install.sh" || fail 'install.sh has no Time synchronization step'
grep -Fxq 'configure_time_sync' "$repo/install.sh" || fail 'install.sh does not call configure_time_sync at the top level'

printf 'Time synchronization default: PASS\n'
