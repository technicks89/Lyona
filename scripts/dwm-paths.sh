# shellcheck shell=bash
#
# Path-safety checks shared by the scripts that write user state. Bash, since
# every caller is; sourced with the directory the caller lives in, which is
# scripts/ in the repo and PREFIX/bin once installed:
#
#     script_dir=${BASH_SOURCE[0]%/*}
#     . "$script_dir/dwm-paths.sh"
#
# Caller contract: ensure_owned_directory reports through die, so a caller
# must define one before using it. Nothing here has any other side effect --
# no variables set, no environment read.

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
