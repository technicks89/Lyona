# shellcheck shell=sh
#
# Trust checks for a file run with more rights than the caller's own (Sync
# Sprint 12 S12-14). POSIX, so the Bash and the sh helpers source the same
# text. The two root helpers keep a byte-identical copy of the two functions
# between "BEGIN dwm-trust.sh" and "END dwm-trust.sh", since a root helper
# sources nothing at run time (decision D-21); tests/test-shell-contracts.sh
# fails if the copies differ. The variables are prefixed rather than local, so
# the file stays POSIX.

# The installed root helper NAME, from the prefix lyona is installed in:
# PREFIX/libexec/lyona/NAME beside PREFIX/bin, the one path its polkit policy
# names (Sync Sprint 16 R16-46: this was four copies, each also trying /usr/local
# and /usr). CALLER is the calling command's own path; from a checkout, the
# installed COMMAND on PATH gives the prefix instead. Prints the helper's path
# when it passes trusted_file. Above the functions the root helpers copy, as
# they never look a helper up.
trusted_root_helper_path() { # NAME CALLER COMMAND
	lyona_trust_bin=${2%/*}
	case $lyona_trust_bin in
	*/bin) ;;
	*)
		lyona_trust_bin=$(command -v "$3" 2>/dev/null) || return 1
		lyona_trust_bin=${lyona_trust_bin%/*}
		case $lyona_trust_bin in */bin) ;; *) return 1 ;; esac
		;;
	esac
	lyona_trust_helper=${lyona_trust_bin%/bin}/libexec/lyona/$1
	trusted_file "$lyona_trust_helper" || return 1
	printf '%s\n' "$lyona_trust_helper"
}

# Every directory from PATH's parent up to / is a real directory, owned by root
# and not group- or other-writable. A stat that fails counts as untrusted.
trusted_parent_chain() {
	lyona_trust_parent=${1%/*}
	while :; do
		[ -d "$lyona_trust_parent" ] && [ ! -L "$lyona_trust_parent" ] || return 1
		[ "$(stat -c %u -- "$lyona_trust_parent" 2>/dev/null || printf 1)" = 0 ] || return 1
		find "$lyona_trust_parent" -maxdepth 0 -type d ! -perm /022 -print -quit 2>/dev/null |
			grep -q . || return 1
		[ "$lyona_trust_parent" = / ] && return 0
		lyona_trust_parent=${lyona_trust_parent%/*}
		[ -n "$lyona_trust_parent" ] || lyona_trust_parent=/
	done
}

# PATH is already canonical (no symlink anywhere in it), and names a root-owned
# executable that nobody else can write, in a trusted directory chain.
trusted_file() {
	lyona_trust_path=$(readlink -f -- "$1" 2>/dev/null) || return 1
	[ -n "$lyona_trust_path" ] && [ "$lyona_trust_path" = "$1" ] || return 1
	trusted_parent_chain "$lyona_trust_path" || return 1
	[ -f "$lyona_trust_path" ] && [ ! -L "$lyona_trust_path" ] && [ -x "$lyona_trust_path" ] || return 1
	[ "$(stat -c %u -- "$lyona_trust_path" 2>/dev/null || printf 1)" = 0 ] || return 1
	find "$lyona_trust_path" -maxdepth 0 -type f ! -perm /022 -print -quit 2>/dev/null | grep -q .
}
