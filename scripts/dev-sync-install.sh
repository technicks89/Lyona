#!/bin/sh

set -eu

program=${0##*/}

usage() {
	cat <<'EOF'
Usage: scripts/dev-sync-install.sh [--check]

Build and synchronize the current checkout with the live lyona install.
The default mode:

  1. Builds dwm from a clean object state.
  2. Skips installation when every managed file already matches.
  3. Backs up the current managed installation before an update.
  4. Runs the complete system and user Makefile install.
  5. Verifies installed commands, generated files, managed data, and Quickshell.
  6. Restarts Quickshell when safe, or defers it to a required session restart.
  7. Reports whether dwm requires a session restart.

Options:
  --check   Verify install and runtime parity without building or changing files.
  -h, --help
            Show this help.

Path overrides use the same variables as the Makefile:
  PREFIX, MANPREFIX, XSESSIONSDIR, DATADIR, USER_HOME,
  XDG_CONFIG_HOME, XDG_DATA_HOME, and XDG_STATE_HOME.
EOF
}

die() {
	printf '%s: %s\n' "$program" "$*" >&2
	exit 1
}

note() {
	printf '==> %s\n' "$*"
}

check_only=0
while [ "$#" -gt 0 ]; do
	case $1 in
	--check)
		check_only=1
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "unknown option: $1"
		;;
	esac
	shift
done

script_dir=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")" && pwd
)
# The verification, backup and runtime checks are shared with lyona-update, in
# lyona-install-verify.sh (Sync Sprint 12 S12-13). This developer tool runs from
# a checkout and is not installed, so the library is beside it.
# shellcheck source=scripts/lyona-install-verify.sh
LYONA_INSTALL_REPO_DIR=${script_dir%/*} \
	. "$script_dir/lyona-install-verify.sh"
owner=$(id -un)

prepare_expected_files

if [ "$check_only" -eq 1 ]; then
	note "Checking live install against $repo_dir"
	verify_install || exit 1
	runtime_verify 0 || exit 1
	exit 0
fi

if [ "$(id -u)" -eq 0 ]; then
	die "run this script as the desktop user, not root"
fi

note "Building current checkout"
"$make_path" -C "$repo_dir" clean
"$make_path" -C "$repo_dir" all

if verify_install; then
	note "Live installation is already current"
	runtime_verify 0 || exit 1
	exit 0
fi

note "Backing up current live installation"
backup_live_install

command -v sudo >/dev/null 2>&1 || die "sudo is required for the system install"
sudo -v

note "Installing complete system and user state"
sudo "$make_path" -C "$repo_dir" install \
	DESTDIR= \
	PREFIX="$prefix" \
	MANPREFIX="$manprefix" \
	XSESSIONSDIR="$xsessions_dir" \
	DATADIR="$data_root" \
	USER_HOME="$user_home" \
	OWNER="$owner" \
	XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$xdg_data_home"

note "Verifying installed state"
verify_install || die "live installation does not match the checkout"
runtime_verify 1 || die "runtime validation failed"
