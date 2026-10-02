#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 12 S12-15: dwm-system-health-root, the System Health root helper,
# accepts only its two requests with checked arguments, runs only a trusted
# installed dwm-system-health, and refuses any copy that is not its trusted
# installed self. Root-only and container-only, like
# tests/test-settings-display-security.sh: it installs into a prefix under /opt.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

[[ ${DWM_SECURITY_CONTAINER:-0} == 1 ]] || {
	printf 'SKIP: privileged system-health helper security test is container-only\n'
	exit 77
}
[[ -e /.dockerenv || -e /run/.containerenv ]] || {
	printf 'Refusing to modify installed paths outside a disposable container\n' >&2
	exit 1
}
[[ $EUID == 0 ]] || {
	printf 'The container security test must run as root\n' >&2
	exit 1
}

work=$(mktemp -d)
custom_prefix=$(mktemp -d /opt/lyona-health-security-test.XXXXXX)
chmod 0755 "$custom_prefix"
cleanup() {
	rm -rf "$work" "$custom_prefix"
}
trap cleanup EXIT
mkdir -p "$custom_prefix/bin" "$custom_prefix/libexec/lyona"

installed=$custom_prefix/libexec/lyona/dwm-system-health-root
health=$custom_prefix/bin/dwm-system-health
record=$work/ran
sed "s|@PREFIX@|$custom_prefix|g" "$repo/scripts/dwm-system-health-root" |
	install -o root -g root -m 0755 /dev/stdin "$installed"
# A stand-in for the installed dwm-system-health: it records what it was asked
# to run, and the environment it was run with.
# shellcheck disable=SC2016 # the stub's own expansions, written literally
printf '#!/bin/sh\nprintf "%%s|HOME=%%s|PKEXEC_UID=%%s\\n" "$*" "$HOME" "${PKEXEC_UID:-}" >>%s\n' \
	"$record" | install -o root -g root -m 0755 /dev/stdin "$health"

refuses() { # LABEL EXPECTED-ERROR ENV-AND-COMMAND...
	local label=$1 expected=$2
	shift 2
	: >"$record"
	if "$@" 2>"$work/refused.err"; then
		fail "$label was accepted"
	fi
	grep -Fq -- "$expected" "$work/refused.err" ||
		fail "$label: expected '$expected', got: $(cat "$work/refused.err")"
	[[ ! -s $record ]] || fail "$label ran dwm-system-health: $(cat "$record")"
}

# Only the trusted installed copy, run through polkit.
refuses 'the repository copy' 'trusted installed path' \
	env PKEXEC_UID=1000 "$repo/scripts/dwm-system-health-root" scan-system
refuses 'a run without polkit' 'must run through polkit as root' "$installed" scan-system
chmod 0775 "$installed"
refuses 'a writable installed helper' 'trusted root-owned executable' \
	env PKEXEC_UID=1000 "$installed" scan-system
chmod 0755 "$installed"
chmod 0775 "$health"
refuses 'an untrusted dwm-system-health' 'trusted dwm-system-health is unavailable' \
	env PKEXEC_UID=1000 "$installed" scan-system
chmod 0755 "$health"

# Only the two requests, with checked arguments.
refuses 'an unknown request' 'usage:' env PKEXEC_UID=1000 "$installed" scan-user
refuses 'scan-system with an argument' 'takes no arguments' \
	env PKEXEC_UID=1000 "$installed" scan-system extra
refuses 'an unknown repair' 'unsupported system repair' \
	env PKEXEC_UID=1000 "$installed" repair-system 'restart-networkmanager;touch /tmp/x'
refuses 'an unknown service verb' 'unsupported system repair' \
	env PKEXEC_UID=1000 "$installed" repair-system 'manage-system-service|kill|sshd.service'
refuses 'a unit with a space' 'unsupported system repair' \
	env PKEXEC_UID=1000 "$installed" repair-system 'manage-system-service|restart|a b.service'
refuses 'a unit that is not a service' 'unsupported system repair' \
	env PKEXEC_UID=1000 "$installed" repair-system 'manage-system-service|restart|sshd.socket'
refuses 'an extra field' 'unsupported system repair' \
	env PKEXEC_UID=1000 "$installed" repair-system 'manage-system-service|restart|sshd.service|x'
refuses 'a newline' 'invalid repair action' \
	env PKEXEC_UID=1000 "$installed" repair-system $'restart-bluetooth\nrestart-bluetooth'

# Accepted requests run the installed dwm-system-health, with a clean
# environment: no PKEXEC_UID, and root's HOME.
: >"$record"
env PKEXEC_UID=1000 HOME=/home/someone "$installed" scan-system
env PKEXEC_UID=1000 "$installed" repair-system 'manage-system-service|restart|systemd-fsck@dev-disk-by\x2duuid-1.service'
env PKEXEC_UID=1000 "$installed" repair-system repair-time-sync
assert_equals "scan-system|HOME=/root|PKEXEC_UID=
repair-system manage-system-service|restart|systemd-fsck@dev-disk-by\\x2duuid-1.service|HOME=/root|PKEXEC_UID=
repair-system repair-time-sync|HOME=/root|PKEXEC_UID=" "$(cat "$record")" 'the accepted requests'

printf 'Privileged system-health helper trust and request checks: PASS\n'
