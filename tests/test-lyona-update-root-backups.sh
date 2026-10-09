#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 12 S12-01 to S12-03: lyona-update-root keeps its own, root-only system
# backups, and a rollback restores only those. Runs the real helper as root, so
# it refuses to run anywhere but a disposable container (the same rule as
# tests/test-settings-display-security.sh).
#
# Part 1 needs only the helper and tar: restore-system refuses a path, a bad id,
# a backup store or backup that is not private to root, a non-root-owned archive
# and members outside the managed locations, and restores a good backup exactly.
# Part 2 builds a real release. install-system release refuses it without a
# signature it verifies itself (GHSA-x538-46gg-v37h). install-unverified release
# (the checksum-only path, on its own polkit prompt) installs it: the helper reads
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

datadir=/usr/share
install_helper() { # as install-system does, for $prefix and $datadir
	sed -e "s|@PREFIX@|$prefix|g" -e "s|@MANPREFIX@|$prefix/share/man|g" \
		-e "s|@DATADIR@|$datadir|g" -e "s|@XSESSIONSDIR@|/usr/share/xsessions|g" \
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

# Cursor themes, in DATADIR and in PREFIX/share where updates before
# 2026.10.0-beta.6 put them (#280 VM: a rollback refused usr/share/icons),
# restore.
cursor_id=20260927T101800Z-4545
install -d -o root -g root -m 0700 "$store/$cursor_id"
for icons in "$datadir/icons" "$prefix/share/icons"; do
	install -D -m 0644 /dev/null "$work/stage4$icons/Capitaine-Cursors/index.theme"
	printf 'from %s\n' "$icons" >"$work/stage4$icons/Capitaine-Cursors/index.theme"
done
tar -C "$work/stage4" --numeric-owner -cpf "$store/$cursor_id/system-files.tar" \
	"${datadir#/}/icons/Capitaine-Cursors" "${prefix#/}/share/icons/Capitaine-Cursors"
run_helper restore-system "$cursor_id" >/dev/null 2>"$work/err" || {
	cat "$work/err" >&2
	fail 'a backup of the cursor themes (DATADIR and PREFIX/share) did not restore'
}
for icons in "$datadir/icons" "$prefix/share/icons"; do
	grep -Fxq "from $icons" "$icons/Capitaine-Cursors/index.theme" ||
		fail "the cursor theme in $icons was not restored"
done
rm -rf "${store:?}/$cursor_id" "$datadir/icons/Capitaine-Cursors" "$prefix/share/icons/Capitaine-Cursors"
rm -f "$home/.local/state/lyona/update.log"

# The layout comes from /etc/lyona-release (#280 VM): only a root-owned record
# that nobody else can write, and only absolute plain paths, are used.
stamp=/etc/lyona-release
[[ ! -e $stamp ]] || mv "$stamp" "$work/stamp.saved"
write_stamp() { # LINE...
	printf '%s\n' 'LYONA_VERSION=test' "LYONA_PREFIX=$prefix" "$@" |
		install -o root -g root -m 0644 /dev/stdin "$stamp"
}
write_stamp "LYONA_DATADIR=$datadir"
chmod 0664 "$stamp"
refuses 'not a root-owned, root-only-writable record' restore-system "$good_id"
chmod 0644 "$stamp"
chown "$uid" "$stamp"
refuses 'not a root-owned, root-only-writable record' restore-system "$good_id"
write_stamp 'LYONA_DATADIR=relative/share'
refuses 'unusable LYONA_DATADIR' restore-system "$good_id"
write_stamp 'LYONA_DATADIR=/usr/share/../../etc'
refuses 'unusable LYONA_DATADIR' restore-system "$good_id"
write_stamp 'LYONA_MANPREFIX=/usr/share/man with space'
refuses 'unusable LYONA_MANPREFIX' restore-system "$good_id"
# A record for another PREFIX is not this install's: the standard layout stays,
# so this helper still refuses a DATADIR it was not installed for.
printf '%s\n' 'LYONA_VERSION=test' 'LYONA_PREFIX=/opt/elsewhere' 'LYONA_DATADIR=/srv/other' |
	install -o root -g root -m 0644 /dev/stdin "$stamp"
other_id=20260927T101900Z-4646
install -d -o root -g root -m 0700 "$store/$other_id"
install -D -m 0644 /dev/null "$work/stage5/srv/other/icons/Capitaine-Cursors/index.theme"
tar -C "$work/stage5" --numeric-owner -cpf "$store/$other_id/system-files.tar" srv/other/icons/Capitaine-Cursors
refuses 'outside the managed install locations' restore-system "$other_id"
# ... and the record for this PREFIX moves it.
write_stamp 'LYONA_DATADIR=/srv/other'
run_helper restore-system "$other_id" >/dev/null 2>"$work/err" || {
	cat "$work/err" >&2
	fail 'a backup of the cursor themes in the recorded DATADIR did not restore'
}
rm -rf "${store:?}/$other_id" /srv/other "$stamp"
[[ ! -e $work/stamp.saved ]] || mv "$work/stamp.saved" "$stamp"
rm -f "$home/.local/state/lyona/update.log"

# A good backup restores the live file exactly as it was recorded.
chown -R "$uid:$uid" "$home/.local"
run_helper restore-system "$good_id" >/dev/null 2>"$work/err" || {
	cat "$work/err" >&2
	fail 'a good root-held backup did not restore'
}
[[ $(cat "$bin_file") == v1 ]] || fail 'restore did not bring back the backed-up contents'
[[ $(stat -c '%u %a' "$bin_file") == '0 755' ]] || fail "restored owner/mode: $(stat -c '%u %a' "$bin_file")"

# S12-03: the helper's log, in the user's home, is written as the user, so a
# symlink planted there never makes root create or append to another file.
log=$home/.local/state/lyona/update.log
[[ -f $log && $(stat -c '%u %a' "$log") == "$uid 600" ]] ||
	fail "the helper log is not the user's own 0600 file: $(stat -c '%u %a' "$log" 2>&1)"
grep -Fq "$(printf 'restore-system\tunknown\t%s\tsucceeded' "$good_id")" "$log" ||
	fail 'the helper did not log the restore'
rm -f "$log"
ln -s /etc/lyona-planted-log "$log"
run_helper restore-system "$good_id" >/dev/null 2>"$work/err" || {
	cat "$work/err" >&2
	fail 'a restore with a planted log symlink failed'
}
[[ ! -e /etc/lyona-planted-log ]] || fail 'root wrote through a symlink planted at the log path'
rm -f "$log"
printf 'restore-system checks: PASS\n'

# --- Part 2: install-unverified release takes the backup; install-system needs a signature -------------------------

if ! command -v pkg-config >/dev/null 2>&1 || ! make -s -C "$repo" check-build-deps >/dev/null 2>&1; then
	printf 'SKIP: part 2 (install-system release backups) needs the build dependencies\n'
	printf 'Update-helper backups: PASS (part 1 only)\n'
	exit 0
fi

rm -rf "$store"
# A DATADIR that is not the Makefile default: the helper must install the
# update there too, and record it in the helper it installs (#280 VM).
datadir=/srv/lyona-data
src=$work/src
cp -a "$repo/." "$src"
rm -f "$src/config.h"
make -s -C "$src" clean >/dev/null
# The live install the update will replace, with a marker the release lacks.
make -s -C "$src" all >/dev/null
make -s -C "$src" install-system DATADIR="$datadir" >/dev/null
# S12-03: the source tree is owned by the building user, not root; the cursor
# themes it installs as root must still come out root-owned.
[[ $(stat -c %u "$src/assets/cursors") != 0 ]] || chown -R "$uid:$uid" "$src/assets/cursors"
make -s -C "$src" install-cursors DATADIR="$datadir" >/dev/null
not_root=$(find "$datadir/icons/Capitaine-Cursors" "$datadir/icons/Capitaine-Cursors-White" \
	! -uid 0 -print -quit)
[[ -z $not_root ]] || fail "install-cursors left a file not owned by root: $not_root"
install_helper
live=$prefix/bin/dwm-status
printf '# live-before-update\n' >>"$live"
version=$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' "$src/config.mk")
# The real release asset (Sync Sprint 12 S12-19): make release's source archive,
# which install-system release builds and installs. The copy keeps its owner from
# the checkout, so git is told, for this one call, to trust it as root.
updates=$home/.local/state/lyona/updates
install -d -o "$uid" -g "$uid" -m 0700 "$home/.local" "$home/.local/state" \
	"$home/.local/state/lyona" "$updates"
tarball=$updates/lyona-$version.tar.gz
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0="$src" \
	make -s -C "$src" release RELEASE_ARCHIVE="$tarball" >/dev/null
chown "$uid:$uid" "$tarball"
chmod 0644 "$tarball"
sha=$(sha256sum "$tarball" | awk '{ print $1 }')

# Six backups dated after the new one, so pruning must reserve its slot.
install -d -o root -g root -m 0700 "$store"
for n in 1 2 3 4 5 6; do
	install -d -o root -g root -m 0700 "$store/20000101T00000${n}Z-1"
done

new_id=19990101T000000Z-$$

# GHSA-x538-46gg-v37h: install-system installs only a release whose signature
# it verifies itself: no bundle, a bundle outside the updates area, or one that
# does not verify, and nothing is installed or backed up.
refuses 'signature bundle' install-system release "$tarball" "$sha" "$version" - "$new_id"
outside_bundle=$home/outside.sigstore.json
install -o "$uid" -g "$uid" -m 0600 /dev/null "$outside_bundle"
refuses 'not under the invoking user' install-system release "$tarball" "$sha" "$version" - "$new_id" "$outside_bundle"
bad_bundle=$updates/lyona-$version.sigstore.json
printf 'not a sigstore bundle\n' | install -o "$uid" -g "$uid" -m 0600 /dev/stdin "$bad_bundle"
if run_helper install-system release "$tarball" "$sha" "$version" - "$new_id" "$bad_bundle" >/dev/null 2>"$work/err"; then
	fail 'install-system installed a release whose signature does not verify'
fi
grep -Eq "signature does not verify|a trusted cosign" "$work/err" ||
	fail "an unverifiable release was refused for another reason: $(cat "$work/err")"
[[ ! -e $store/$new_id ]] || fail 'a release refused for its signature left a system backup behind'
rm -f "$outside_bundle" "$bad_bundle"
refuses 'malformed backup id' install-unverified release "$tarball" "$sha" "$version" - ../x
refuses 'requires a tarball' install-unverified release "$tarball" "$sha" "$version" -

# S12-02: the digest is checked on root's own copy, and both inputs are read with
# the invoking user's permissions. Root could read a mode-000 file; the user cannot.
wrong_sha=$(printf '%064d' 0)
refuses 'checksum does not match' install-unverified release "$tarball" "$wrong_sha" "$version" - "$new_id"
chmod 0000 "$tarball"
refuses 'could not read the tarball as the invoking user' \
	install-unverified release "$tarball" "$sha" "$version" - "$new_id"
chmod 0644 "$tarball"
ln -s "$tarball" "$updates/linked.tar.gz"
refuses 'not a safe, user-owned file' install-unverified release "$updates/linked.tar.gz" "$sha" "$version" - "$new_id"
rm "$updates/linked.tar.gz"
config_h=$home/config.h
install -o "$uid" -g "$uid" -m 0000 "$repo/config.def.h" "$config_h"
refuses 'could not read config.h as the invoking user' \
	install-unverified release "$tarball" "$sha" "$version" "$config_h" "$new_id"
chmod 0644 "$config_h"
[[ ! -e $store/$new_id ]] || fail 'a refused install left a system backup behind'

run_helper install-unverified release "$tarball" "$sha" "$version" "$config_h" "$new_id" >"$work/install.out" 2>&1 || {
	tail -40 "$work/install.out" >&2
	fail 'install-unverified release failed'
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
grep -q "^${datadir#/}/icons/Capitaine-Cursors/" "$work/backup-list" ||
	fail 'the backup does not hold the cursor themes from DATADIR'
grep -Fxq "LYONA_DATADIR=$datadir" /etc/lyona-release ||
	fail "the update did not keep DATADIR $datadir in /etc/lyona-release: $(cat /etc/lyona-release)"
! grep -q '@[A-Z_]*@' "$helper" || fail 'the installed helper still has an install placeholder'
[[ $(sed "s|@PREFIX@|$prefix|g" "$src/scripts/lyona-update-root") == "$(cat "$helper")" ]] ||
	fail 'the installed helper is not the source with @PREFIX@ filled in (what an older update check expects)'
[[ ! -e /usr/share/icons/Capitaine-Cursors && ! -e $prefix/share/icons/Capitaine-Cursors ]] ||
	fail 'the update installed the cursor themes outside DATADIR'
! grep -Fxq '# live-before-update' "$live" || fail 'the update did not replace the live file'
kept=$(find "$store" -mindepth 1 -maxdepth 1 -type d | wc -l)
[[ $kept == 5 ]] || fail "pruning kept $kept backups, not 5"
[[ -d $store/$new_id ]] || fail 'pruning removed the newly created backup'

run_helper restore-system "$new_id" >/dev/null 2>"$work/err" || {
	cat "$work/err" >&2
	fail 'rolling back to the new backup failed'
}
grep -Fxq '# live-before-update' "$live" || fail 'the rollback did not bring the live file back'
printf 'install-system signature refusals, install-unverified inputs and backups: PASS\n'
printf 'Update-helper backups: PASS\n'
