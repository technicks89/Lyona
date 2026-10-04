#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 12 S12-11 item 7: the ISO installer's credentials survive any
# passphrase. write_credentials_json is extracted from lyona-install.sh and run with
# passwords that broke the old interpolated JSON (a '"') or silently changed in it
# (a backslash escape, which locked the user out of the new install). The values
# must come back out of the JSON exactly. The password is hashed through stdin,
# never passed in argv.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
command -v jq >/dev/null 2>&1 || {
	printf 'SKIP: jq is unavailable\n'
	exit 77
}

installer=$repo/archiso/airootfs/root/lyona-install.sh
sed -n '/^write_credentials_json() {$/,/^}$/p' "$installer" >"$work/creds.sh"
[[ -s $work/creds.sh ]] || fail 'write_credentials_json not found in lyona-install.sh'
# shellcheck disable=SC1091 # generated above
. "$work/creds.sh"

check_round_trip() { # USERNAME HASH PASSPHRASE ENCRYPT
	# Read by write_credentials_json.
	# shellcheck disable=SC2034
	USERNAME=$1 ENCRYPTION_PASSWORD=$3 ENCRYPT=$4
	write_credentials_json "$2" >"$work/creds.json" || fail "write_credentials_json failed for: $3"
	jq -e . "$work/creds.json" >/dev/null || fail "not valid JSON for passphrase: $3"
	[[ $(jq -r '.users[0].username' "$work/creds.json") == "$1" ]] || fail 'the username changed'
	[[ $(jq -r '.users[0].enc_password' "$work/creds.json") == "$2" ]] || fail 'the user hash changed'
	# Root gets no password: the user administers through sudo (decision R16-18).
	[[ $(jq -r 'has("root_enc_password")' "$work/creds.json") == false ]] || fail 'root was given a password'
	[[ $(jq -r '.users[0].sudo' "$work/creds.json") == true ]] || fail 'the user lost sudo'
	if [[ $4 == 1 ]]; then
		[[ $(jq -r '.encryption_password' "$work/creds.json") == "$3" ]] ||
			fail "the disk passphrase changed: $3"
	else
		[[ $(jq -r 'has("encryption_password")' "$work/creds.json") == false ]] ||
			fail 'an encryption passphrase was written without encryption'
	fi
}

# shellcheck disable=SC2016 # a literal crypt hash
hash='$6$salt$abcdefghijklmnopqrstuvwxyz0123456789./ABCDEFG'
for passphrase in 'plain' 'quote"inside' 'back\slash' 'escape\n\t\u0041' "it's" \
	'{"json":true}' 'ünïcödé 密码' ' leading and trailing '; do
	check_round_trip lyona "$hash" "$passphrase" 1
done
check_round_trip lyona "$hash" 'unused' 0

# The hash and the disk passphrase reach jq on stdin, never as arguments.
if grep -Eq -- '--arg (hash|passphrase)' "$work/creds.sh"; then
	fail 'the password hash or the disk passphrase is passed to jq in argv'
fi

# The password reaches openssl on stdin, never as an argument.
grep -Fq "| openssl passwd -6 -stdin" "$installer" || fail 'openssl passwd does not read the password from stdin'
# shellcheck disable=SC2016 # matches the source text
if grep -Eq 'openssl passwd -6 "\$PASSWORD"' "$installer"; then
	fail 'the password is still passed to openssl in argv'
fi

# The host name is RFC 1123 before it goes into the JSON (Sync Sprint 16 R16-17).
sed -n '/^valid_hostname() {$/,/^}$/p' "$installer" >"$work/hostname.sh"
[[ -s $work/hostname.sh ]] || fail 'valid_hostname not found in lyona-install.sh'
# shellcheck disable=SC1091 # generated above
. "$work/hostname.sh"
long_label=$(printf 'a%.0s' {1..63})
# 253 characters, the longest a name may be.
longest=$(printf 'abcdefgh.%.0s' {1..28})x
for name in lyona my-pc PC01 a host.example.org "$long_label" "$longest"; do
	valid_hostname "$name" || fail "a valid host name was refused: $name"
done
for name in '' '-pc' 'pc-' 'my pc' 'pc"x' 'pc\x' 'a..b' '.pc' 'pc.' 'pc_1' "${long_label}a" \
	"${longest}y" $'pc\nx'; do
	if valid_hostname "$name"; then
		fail "an invalid host name was accepted: $name"
	fi
done
# shellcheck disable=SC2016 # the literal text in the installer
grep -Fq 'valid_hostname "$name" && break' "$installer" || fail 'ask_hostname does not validate the name'

# The postinstall locks root on the new system (R16-18).
# shellcheck disable=SC2016 # the literal text in the postinstall
grep -Fqx 'arch-chroot "$TARGET" passwd -l root >/dev/null' "$repo/archiso/airootfs/root/lyona-postinstall.sh" ||
	fail 'the postinstall does not lock root'

printf '%s\n' 'ISO installer credentials (jq-built JSON, passphrases round-trip, password via stdin): PASS'
