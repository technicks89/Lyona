#!/bin/sh
# #280 VM: a live backup is labelled with the installed version it holds, from
# /etc/lyona-release (read by lyona-version, with its ownership checks), not
# with the release about to replace it. A rollback to beta.5 said "Log in now to
# start using 2026.10.0-beta.6".

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

home=$work/home
mkdir -p "$home/.config" "$home/.local/share" "$home/.local/state/lyona"
# The account's install record, which a rollback puts back (#324 VM).
printf 'LYONA_USER_VERSION=2026.10.0-beta.5\n' >"$home/.local/state/lyona/install.state"
record=$work/lyona-release
printf '%s\n' 'LYONA_VERSION=2026.10.0-beta.5' 'LYONA_COMMIT=fb7e28c' 'LYONA_SOURCE=iso' \
	'LYONA_PREFIX=/usr/local' 'LYONA_INSTALL_DATE=2026-10-08T00:00:00Z' >"$record"

# shellcheck disable=SC2016 # expanded by the inner shell
LYONA_INSTALL_REPO_DIR=$repo USER_HOME=$home HOME=$home PREFIX=$work/prefix \
	MANPREFIX=$work/prefix/share/man XSESSIONSDIR=$work/xsessions DATADIR=$work/data \
	XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share XDG_STATE_HOME=$home/.local/state \
	LYONA_TEST_WORK=$work DWM_TEST_SYSTEM_RECORD=$record DWM_TEST_SYSTEM_OWNER="$(id -u)" \
	version_helper=$repo/scripts/lyona-version bash -c '
		set -e
		. "$LYONA_INSTALL_REPO_DIR/scripts/lyona-install-verify.sh"
		prepare_expected_files
		backup_live_install
		cat "$backup_dir/checkout.txt"
		cp "$backup_dir/install.state" "$LYONA_TEST_WORK/kept-install.state" 2>/dev/null || :
	' >"$work/checkout.txt" 2>"$work/err" || {
	cat "$work/err" >&2
	fail 'backup_live_install failed'
}

assert_line() {
	grep -Fxq -- "$1" "$work/checkout.txt" || {
		lyona_show_file "$work/checkout.txt"
		fail "the backup record lacks: $1"
	}
}
assert_line 'version=2026.10.0-beta.5'
assert_line 'commit=fb7e28c'
assert_line 'source=iso'
staged=$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' "$repo/config.mk")
if grep -Fxq "version=$staged" "$work/checkout.txt" && [ "$staged" != 2026.10.0-beta.5 ]; then
	fail "the backup is labelled with the release being installed ($staged)"
fi

cmp -s "$home/.local/state/lyona/install.state" "$work/kept-install.state" ||
	fail 'the backup does not keep the account install record (install.state)'

printf 'Live backups name the version they hold: PASS\n'
