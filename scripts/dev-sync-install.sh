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

# A caller sourcing this file in DEV_SYNC_INSTALL_LIB_ONLY mode has almost
# certainly already defined its own die() (dwm-paths.sh's helpers require
# one); defining a second one here would silently replace theirs for the
# rest of their process, misattributing every later error message to this
# file's own $program instead of the sourcing script's.
if ! command -v die >/dev/null 2>&1; then
	die() {
		printf '%s: %s\n' "$program" "$*" >&2
		exit 1
	}
fi

note() {
	printf '==> %s\n' "$*"
}

validate_live_root() {
	live_root_name=$1
	live_root_value=$2

	case $live_root_value in
	/*) ;;
	*) die "$live_root_name must be an absolute path: $live_root_value" ;;
	esac
	if [ "$live_root_value" = / ]; then
		die "$live_root_name must not be the filesystem root"
	fi
}

# DEV_SYNC_INSTALL_REPO_DIR lets a sourcing caller (lyona-update, staging an
# unpacked release rather than this script's own checkout) point every path
# and function below at a different tree. $0 is meaningless once sourced --
# it names the sourcing script, not this file -- so lib-only mode requires
# the override explicitly rather than silently deriving a wrong path from it.
if [ "${DEV_SYNC_INSTALL_LIB_ONLY:-0}" = 1 ]; then
	[ -n "${DEV_SYNC_INSTALL_REPO_DIR:-}" ] ||
		die "DEV_SYNC_INSTALL_REPO_DIR is required when sourcing this file"
	repo_dir=$DEV_SYNC_INSTALL_REPO_DIR
else
	repo_dir=${DEV_SYNC_INSTALL_REPO_DIR:-$(
		unset CDPATH
		cd -- "$(dirname -- "$0")/.." && pwd
	)}
fi

# DEV_SYNC_INSTALL_LIB_ONLY=1: a caller sources this file for its functions
# and path variables (backup_live_install, verify_install, runtime_verify,
# prepare_expected_files) without running this script's own CLI or build/
# install/backup sequence. Skip argument parsing entirely in that mode --
# $@ belongs to the sourcing script, not to us.
check_only=0
if [ "${DEV_SYNC_INSTALL_LIB_ONLY:-0}" != 1 ]; then
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
fi

if [ -n "${DESTDIR:-}" ]; then
	die "DESTDIR is not supported; this command targets a live installation"
fi

user_home=${USER_HOME:-${HOME:-}}
[ -n "$user_home" ] || die "USER_HOME and HOME are unavailable"
owner=$(id -un)
prefix=${PREFIX:-/usr/local}
manprefix=${MANPREFIX:-$prefix/share/man}
xsessions_dir=${XSESSIONSDIR:-/usr/share/xsessions}
data_root=${DATADIR:-/usr/share}
config_home=${XDG_CONFIG_HOME:-$user_home/.config}
xdg_data_home=${XDG_DATA_HOME:-$user_home/.local/share}
state_home=${XDG_STATE_HOME:-$user_home/.local/state}
data_dir=$xdg_data_home/lyona
quickshell_dir=$config_home/quickshell
binary_target=$prefix/bin/dwm
man_target=$manprefix/man1/dwm.1
xsession_target=$xsessions_dir/dwm.desktop
privileged_helper_dir=$prefix/libexec/lyona
make_command=${MAKE:-make}

validate_live_root USER_HOME "$user_home"
validate_live_root PREFIX "$prefix"
validate_live_root MANPREFIX "$manprefix"
validate_live_root XSESSIONSDIR "$xsessions_dir"
validate_live_root DATADIR "$data_root"
validate_live_root XDG_CONFIG_HOME "$config_home"
validate_live_root XDG_DATA_HOME "$xdg_data_home"
validate_live_root XDG_STATE_HOME "$state_home"

for required_command in awk cmp diff id mktemp sed "$make_command"; do
	command -v "$required_command" >/dev/null 2>&1 ||
		die "required command not found: $required_command"
done
make_path=$(command -v "$make_command")

work=$(mktemp -d "${TMPDIR:-/tmp}/dwm-dev-sync.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
install_sources_file=$work/install-sources
expected_man=$work/dwm.1
expected_xsession=$work/dwm.desktop
privileged_helpers_file=$work/privileged-helpers
expected_privileged_dir=$work/privileged
tree_diff=$work/tree.diff

prepare_expected_files() {
	# shellcheck disable=SC2016
	"$make_path" -s -C "$repo_dir" --no-print-directory \
		--eval='dwm-dev-print-install-sources: ; @printf "%s\n" $(INSTALL_COMMANDS)' \
		dwm-dev-print-install-sources >"$install_sources_file"
	[ -s "$install_sources_file" ] ||
		die "Makefile did not report any installed commands"

	# shellcheck disable=SC2016
	"$make_path" -s -C "$repo_dir" --no-print-directory \
		--eval='dwm-dev-print-privileged-helpers: ; @printf "%s\n" $(PRIVILEGED_HELPERS)' \
		dwm-dev-print-privileged-helpers >"$privileged_helpers_file"
	[ -s "$privileged_helpers_file" ] ||
		die "Makefile did not report any privileged helpers"

	version=$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' "$repo_dir/config.mk")
	[ -n "$version" ] || die "could not read VERSION from config.mk"
	sed "s/VERSION/$version/g" "$repo_dir/dwm.1" >"$expected_man"
	sed "s|@PREFIX@|$prefix|g" "$repo_dir/dwm.desktop" >"$expected_xsession"

	mkdir -p "$expected_privileged_dir"
	while IFS= read -r privileged_helper; do
		[ -n "$privileged_helper" ] || continue
		sed "s|@PREFIX@|$prefix|g" "$repo_dir/$privileged_helper" \
			>"$expected_privileged_dir/${privileged_helper##*/}"
	done <"$privileged_helpers_file"
}

verification_failed=0

verify_file() {
	expected_file=$1
	actual_file=$2
	file_label=$3

	if [ ! -f "$expected_file" ]; then
		printf 'MISSING SOURCE: %s (%s)\n' "$file_label" "$expected_file" >&2
		verification_failed=1
	elif [ ! -f "$actual_file" ]; then
		printf 'MISSING INSTALL: %s (%s)\n' "$file_label" "$actual_file" >&2
		verification_failed=1
	elif ! cmp -s "$expected_file" "$actual_file"; then
		printf 'MISMATCH: %s (%s)\n' "$file_label" "$actual_file" >&2
		verification_failed=1
	fi
}

verify_executable() {
	expected_executable=$1
	actual_executable=$2
	executable_label=$3

	verify_file "$expected_executable" "$actual_executable" "$executable_label"
	if [ -e "$actual_executable" ] && [ ! -x "$actual_executable" ]; then
		printf 'NOT EXECUTABLE: %s (%s)\n' "$executable_label" "$actual_executable" >&2
		verification_failed=1
	fi
}

verify_tree() {
	expected_tree=$1
	actual_tree=$2
	tree_label=$3

	if [ ! -d "$expected_tree" ]; then
		printf 'MISSING SOURCE TREE: %s (%s)\n' "$tree_label" "$expected_tree" >&2
		verification_failed=1
	elif [ ! -d "$actual_tree" ]; then
		printf 'MISSING INSTALL TREE: %s (%s)\n' "$tree_label" "$actual_tree" >&2
		verification_failed=1
	elif diff -qr "$expected_tree" "$actual_tree" >"$tree_diff"; then
		:
	else
		printf 'MISMATCH TREE: %s (%s)\n' "$tree_label" "$actual_tree" >&2
		sed 's/^/  /' "$tree_diff" >&2
		verification_failed=1
	fi
}

verify_install() {
	verification_failed=0

	verify_executable "$repo_dir/dwm" "$binary_target" "dwm binary"
	while IFS= read -r install_source; do
		[ -n "$install_source" ] || continue
		install_name=${install_source##*/}
		verify_executable "$repo_dir/$install_source" "$prefix/bin/$install_name" \
			"installed command $install_name"
	done <"$install_sources_file"
	verify_privileged_helper_trust=1
	if [ "${DWM_DEV_SYNC_SKIP_PRIVILEGED_TRUST:-0}" = 1 ]; then
		verify_privileged_helper_trust=0
	fi
	while IFS= read -r privileged_helper; do
		[ -n "$privileged_helper" ] || continue
		privileged_helper_name=${privileged_helper##*/}
		privileged_helper_target=$privileged_helper_dir/$privileged_helper_name
		verify_executable "$expected_privileged_dir/$privileged_helper_name" \
			"$privileged_helper_target" "privileged helper $privileged_helper_name"
		if [ "$verify_privileged_helper_trust" -eq 1 ] && [ -e "$privileged_helper_target" ]; then
			if [ "$(stat -c %u "$privileged_helper_target")" -ne 0 ] ||
				find "$privileged_helper_target" -maxdepth 0 -perm /022 -print -quit | grep -q .; then
				printf 'UNTRUSTED: privileged helper ownership or mode: %s (%s)\n' \
					"$privileged_helper_name" "$privileged_helper_target" >&2
				verification_failed=1
			fi
		fi
	done <"$privileged_helpers_file"

	verify_file "$expected_man" "$man_target" "dwm man page"
	verify_file "$expected_xsession" "$xsession_target" "dwm X session"
	verify_tree "$repo_dir/config" "$data_dir/config" "managed data config"
	verify_tree "$repo_dir/scripts" "$data_dir/scripts" "managed data scripts"
	verify_tree "$repo_dir/config/quickshell" "$quickshell_dir" "managed Quickshell"

	for cursor_source in "$repo_dir"/assets/cursors/Capitaine-Cursors*; do
		[ -d "$cursor_source" ] || continue
		cursor_name=${cursor_source##*/}
		verify_tree "$cursor_source" "$data_root/icons/$cursor_name" \
			"cursor theme $cursor_name"
	done
	verify_file "$repo_dir/assets/cursors/COPYING" \
		"$data_root/licenses/lyona/capitaine-cursors/COPYING" \
		"cursor license"

	if [ "$verification_failed" -eq 0 ]; then
		printf 'All managed files match the checkout.\n'
		return 0
	fi
	return 1
}

add_system_backup_path() {
	system_path=$1
	if [ -e "$system_path" ] || [ -L "$system_path" ]; then
		printf '%s\n' "${system_path#/}" >>"$system_manifest"
	fi
}

backup_live_install() {
	for backup_command in date git sha256sum tar; do
		command -v "$backup_command" >/dev/null 2>&1 ||
			die "required backup command not found: $backup_command"
	done

	backup_parent=$state_home/lyona/live-update-backups
	backup_stamp=$(date -u +%Y%m%dT%H%M%SZ)
	mkdir -p "$backup_parent"
	backup_dir=$backup_parent/$backup_stamp-$$
	mkdir -m 700 "$backup_dir"

	if [ -e "$quickshell_dir" ]; then
		tar -C "$(dirname "$quickshell_dir")" -cpf \
			"$backup_dir/quickshell.tar" "$(basename "$quickshell_dir")"
	fi
	if [ -e "$data_dir" ]; then
		tar -C "$(dirname "$data_dir")" -cpf \
			"$backup_dir/lyona-data.tar" "$(basename "$data_dir")"
	fi

	system_manifest=$work/system-files
	: >"$system_manifest"
	add_system_backup_path "$binary_target"
	add_system_backup_path "$man_target"
	add_system_backup_path "$xsession_target"
	while IFS= read -r install_source; do
		[ -n "$install_source" ] || continue
		add_system_backup_path "$prefix/bin/${install_source##*/}"
	done <"$install_sources_file"
	while IFS= read -r privileged_helper; do
		[ -n "$privileged_helper" ] || continue
		add_system_backup_path "$privileged_helper_dir/${privileged_helper##*/}"
	done <"$privileged_helpers_file"
	for cursor_source in "$repo_dir"/assets/cursors/Capitaine-Cursors*; do
		[ -d "$cursor_source" ] || continue
		add_system_backup_path "$data_root/icons/${cursor_source##*/}"
	done
	add_system_backup_path "$data_root/licenses/lyona/capitaine-cursors/COPYING"
	if [ -s "$system_manifest" ]; then
		tar -C / -cpf "$backup_dir/system-files.tar" -T "$system_manifest"
	fi

	{
		printf 'commit=%s\n' "$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || printf unknown)"
		printf 'branch=%s\n' "$(git -C "$repo_dir" branch --show-current 2>/dev/null || printf unknown)"
		printf 'version=%s\n' "$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' "$repo_dir/config.mk")"
		printf 'prefix=%s\n' "$prefix"
		printf 'data_root=%s\n' "$data_root"
		printf 'config_home=%s\n' "$config_home"
		printf 'xdg_data_home=%s\n' "$xdg_data_home"
	} >"$backup_dir/checkout.txt"

	: >"$backup_dir/SHA256SUMS"
	for backup_archive in "$backup_dir"/*.tar; do
		[ -f "$backup_archive" ] || continue
		sha256sum "$backup_archive" >>"$backup_dir/SHA256SUMS"
	done
	printf 'Backup created: %s\n' "$backup_dir"
}

runtime_verify() {
	allow_session_restart=$1
	runtime_failed=0

	if [ "${DWM_DEV_SYNC_SKIP_RUNTIME:-0}" = 1 ]; then
		printf 'Runtime validation skipped by DWM_DEV_SYNC_SKIP_RUNTIME=1.\n'
		return 0
	fi
	if [ -z "${DISPLAY:-}" ]; then
		printf 'Runtime validation deferred: DISPLAY is unavailable.\n'
		return 0
	fi

	dwm_pid=$(pgrep -xo dwm 2>/dev/null || true)
	dwm_restart_required=0
	if [ -n "$dwm_pid" ]; then
		running_executable=$(readlink "/proc/$dwm_pid/exe" 2>/dev/null || true)
		case $running_executable in
		*" (deleted)") dwm_restart_required=1 ;;
		esac
		if [ "$dwm_restart_required" -eq 0 ] &&
			! cmp -s "/proc/$dwm_pid/exe" "$binary_target"; then
			dwm_restart_required=1
		fi
	fi

	restart_quickshell_now=$allow_session_restart
	if [ "$allow_session_restart" -eq 1 ] && [ "$dwm_restart_required" -eq 1 ]; then
		restart_quickshell_now=0
		printf 'Quickshell activation deferred to the required session restart to preserve tray startup order.\n'
	fi

	if command -v quickshell >/dev/null 2>&1; then
		if [ "$restart_quickshell_now" -eq 1 ]; then
			control_helper=$prefix/bin/dwm-quickshell-controlcenter
			if [ ! -x "$control_helper" ]; then
				printf 'Runtime error: managed Quickshell control helper is unavailable.\n' >&2
				runtime_failed=1
			elif ! "$control_helper" action restart-quickshell; then
				printf 'Runtime error: Quickshell restart failed.\n' >&2
				runtime_failed=1
			fi
		fi

		tray_ready=0
		tray_count=
		tray_try=0
		while [ "$tray_try" -lt 50 ]; do
			if tray_count=$(quickshell ipc --path "$quickshell_dir/shell.qml" \
				call tray count 2>/dev/null); then
				tray_ready=1
				break
			fi
			tray_try=$((tray_try + 1))
			sleep 0.1
		done
		if [ "$tray_ready" -eq 1 ]; then
			quickshell_count=$(pgrep -xc quickshell 2>/dev/null || true)
			if [ "$quickshell_count" -ne 1 ]; then
				printf 'Runtime error: expected one Quickshell process, found %s.\n' \
					"$quickshell_count" >&2
				runtime_failed=1
			else
				printf 'Quickshell IPC ready; tray items: %s.\n' "$tray_count"
			fi
		else
			printf 'Runtime error: Quickshell tray IPC did not become ready.\n' >&2
			runtime_failed=1
		fi
	else
		printf 'Runtime validation deferred: Quickshell is not installed.\n'
	fi

	if [ -n "$dwm_pid" ]; then
		if [ "$dwm_restart_required" -eq 1 ]; then
			if [ "$allow_session_restart" -eq 1 ]; then
				printf '\nSESSION RESTART REQUIRED: log out and back in to activate %s.\n' \
					"$binary_target"
			else
				printf 'Runtime error: running dwm does not match the installed binary.\n' >&2
				runtime_failed=1
			fi
		else
			printf 'Running dwm matches the installed binary.\n'
		fi

		if command -v systemctl >/dev/null 2>&1; then
			for graphical_target in graphical-session.target xdg-desktop-autostart.target; do
				if ! systemctl --user is-active --quiet "$graphical_target" 2>/dev/null; then
					printf 'Runtime error: %s is not active.\n' "$graphical_target" >&2
					runtime_failed=1
				fi
			done
			failed_autostarts=$(systemctl --user --failed --no-legend --plain 2>/dev/null |
				awk '$1 ~ /@autostart[.]service$/ { print $1 }')
			if [ -n "$failed_autostarts" ]; then
				printf 'Runtime error: failed XDG autostart units:\n%s\n' \
					"$failed_autostarts" >&2
				runtime_failed=1
			fi
		fi
	else
		printf 'Runtime validation deferred: dwm is not running.\n'
	fi

	[ "$runtime_failed" -eq 0 ]
}

if [ "${DEV_SYNC_INSTALL_LIB_ONLY:-0}" = 1 ]; then
	# Every function and path variable above is now defined in the sourcing
	# shell. Stop before this script's own build/verify/backup/install
	# sequence -- the caller drives that with its own step ordering.
	# shellcheck disable=SC2317 # exit is reachable when run directly, not sourced
	return 0 2>/dev/null || exit 0
fi

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
