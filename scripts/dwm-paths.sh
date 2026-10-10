# shellcheck shell=bash
#
# Path-safety checks shared by the scripts that write user state, and where the
# shipped defaults live. Bash, since every caller is; sourced from lyona_lib,
# which is scripts/ in the repo and PREFIX/lib/lyona once installed:
#
#     lyona_lib=${BASH_SOURCE[0]%/*}
#     [[ -f $lyona_lib/dwm-paths.sh ]] || lyona_lib=${lyona_lib%bin}lib/lyona
#     . "$lyona_lib/dwm-paths.sh"
#
# Caller contract: ensure_owned_directory reports through die, so a caller
# must define one before using it. lyona_toml reads the caller's lyona_lib,
# and lyona_toml_load sets LYONA_TOML. Nothing else here has a side effect.

# An absolute path with nothing in it that would confuse a later parse or walk
# somewhere else: no newline, carriage return or tab, and no . or .. component.
#
# Three copies of this had drifted apart, and one was materially weaker:
# dwm-settings-font's accepted tabs and traversal components while validating
# HOME and the XDG directories, which the other two rejected for the same
# class of input. This is the strict form.
valid_absolute_path() {
	local path=${1:-}
	[[ $path == /* && $path != *$'\n'* && $path != *$'\r'* && $path != *$'\t'* ]] || return 1
	case $path/ in
	*/../* | */./*) return 1 ;;
	esac
	return 0
}

# No component of an absolute path is a symlink. Guards against a directory in
# the middle of the path being swapped for a link somewhere else between the
# check and the write.
path_has_no_symlink_components() {
	local path=$1 current=/ component
	local -a components=()

	valid_absolute_path "$path" || return 1
	IFS=/ read -r -a components <<<"${path#/}"
	for component in "${components[@]}"; do
		[[ -n $component ]] || continue
		if [[ $current == / ]]; then
			current=/$component
		else
			current=$current/$component
		fi
		[[ ! -L $current ]] || return 1
	done
}

# Every existing ancestor of a path is a real directory rather than a symlink.
# Walks upward, so it says nothing about the final component itself.
existing_path_chain_is_safe() {
	local path=$1 probe
	probe=${path%/*}
	[[ $probe != "$path" ]] || probe=.
	while [[ $probe != / && $probe != . ]]; do
		if [[ -e $probe || -L $probe ]]; then
			[[ -d $probe && ! -L $probe ]] || return 1
		fi
		probe=${probe%/*}
		[[ -n $probe ]] || probe=/
	done
}

# A directory is safe to write into, creating it later if it does not exist
# yet. With require_owner, it must also belong to this user and be writable and
# searchable by them.
directory_path_ready() {
	local directory=$1 require_owner=${2:-false} probe mode
	[[ $directory == /* ]] || return 1
	# The sentinel is never created: existing_path_chain_is_safe walks up from
	# its argument, so naming a child is how the directory itself gets checked.
	existing_path_chain_is_safe "$directory/.path-ready" || return 1
	if [[ -e $directory || -L $directory ]]; then
		[[ -d $directory && ! -L $directory && -w $directory && -x $directory ]] || return 1
		if [[ $require_owner == true ]]; then
			[[ $(stat -c %u -- "$directory") == "$UID" ]] || return 1
			mode=$(stat -c %a -- "$directory")
			(((8#$mode & 0300) == 0300)) || return 1
		fi
		return 0
	fi
	probe=$directory
	while [[ ! -e $probe && ! -L $probe ]]; do
		[[ $probe != / && $probe != . ]] || return 1
		probe=${probe%/*}
		[[ -n $probe ]] || probe=/
	done
	[[ -d $probe && ! -L $probe && -w $probe && -x $probe ]]
}

# Create a directory this user owns, or die trying.
#
# The symlink check comes before mkdir, not after: refusing outright beats
# calling mkdir on a path an attacker controls and then judging the result.
# That ordering came from dwm-settings-font; the $UID rather than an id -u
# fork came from the other two.
ensure_owned_directory() {
	local path=$1 label=$2
	if [[ -L $path ]]; then
		die "$label directory must not be a symlink: $path"
	fi
	if [[ ! -e $path ]]; then
		(umask 077 && mkdir -p -- "$path") 2>/dev/null ||
			die "could not create $label directory: $path"
	fi
	[[ -d $path && ! -L $path ]] || die "$label path is not a directory: $path"
	[[ $(stat -c %u -- "$path" 2>/dev/null) == "$UID" ]] ||
		die "$label directory is not owned by the current user: $path"
}

# The shipped default config for a caller whose libraries are in LIB (its
# lyona_lib): PREFIX/share/lyona/config beside an installed PREFIX/lib/lyona,
# else config/ beside the checkout's scripts/ (Sync Sprint 12 S12-13). Prints
# the directory as an absolute path with no symlinks, or fails if it is missing.
# A subshell body, so the cd never moves the caller.
lyona_default_config_dir() (
	lib=$1
	case $lib in
	*lib/lyona) dir=$lib/../../share/lyona/config ;;
	*) dir=$lib/../config ;;
	esac
	CDPATH='' cd -P -- "$dir" 2>/dev/null && pwd
)

# The one TOML reader (Sync Sprint 12 S12-14, D-20): PREFIX/lib/lyona/lyona-toml
# beside an installed caller's libraries, else the checkout's built one beside
# scripts/. Runs it with the arguments given; see lyona-toml.c for its output and
# exit status.
lyona_toml() {
	local lib=${lyona_lib:?lyona_toml needs lyona_lib set by the caller}
	local tool=$lib/lyona-toml
	[[ -x $tool ]] || tool=$lib/../lyona-toml
	"$tool" "$@"
}

# Read FILE once into LYONA_TOML, a map of "section<FS>key" to value for its
# plain entries (not [[array-of-tables]] ones); the first entry of a key wins, as
# in dwm's toml_get. Fields are split by parameter expansion, not IFS, since
# consecutive tabs would collapse an empty top-level section name, and the dump
# doubles every backslash, so %b gives back exactly each value. Returns
# lyona-toml's status: 0, or 4 when entries past dwm's limit were dropped (the
# map still holds what dwm reads). Load in the calling shell, not in $(...):
# the map is lost with the subshell.
lyona_toml_load() {
	local file=$1 line section index key value dump status=0
	declare -gA LYONA_TOML=()
	dump=$(lyona_toml dump "$file") || status=$?
	[[ $status == 0 || $status == 4 ]] || return "$status"
	while IFS= read -r line; do
		section=${line%%$'\t'*}
		line=${line#*$'\t'}
		index=${line%%$'\t'*}
		line=${line#*$'\t'}
		key=${line%%$'\t'*}
		value=${line#*$'\t'}
		[[ $index == -1 ]] || continue
		[[ -z ${LYONA_TOML["$section"$'\034'"$key"]+x} ]] || continue
		printf -v value '%b' "$value"
		LYONA_TOML["$section"$'\034'"$key"]=$value
	done <<<"$dump"
	return "$status"
}

# The value lyona_toml_load read for SECTION and KEY, or nothing.
lyona_toml_value() {
	printf '%s\n' "${LYONA_TOML["$1"$'\034'"$2"]:-}"
}

# The default shared-data directory for PREFIX, as the Makefile's DATADIR:
# /usr/share for PREFIX /usr and /usr/local, else PREFIX/share.
lyona_default_datadir() {
	case $1 in
	/usr | /usr/local) printf '/usr/share\n' ;;
	*) printf '%s/share\n' "$1" ;;
	esac
}

# Where the system install put things, from the record make install-system
# wrote (/etc/lyona-release, its LYONA_PREFIX, LYONA_MANPREFIX, LYONA_DATADIR and
# LYONA_XSESSIONSDIR), so both halves of an update use the layout root installs
# into (#325); lyona-update-root reads the same record, as root. A field the
# record lacks (one from before 2026.10.0-beta.6) comes from the environment,
# else the Makefile's default. Read as data, never sourced: only absolute paths
# of plain characters are taken. Sets and exports PREFIX, MANPREFIX, DATADIR
# and XSESSIONSDIR. DWM_TEST_SYSTEM_RECORD names another record, for the tests.
lyona_install_layout() {
	local record=${DWM_TEST_SYSTEM_RECORD:-/etc/lyona-release} line key value size
	local prefix='' manprefix='' datadir='' xsessionsdir=''

	if [[ -f $record && ! -L $record ]] && size=$(stat -c %s -- "$record" 2>/dev/null) &&
		((size <= 4096)); then
		while IFS= read -r line || [[ -n $line ]]; do
			key=${line%%=*}
			value=${line#*=}
			if ! [[ $value =~ ^/[A-Za-z0-9._/+-]*$ && $value != / ]] || ! valid_absolute_path "$value"; then
				continue
			fi
			case $key in
			LYONA_PREFIX) prefix=$value ;;
			LYONA_MANPREFIX) manprefix=$value ;;
			LYONA_DATADIR) datadir=$value ;;
			LYONA_XSESSIONSDIR) xsessionsdir=$value ;;
			esac
		done <"$record"
	fi
	PREFIX=${prefix:-${PREFIX:-/usr/local}}
	MANPREFIX=${manprefix:-${MANPREFIX:-$PREFIX/share/man}}
	DATADIR=${datadir:-${DATADIR:-$(lyona_default_datadir "$PREFIX")}}
	XSESSIONSDIR=${xsessionsdir:-${XSESSIONSDIR:-/usr/share/xsessions}}
	export PREFIX MANPREFIX DATADIR XSESSIONSDIR
}
