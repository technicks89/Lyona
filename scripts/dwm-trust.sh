# shellcheck shell=sh
#
# Trust checks for a file run with more rights than the caller's own (Sync
# Sprint 12 S12-14). POSIX, so the Bash and the sh helpers source the same
# text. The two root helpers keep a byte-identical copy of the two functions
# between "BEGIN dwm-trust.sh" and "END dwm-trust.sh", since a root helper
# sources nothing at run time (decision D-21); tests/test-shell-contracts.sh
# fails if the copies differ. The variables are prefixed rather than local, so
# the file stays POSIX.

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
