#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 12 S12-11 item 1: enabling multilib must not leave a partial upgrade.
# configure_arch_multilib_repository is extracted from install.sh and run against
# stubs: sudo only logs (nothing touches the real pacman.conf), and multilib reads
# as disabled until the sed has run.
# #248: it runs no pacman of its own. The databases are refreshed by the package
# install right after it, one pacman -Syu --needed transaction with the gaming
# packages in it: the matching upgrade, never -Sy alone.

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
	[[ ${ALREADY_ENABLED:-0} != 1 ]] || : >"$work/enabled"
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
grep -q '^sed ' "$work/sudo.log" || fail 'multilib was not enabled in pacman.conf'
grep -Fq 'info Enabling the multilib repository' "$work/sudo.log" || fail 'enabling multilib is not announced'
if grep -q '^pacman' "$work/sudo.log"; then
	lyona_show_file "$work/sudo.log"
	fail 'configure_arch_multilib_repository still runs pacman itself'
fi

# multilib already enabled (a rerun, or enabled by hand): pacman.conf is left alone.
ALREADY_ENABLED=1 run_case || fail 'the already-enabled case failed'
if grep -Eq '^(sed|pacman) ' "$work/sudo.log"; then
	lyona_show_file "$work/sudo.log"
	fail 'an already-enabled multilib changed something'
fi

# install.sh: multilib is set up, and the gaming packages (Vulkan drivers first)
# queued, before the one package install, which is -Syu; no other pacman -Sy.
# shellcheck disable=SC2016 # the literal text in install.sh
configure_line=$(grep -n '^	elif configure_arch_multilib_repository; then$' "$repo/install.sh" | cut -d: -f1)
vulkan_line=$(grep -nF 'batch_optional < <(dwm_vulkan_driver_packages)' "$repo/install.sh" | cut -d: -f1)
gaming_line=$(grep -nF 'batch_optional < <(dwm_collect_packages gaming)' "$repo/install.sh" | cut -d: -f1)
# shellcheck disable=SC2016 # the literal text in install.sh
batch_line=$(grep -nF 'if ! dwm_install_batch "${batch_flags[@]}" batch_required batch_optional; then' "$repo/install.sh" | cut -d: -f1)
if [[ -z $configure_line || -z $vulkan_line || -z $gaming_line || -z $batch_line ]] ||
	! ((configure_line < vulkan_line && vulkan_line < gaming_line && gaming_line < batch_line)); then
	fail "install.sh does not set up multilib, then queue the Vulkan drivers and gaming, before the install ($configure_line, $vulkan_line, $gaming_line, $batch_line)"
fi
if grep -nE 'pacman -Sy([^u]|$)' "$repo/install.sh" | grep -v ':[[:space:]]*#' | grep -q .; then
	fail "install.sh runs pacman -Sy without the upgrade: $(grep -nE 'pacman -Sy([^u]|$)' "$repo/install.sh")"
fi
[[ $(grep -c 'dwm_install_batch ' "$repo/install.sh") == 1 ]] || fail 'install.sh has more than one package transaction'

printf '%s\n' 'install.sh multilib in the one package install (pacman -Syu, never -Sy): PASS'
