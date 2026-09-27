#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 12 S12-01: lyona-update-root keeps its own, root-only system
# backups, and a rollback restores only those. Runs the real helper as root, so
# it refuses to run anywhere but a disposable container (the same rule as
# tests/test-settings-display-security.sh).
#
# Part 1 needs only the helper and tar: restore-system refuses a path, a bad id,
# a backup store or backup that is not private to root, a non-root-owned archive
# and members outside the managed locations, and restores a good backup exactly.
# Part 2 builds a real release and runs install-system release: the helper reads
# the tarball and config.h only with the invoking user's permissions into its own
# copy and refuses a wrong digest (S12-02), backs up the live files as root before
# installing, prunes old backups, and a rollback brings the live file back. Part 2
# needs the build dependencies; without them it is skipped and says so.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

[[ ${DWM_SECURITY_CONTAINER:-0} == 1 ]] || {
	printf 'SKIP: privileged update-helper backup test is container-only\n'
	exit 77
}
[[ -e /.dockerenv || -e /run/.containerenv ]] || {
	printf 'Refusing to modify installed paths outside a disposable container\n' >&2
	exit 1
}
[[ $EUID == 0 ]] || {
	printf 'The container backup test must run as root\n' >&2
	exit 1
}

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

prefix=/usr/local
helper=$prefix/libexec/lyona/lyona-update-root
store=/var/lib/lyona/backups
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

user=lyonabackuptest
id -u "$user" >/dev/null 2>&1 || useradd -m "$user"
uid=$(id -u "$user")
home=$(getent passwd "$user" | cut -d: -f6)

install_helper() {
	sed -e "s|@PREFIX@|$prefix|g" -e "s|@MANPREFIX@|$prefix/share/man|g" \
		-e "s|@DATADIR@|$prefix/share|g" -e "s|@XSESSIONSDIR@|/usr/share/xsessions|g" \
		"$repo/scripts/lyona-update-root" |
		install -D -o root -g root -m 0755 /dev/stdin "$helper"
}

run_helper() {
	env -i PATH=/usr/bin:/bin PKEXEC_UID="$uid" "$helper" "$@"
}

refuses() { # MESSAGE-FRAGMENT ARGS...: the helper must fail, saying MESSAGE-FRAGMENT
	local want=$1
	shift
	if run_helper "$@" >"$work/out" 2>"$work/err"; then
		fail "helper accepted: $*"
	fi
	grep -Fq -- "$want" "$work/err" || {
		cat "$work/err" >&2
		fail "helper refused '$*' for the wrong reason (wanted: $want)"
	}
}

install_helper
rm -rf "$store"

# --- Part 1: restore-system ------------------------------------------------

bin_file=$prefix/bin/dwm-display-setup
install -D -o root -g root -m 0755 /dev/null "$bin_file"
printf 'v1\n' >"$bin_file"

good_id=20260927T101500Z-4242
make_root_backup() { # ID: a backup as the helper would make it, of $bin_file
	install -d -o root -g root -m 0700 "$store" "$store/$1"
	tar -C / --numeric-owner -cpf "$store/$1/system-files.tar" "${bin_file#/}"
}

# A path, or anything that is not an id, is refused before anything is read.
user_backups=$home/.local/state/lyona/live-update-backups/$good_id
install -d -o "$uid" -g "$uid" -m 0700 "$user_backups"
refuses 'malformed backup id' restore-system "$user_backups"
refuses 'malformed backup id' restore-system ../../etc
refuses 'malformed backup id' restore-system "$good_id/.."
refuses 'malformed backup id' restore-system ''
refuses 'requires a backup id' restore-system

# No store yet, then a store without that backup.
refuses 'nothing to restore' restore-system "$good_id"
install -d -o root -g root -m 0700 "$store"
refuses 'no system backup was kept' restore-system "$good_id"

make_root_backup "$good_id"
printf 'v2\n' >"$bin_file"

# The store must be private to root.
chmod 0750 "$store"
refuses 'not a private root-owned directory' restore-system "$good_id"
chmod 0700 "$store"
chown "$uid" "$store"
refuses 'not a private root-owned directory' restore-system "$good_id"
chown root "$store"

# So must the backup: a user-owned one, or a symlink to one, is refused.
chown "$uid" "$store/$good_id"
refuses 'no system backup was kept' restore-system "$good_id"
chown root "$store/$good_id"
planted_id=20260927T101600Z-4343
planted=$home/planted
install -d -o "$uid" -g "$uid" -m 0700 "$planted"
cp -p "$store/$good_id/system-files.tar" "$planted/system-files.tar"
ln -s "$planted" "$store/$planted_id"
refuses 'no system backup was kept' restore-system "$planted_id"
rm "$store/$planted_id"

# The archive must be root's.
chown "$uid" "$store/$good_id/system-files.tar"
refuses 'missing or not root-owned' restore-system "$good_id"
chown root "$store/$good_id/system-files.tar"

# Defence in depth: members outside the managed locations are refused, and
# nothing is written.
bad_id=20260927T101700Z-4444
install -d -o root -g root -m 0700 "$store/$bad_id"
install -D -m 0644 /dev/null "$work/stage/etc/cron.d/lyona-planted"
tar -C "$work/stage" --numeric-owner -cpf "$store/$bad_id/system-files.tar" etc/cron.d/lyona-planted
refuses 'outside the managed install locations' restore-system "$bad_id"
[[ ! -e /etc/cron.d/lyona-planted ]] || fail 'a refused archive wrote a file'
install -D -m 0755 /dev/null "$work/stage2/${bin_file#/}"
chmod 4755 "$work/stage2/${bin_file#/}"
tar -C "$work/stage2" --numeric-owner -cpf "$store/$bad_id/system-files.tar" "${bin_file#/}"
refuses 'setuid, setgid, or sticky' restore-system "$bad_id"
install -d "$work/stage3/${prefix#/}/bin"
ln -s /etc/shadow "$work/stage3/${prefix#/}/bin/dwm-planted-link"
tar -C "$work/stage3" --numeric-owner -cpf "$store/$bad_id/system-files.tar" "${prefix#/}/bin/dwm-planted-link"
refuses 'symlink outside the cursor themes' restore-system "$bad_id"
[[ ! -L $prefix/bin/dwm-planted-link ]] || fail 'a refused archive wrote a symlink'
rm -rf "${store:?}/$bad_id"

# A good backup restores the live file exactly as it was recorded.
run_helper restore-system "$good_id" >/dev/null 2>"$work/err" || {
	cat "$work/err" >&2
	fail 'a good root-held backup did not restore'
}
[[ $(cat "$bin_file") == v1 ]] || fail 'restore did not bring back the backed-up contents'
[[ $(stat -c '%u %a' "$bin_file") == '0 755' ]] || fail "restored owner/mode: $(stat -c '%u %a' "$bin_file")"
printf 'restore-system checks: PASS\n'

# --- Part 2: install-system release takes the backup -------------------------

if ! command -v pkg-config >/dev/null 2>&1 || ! make -s -C "$repo" check-build-deps >/dev/null 2>&1; then
	printf 'SKIP: part 2 (install-system release backups) needs the build dependencies\n'
	printf 'Update-helper backups: PASS (part 1 only)\n'
	exit 0
fi

rm -rf "$store"
src=$work/src
cp -a "$repo/." "$src"
rm -f "$src/config.h"
make -s -C "$src" clean >/dev/null
# The live install the update will replace, with a marker the release lacks.
make -s -C "$src" all >/dev/null
make -s -C "$src" install-system >/dev/null
install_helper
live=$prefix/bin/dwm-status
printf '# live-before-update\n' >>"$live"
version=$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' "$src/config.mk")
# install-system release builds from a source tree (it reads config.mk and runs
# make), so the test gives it one. (`make release` produces a runtime bundle with
# no Makefile; that mismatch is tracked separately, not by this test.)
make -s -C "$src" clean >/dev/null
cp -a "$src" "$work/lyona-$version"
rm -rf "$work/lyona-$version/.git" "$work/lyona-$version/release"
updates=$home/.local/state/lyona/updates
install -d -o "$uid" -g "$uid" -m 0700 "$home/.local" "$home/.local/state" \
	"$home/.local/state/lyona" "$updates"
tarball=$updates/lyona-$version.tar.gz
tar -C "$work" -czf "$tarball" "lyona-$version"
chown "$uid:$uid" "$tarball"
chmod 0644 "$tarball"
sha=$(sha256sum "$tarball" | awk '{ print $1 }')

# Six backups dated after the new one, so pruning must reserve its slot.
install -d -o root -g root -m 0700 "$store"
for n in 1 2 3 4 5 6; do
	install -d -o root -g root -m 0700 "$store/20000101T00000${n}Z-1"
done

new_id=19990101T000000Z-$$
refuses 'malformed backup id' install-system release "$tarball" "$sha" "$version" - ../x
refuses 'requires a tarball' install-system release "$tarball" "$sha" "$version" -

# S12-02: the digest is checked on root's own copy, and both inputs are read with
# the invoking user's permissions. Root could read a mode-000 file; the user cannot.
wrong_sha=$(printf '%064d' 0)
refuses 'checksum does not match' install-system release "$tarball" "$wrong_sha" "$version" - "$new_id"
chmod 0000 "$tarball"
refuses 'could not read the tarball as the invoking user' \
	install-system release "$tarball" "$sha" "$version" - "$new_id"
chmod 0644 "$tarball"
ln -s "$tarball" "$updates/linked.tar.gz"
refuses 'not a safe, user-owned file' install-system release "$updates/linked.tar.gz" "$sha" "$version" - "$new_id"
rm "$updates/linked.tar.gz"
config_h=$home/config.h
install -o "$uid" -g "$uid" -m 0000 "$repo/config.def.h" "$config_h"
refuses 'could not read config.h as the invoking user' \
	install-system release "$tarball" "$sha" "$version" "$config_h" "$new_id"
chmod 0644 "$config_h"
[[ ! -e $store/$new_id ]] || fail 'a refused install left a system backup behind'

run_helper install-system release "$tarball" "$sha" "$version" "$config_h" "$new_id" >"$work/install.out" 2>&1 || {
	tail -40 "$work/install.out" >&2
	fail 'install-system release failed'
}

[[ $(stat -c '%u %a' "$store/$new_id") == '0 700' ]] || fail 'the new system backup is not private to root'
# Listed into files first: under pipefail, grep -q closing the pipe early would
# make tar's SIGPIPE fail the check.
tar -xOf "$store/$new_id/system-files.tar" "${live#/}" >"$work/backed-up-live"
grep -Fxq '# live-before-update' "$work/backed-up-live" ||
	fail 'the backup does not hold the live file as it was before the update'
tar -tf "$store/$new_id/system-files.tar" >"$work/backup-list"
grep -Fxq "${helper#/}" "$work/backup-list" ||
	fail 'the backup does not hold the privileged helper'
! grep -Fxq '# live-before-update' "$live" || fail 'the update did not replace the live file'
kept=$(find "$store" -mindepth 1 -maxdepth 1 -type d | wc -l)
[[ $kept == 5 ]] || fail "pruning kept $kept backups, not 5"
[[ -d $store/$new_id ]] || fail 'pruning removed the newly created backup'

run_helper restore-system "$new_id" >/dev/null 2>"$work/err" || {
	cat "$work/err" >&2
	fail 'rolling back to the new backup failed'
}
grep -Fxq '# live-before-update' "$live" || fail 'the rollback did not bring the live file back'
printf 'install-system release inputs and backups: PASS\n'
printf 'Update-helper backups: PASS\n'
