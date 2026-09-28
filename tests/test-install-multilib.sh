#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 12 S12-11 item 1: enabling multilib must not leave a partial upgrade.
# configure_arch_multilib_repository is extracted from install.sh and run against
# stubs: sudo only logs (nothing touches the real pacman.conf), and multilib reads
# as disabled until the sed has run. The databases are refreshed with the matching
# upgrade (pacman -Syu), never with -Sy alone, which Arch does not support before
# installing packages.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

sed -n '/^configure_arch_multilib_repository() {$/,/^}$/p' "$repo/install.sh" >"$work/multilib.sh"
[[ -s $work/multilib.sh ]] || fail 'configure_arch_multilib_repository not found in install.sh'

# The variables are read, and the stubs called, by the extracted function it sources.
# shellcheck disable=SC2034,SC2329
run_case() {
	: >"$work/sudo.log"
	rm -f "$work/enabled"
	(
		DISTRO_ID=arch INSTALL_PROFILE=full ARCH=x86_64 ARCH_GAMING_REPOS_APPROVED=true
		ok() { :; }
		info() { printf 'info %s\n' "$1" >>"$work/sudo.log"; }
		warn() { printf 'warn %s\n' "$1" >>"$work/sudo.log"; }
		arch_multilib_enabled() { [[ -e $work/enabled ]]; }
		sudo() {
			printf '%s\n' "$*" >>"$work/sudo.log"
			[[ $1 != sed ]] || : >"$work/enabled"
			[[ $1 != pacman || ${PACMAN_FAILS:-0} != 1 ]]
		}
		# shellcheck disable=SC1091 # generated above
		. "$work/multilib.sh"
		configure_arch_multilib_repository
	)
}

run_case || fail 'enabling multilib failed'
grep -Fqx 'pacman -Syu' "$work/sudo.log" || {
	lyona_show_file "$work/sudo.log"
	fail 'multilib was not followed by pacman -Syu'
}
if grep -Eq '^pacman -Sy$|^pacman -Sy ' "$work/sudo.log"; then
	lyona_show_file "$work/sudo.log"
	fail 'pacman -Sy (a partial upgrade) is still run'
fi
grep -Fq 'info Upgrading the system' "$work/sudo.log" || fail 'the upgrade is not announced'

PACMAN_FAILS=1 run_case && fail 'a failed upgrade was reported as success'
grep -Fq 'warn Could not upgrade the system' "$work/sudo.log" || fail 'a failed upgrade is not reported'

printf '%s\n' 'install.sh multilib upgrade (pacman -Syu, never -Sy): PASS'
