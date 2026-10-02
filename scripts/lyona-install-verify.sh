# shellcheck shell=sh
#
# Verify, back up and runtime-check a live Lyona install against a source tree
# (Sync Sprint 12 S12-13). A library, sourced by lyona-update (apply, rollback)
# and scripts/dev-sync-install.sh, which set LYONA_INSTALL_REPO_DIR first:
#
#     LYONA_INSTALL_REPO_DIR=$tree . "$lyona_lib/lyona-install-verify.sh"
#     prepare_expected_files
#     backup_live_install; verify_install; runtime_verify 1
#
# Sourcing it sets the path variables below from PREFIX, MANPREFIX,
# XSESSIONSDIR, DATADIR, USER_HOME and the XDG directories, as the Makefile
# does, creates a work directory, and chains its removal onto any EXIT trap.

# A caller has almost certainly already defined its own die() (dwm-paths.sh's
# helpers require one); defining a second one here would silently replace
# theirs for the rest of their process, misattributing every later error
# message to this file instead of the sourcing script.
if ! command -v die >/dev/null 2>&1; then
	die() {
		printf '%s: %s\n' "${program:-lyona-install-verify}" "$*" >&2
		exit 1
	}
fi

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

# The tree the live install is compared against: a checkout for
# dev-sync-install.sh, an unpacked release or a backup for lyona-update. $0
# names the sourcing script, so the caller always says which.
[ -n "${LYONA_INSTALL_REPO_DIR:-}" ] ||
	die "LYONA_INSTALL_REPO_DIR is required when sourcing lyona-install-verify.sh"
repo_dir=$LYONA_INSTALL_REPO_DIR

if [ -n "${DESTDIR:-}" ]; then
	die "DESTDIR is not supported; this command targets a live installation"
fi

user_home=${USER_HOME:-${HOME:-}}
[ -n "$user_home" ] || die "USER_HOME and HOME are unavailable"
prefix=${PREFIX:-/usr/local}
manprefix=${MANPREFIX:-$prefix/share/man}
xsessions_dir=${XSESSIONSDIR:-/usr/share/xsessions}
data_root=${DATADIR:-/usr/share}
# Not dwm-xdg.sh (S12-14): these fall back under USER_HOME, not HOME, and
# validate_live_root below refuses a relative value outright, since they name
# the live install being checked.
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

work=$(mktemp -d "${TMPDIR:-/tmp}/lyona-install-verify.XXXXXX")
# A caller sourcing this file may already have its own EXIT
# trap registered (lyona-update's apply/rollback use one to report a failed
# status on any die() from here on). `trap` silently replaces whatever was
# there, so any existing handler is captured and chained instead of clobbered
# -- the same class of fix as die()'s command -v guard above, for traps
# instead of functions.
# shellcheck disable=SC3045 # trap -p is not POSIX Base, but this project's
# /bin/sh is bash on its only supported platform (Arch); there is no portable
# alternative for reading back an existing trap.
install_verify_previous_exit_trap=$(trap -p EXIT | sed -n "s/^trap -- '\\(.*\\)' EXIT\$/\\1/p")
if [ -n "$install_verify_previous_exit_trap" ]; then
	# install_verify_exit_status is captured before "rm -rf" runs and left in the
	# environment for the chained handler to read: $? right before that
	# handler runs would otherwise be rm's own (always 0), not the status
	# that actually triggered this trap.
	# shellcheck disable=SC2064 # deliberately expanded now: $work and the
	# captured trap command are both already fully resolved, and must be
	# baked into the chained trap string as it is set, not re-evaluated
	# later against whatever $work/$install_verify_previous_exit_trap then hold.
	trap "install_verify_exit_status=\$?; rm -rf \"$work\"; $install_verify_previous_exit_trap" EXIT
else
	trap 'rm -rf "$work"' EXIT
fi
# Let caller-owned signal handlers keep their behavior. Otherwise terminate
# with the signal status, leaving cleanup and the chained handler to EXIT.
# shellcheck disable=SC3045 # trap -p is supported by Arch's /bin/sh (bash).
case $(trap -p HUP) in "" | "trap -- - HUP") trap 'exit 129' HUP ;; esac
# shellcheck disable=SC3045
case $(trap -p INT) in "" | "trap -- - INT") trap 'exit 130' INT ;; esac
# shellcheck disable=SC3045
case $(trap -p TERM) in "" | "trap -- - TERM") trap 'exit 143' TERM ;; esac
install_sources_file=$work/install-sources
lib_sources_file=$work/lib-sources
python_sources_file=$work/python-sources
session_sources_file=$work/session-sources
default_sources_file=$work/default-sources
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
		--eval='dwm-dev-print-lib-sources: ; @printf "%s\n" $(INSTALL_LIBS)' \
		dwm-dev-print-lib-sources >"$lib_sources_file"
	[ -s "$lib_sources_file" ] ||
		die "Makefile did not report any installed libraries"

	# shellcheck disable=SC2016
	"$make_path" -s -C "$repo_dir" --no-print-directory \
		--eval='dwm-dev-print-python-sources: ; @printf "%s\n" $(INSTALL_PYTHON)' \
		dwm-dev-print-python-sources >"$python_sources_file"
	[ -s "$python_sources_file" ] ||
		die "Makefile did not report the system-management package"

	# shellcheck disable=SC2016
	"$make_path" -s -C "$repo_dir" --no-print-directory \
		--eval='dwm-dev-print-session-sources: ; @printf "%s\n" $(INSTALL_SESSION_SCRIPTS)' \
		dwm-dev-print-session-sources >"$session_sources_file"
	[ -s "$session_sources_file" ] ||
		die "Makefile did not report any session scripts"

	# shellcheck disable=SC2016
	"$make_path" -s -C "$repo_dir" --no-print-directory \
		--eval='dwm-dev-print-default-sources: ; @printf "%s\n" $(INSTALL_DEFAULTS)' \
		dwm-dev-print-default-sources >"$default_sources_file"
	[ -s "$default_sources_file" ] ||
		die "Makefile did not report any shipped defaults"

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
	verify_executable "$repo_dir/lyona-toml" "$prefix/lib/lyona/lyona-toml" "TOML reader"
	while IFS= read -r install_source; do
		[ -n "$install_source" ] || continue
		install_name=${install_source##*/}
		verify_executable "$repo_dir/$install_source" "$prefix/bin/$install_name" \
			"installed command $install_name"
	done <"$install_sources_file"
	# Shared shell code lives in PREFIX/lib/lyona, off PATH (S12-13); a copy
	# left in PREFIX/bin by an older install is stale.
	while IFS= read -r lib_source; do
		[ -n "$lib_source" ] || continue
		lib_name=${lib_source##*/}
		verify_file "$repo_dir/$lib_source" "$prefix/lib/lyona/$lib_name" \
			"installed library $lib_name"
		if [ -e "$prefix/bin/$lib_name" ] || [ -L "$prefix/bin/$lib_name" ]; then
			printf 'STALE: library %s is still installed in %s\n' \
				"$lib_name" "$prefix/bin" >&2
			verification_failed=1
		fi
	done <"$lib_sources_file"
	# The Python package behind dwm-system-management (S12-16), file by file:
	# a checkout's package directory may also hold __pycache__.
	python_dir=$prefix/lib/lyona/python/lyona_system_management
	while IFS= read -r python_source; do
		[ -n "$python_source" ] || continue
		verify_file "$repo_dir/$python_source" "$python_dir/${python_source##*/}" \
			"system-management module ${python_source##*/}"
	done <"$python_sources_file"
	for installed_module in "$python_dir"/*.py; do
		[ -e "$installed_module" ] || continue
		if ! grep -Fqx "scripts/lyona_system_management/${installed_module##*/}" "$python_sources_file"; then
			printf 'STALE: system-management module %s is no longer shipped\n' \
				"${installed_module##*/}" >&2
			verification_failed=1
		fi
	done
	while IFS= read -r session_source; do
		[ -n "$session_source" ] || continue
		verify_executable "$repo_dir/$session_source" \
			"$prefix/lib/lyona/${session_source##*/}" \
			"session script ${session_source##*/}"
	done <"$session_sources_file"
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

	while IFS= read -r default_source; do
		[ -n "$default_source" ] || continue
		verify_file "$repo_dir/$default_source" \
			"$prefix/share/lyona/config/${default_source##*/}" \
			"shipped default ${default_source##*/}"
	done <"$default_sources_file"

	verify_file "$expected_man" "$man_target" "dwm man page"
	verify_file "$expected_xsession" "$xsession_target" "dwm X session"
	verify_tree "$repo_dir/config/quickshell" "$quickshell_dir" "managed Quickshell"
	# The system copy is the only runtime source (S12-13); install-user removes
	# the per-user copy an older install left.
	for stale_tree in "$data_dir/scripts" "$data_dir/config"; do
		if [ -e "$stale_tree" ] || [ -L "$stale_tree" ]; then
			printf 'STALE: per-user copy %s is still present; run make install-user\n' \
				"$stale_tree" >&2
			verification_failed=1
		fi
	done

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
	# An upgrade removes legacy runtime trees; rollback must be able to put
	# them back for the previous release, including symlinked trees.
	if [ -e "$data_dir/scripts" ] || [ -L "$data_dir/scripts" ] ||
		[ -e "$data_dir/config" ] || [ -L "$data_dir/config" ]; then
		tar -C "$(dirname "$data_dir")" -cpf \
			"$backup_dir/lyona-data.tar" "$(basename "$data_dir")"
	fi

	system_manifest=$work/system-files
	: >"$system_manifest"
	add_system_backup_path "$binary_target"
	add_system_backup_path "$prefix/lib/lyona/lyona-toml"
	add_system_backup_path "$man_target"
	add_system_backup_path "$xsession_target"
	while IFS= read -r install_source; do
		[ -n "$install_source" ] || continue
		add_system_backup_path "$prefix/bin/${install_source##*/}"
	done <"$install_sources_file"
	# Both places: the install removes a library's old copy from bin, so the
	# backup keeps that one too.
	while IFS= read -r lib_source; do
		[ -n "$lib_source" ] || continue
		add_system_backup_path "$prefix/bin/${lib_source##*/}"
		add_system_backup_path "$prefix/lib/lyona/${lib_source##*/}"
	done <"$lib_sources_file"
	add_system_backup_path "$prefix/lib/lyona/python/lyona_system_management"
	while IFS= read -r session_source; do
		[ -n "$session_source" ] || continue
		add_system_backup_path "$prefix/lib/lyona/${session_source##*/}"
	done <"$session_sources_file"
	while IFS= read -r default_source; do
		[ -n "$default_source" ] || continue
		add_system_backup_path "$prefix/share/lyona/config/${default_source##*/}"
	done <"$default_sources_file"
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
		# Reinstallation can unlink the running executable without changing its
		# bytes. Proc still exposes that inode; compare it even when deleted.
		if ! cmp -s "/proc/$dwm_pid/exe" "$binary_target"; then
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
