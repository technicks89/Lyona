#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

# Run the actual cleanup recipe in isolated path layouts without installing
# desktop settings for every case.
{
	printf 'cleanup:\n'
	sed -n '/^\tcleanup_data=1;/,/^\tfi$/p' "$repo/Makefile"
} >"$work/cleanup.mk"
for layout in same ancestor descendant sibling prefix missing symlink root; do
	base=$work/$layout
	checkout=$base/checkout
	data=$base/data
	expect=remove
	case $layout in
	same)
		data=$checkout
		expect=keep
		;;
	ancestor)
		checkout=$data/scripts/checkout
		expect=keep
		;;
	descendant)
		data=$checkout/data
		expect=keep
		;;
	prefix) data=$checkout-other ;;
	symlink)
		data=$base/alias
		expect=keep
		;;
	root)
		checkout=/
		expect=keep
		;;
	esac
	mkdir -p "$checkout" "$base"
	if [ "$layout" = symlink ]; then
		ln -s "$checkout" "$data"
	fi
	if [ "$layout" != missing ]; then
		mkdir -p "$data/config" "$data/scripts"
		printf 'legacy config\n' >"$data/config/marker"
		printf 'legacy script\n' >"$data/scripts/marker"
	fi
	make -s -C "$checkout" -f "$work/cleanup.mk" "DATA_DIR=$data" cleanup
	if [ "$expect" = keep ]; then
		assert_file "$data/config/marker"
		assert_file "$data/scripts/marker"
	else
		assert_no_file "$data/config"
		assert_no_file "$data/scripts"
	fi
done

# Exercise library traps in a separate process so EXIT and signal status are
# observable. Arch's /bin/sh is Bash; --posix also covers its sh mode.
for chained in no yes; do
	for event in success failure HUP INT TERM; do
		case $event in
		success) expected=0 ;;
		failure) expected=7 ;;
		HUP) expected=129 ;;
		INT) expected=130 ;;
		TERM) expected=143 ;;
		esac
		probe=$work/$chained-$event
		mkdir -p "$probe"
		status=0
		# The managed runner backgrounds its child; reset inherited ignored
		# signals before exec so this fixture starts with normal dispositions.
		# shellcheck disable=SC2016 # Variables expand in the child shell.
		USER_HOME=$probe LYONA_INSTALL_REPO_DIR=$repo python3 -c '
import os, signal, sys
for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(sig, signal.SIG_DFL)
os.execvp(sys.argv[1], sys.argv[1:])
' bash --posix -c '
			set -eu
			probe=$1
			previous_exit() {
				[ ! -e "$work" ] || exit 99
				printf "%s\n" "$install_verify_exit_status" >>"$probe/exits"
			}
			[ "$2" != yes ] || trap previous_exit EXIT
			. "$LYONA_INSTALL_REPO_DIR/scripts/lyona-install-verify.sh"
			printf "%s\n" "$work" >"$probe/work"
			case $3 in
			success) exit 0 ;;
			failure) exit 7 ;;
			*) kill -s "$3" "$$" ;;
			esac
			printf "continued\n" >"$probe/continued"
		' bash "$probe" "$chained" "$event" || status=$?
		[ "$status" -eq "$expected" ] || fail "$event exited $status, expected $expected"
		assert_no_file "$(cat "$probe/work")"
		assert_no_file "$probe/continued"
		if [ "$chained" = yes ]; then
			[ "$(cat "$probe/exits")" = "$expected" ] || fail "EXIT handler status/count: $event"
		fi
	done
done

# A library must leave caller-owned (including ignored) signals intact.
USER_HOME=$work LYONA_INSTALL_REPO_DIR=$repo bash --posix -c '
	set -eu
	trap "exit 42" HUP
	trap "" INT
	trap "exit 43" TERM
	before=$(trap -p HUP INT TERM)
	. "$LYONA_INSTALL_REPO_DIR/scripts/lyona-install-verify.sh"
	[ "$(trap -p HUP INT TERM)" = "$before" ]
'

for legacy in none scripts config both symlink; do
	probe=$work/backup-$legacy
	mkdir -p "$probe/data/lyona"
	printf 'user data\n' >"$probe/data/lyona/other"
	case $legacy in
	scripts | both)
		mkdir -p "$probe/data/lyona/scripts"
		printf 'script\n' >"$probe/data/lyona/scripts/marker"
		;;
	esac
	case $legacy in
	config | both)
		mkdir -p "$probe/data/lyona/config"
		printf 'config\n' >"$probe/data/lyona/config/marker"
		;;
	symlink) ln -s missing "$probe/data/lyona/config" ;;
	esac
	USER_HOME=$probe PREFIX=$probe/prefix DATADIR=$probe/system-data \
		XSESSIONSDIR=$probe/xsessions XDG_DATA_HOME=$probe/data \
		XDG_STATE_HOME=$probe/state XDG_CONFIG_HOME=$probe/config \
		LYONA_INSTALL_REPO_DIR=$repo bash --posix -c '
		set -eu
		probe=$1
		. "$LYONA_INSTALL_REPO_DIR/scripts/lyona-install-verify.sh"
		prepare_expected_files
		backup_live_install
		printf "%s\n" "$backup_dir" >"$probe/backup"
	' bash "$probe"
	backup=$(cat "$probe/backup")
	if [ "$legacy" = none ]; then
		assert_no_file "$backup/lyona-data.tar"
	else
		assert_file "$backup/lyona-data.tar"
		sha256sum -c "$backup/SHA256SUMS"
		mv "$probe/data/lyona" "$probe/original"
		tar -C "$probe/data" -xpf "$backup/lyona-data.tar"
		if [ "$legacy" = symlink ]; then
			[ "$(readlink "$probe/data/lyona/config")" = missing ] || fail 'legacy symlink not restored'
			rm "$probe/data/lyona/config" "$probe/original/config"
		fi
		diff -r "$probe/original" "$probe/data/lyona"
	fi
done

printf 'Install cleanup, signal handling and legacy backup: PASS\n'
