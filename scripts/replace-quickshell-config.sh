#!/bin/sh
# replace-quickshell-config.sh SOURCE TARGET: replace the managed Quickshell
# config TARGET (~/.config/quickshell) with the tree SOURCE, for install-user
# (#461).
#
# The new tree is built beside the live one and swapped in at once, so a
# running shell never sees its config missing or half copied: two renames
# where the filesystem cannot exchange. And a shell that still watches its
# config files, started from a release older than #461, is stopped first and
# started again after: it would hot-reload the new tree, and Quickshell 0.3.2
# crashes when a shell that has reloaded is stopped, as the restart after an
# update does. A shell of #461 or later does not watch its files, so it is left
# running for the caller to restart.

set -eu

lyona_lib=${0%/*}
[ "$lyona_lib" != "$0" ] || lyona_lib=.

[ "$#" -eq 2 ] || {
	printf 'usage: %s SOURCE TARGET\n' "${0##*/}" >&2
	exit 2
}
source_dir=$1
target=$2
parent=$(dirname -- "$target")
name=$(basename -- "$target")
staged=$parent/.$name.new
previous=$parent/.$name.old

rm -rf "$staged" "$previous"
mkdir -p "$staged"
cp -aL --no-preserve=ownership "$source_dir"/. "$staged"/

# shellcheck source=scripts/dwm-quickshell-lifecycle.sh
. "$lyona_lib/dwm-quickshell-lifecycle.sh"
stopped=$(quickshell_stop_watching "$target/shell.qml")
# start_stopped: start the shell stopped above again, however this script
# ends, so a failed swap does not leave the session without one.
start_stopped() {
	[ -n "$stopped" ] || return 0
	"$lyona_lib/dwm-quickshell-controlcenter" action start-quickshell >/dev/null 2>&1 ||
		printf '  Warning: Quickshell did not start again; log out and back in to start it.\n' >&2
}
trap start_stopped EXIT
[ -z "$stopped" ] ||
	printf '  Stopped the running Quickshell while its config is replaced.\n'

if [ ! -e "$target" ] && [ ! -L "$target" ]; then
	mv -T "$staged" "$target"
elif ! mv --exchange -T "$staged" "$target" 2>/dev/null; then
	mv -T "$target" "$previous"
	if ! mv -T "$staged" "$target"; then
		mv -T "$previous" "$target" ||
			printf '  Warning: the previous Quickshell config is kept in %s.\n' "$previous" >&2
		exit 1
	fi
fi
rm -rf "$staged" "$previous"
