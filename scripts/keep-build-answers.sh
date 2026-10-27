#!/bin/sh
# keep-build-answers.sh LYONA_CONFIG_DIR: keep this checkout's dwm build
# choices for lyona-update, for install-user (decision D-18, #464).
#
# A config.h that configure-build.sh made is kept as its answers, in
# LYONA_CONFIG_DIR/build.conf, from which lyona-update makes each release's
# config.h from that release's config.def.h: a copy of the file itself would go
# stale as config.def.h changes. A config.h edited in any other way is copied to
# LYONA_CONFIG_DIR/config.h once, and never overwritten. An earlier copy that
# holds nothing but answers, as every fresh install's did while #464 made each
# one differ from config.def.h, becomes build.conf, and the copy is kept beside
# it as config.h.bak.TIME.

set -eu

lyona_lib=${0%/*}
[ "$lyona_lib" != "$0" ] || lyona_lib=.
repo=$(dirname -- "$lyona_lib")

[ "$#" -eq 1 ] || {
	printf 'usage: %s LYONA_CONFIG_DIR\n' "${0##*/}" >&2
	exit 2
}
config_dir=$1
user_config=$config_dir/config.h
answers_file=$config_dir/build.conf

derive() {
	"$lyona_lib/configure-build.sh" --derive "$1" --template "$repo/config.def.h" 2>/dev/null
}

write_answers() {
	mkdir -p "$config_dir"
	answers_new=$(mktemp "$answers_file.XXXXXX")
	{
		printf '%s\n' "# The dwm build answers (scripts/configure-build.sh --help), one a line."
		printf '%s\n' "# lyona-update makes each release's config.h from its config.def.h with them."
		printf '%s\n' "$1"
	} >"$answers_new"
	chmod 0644 "$answers_new"
	mv -fT "$answers_new" "$answers_file"
}

if [ -f "$user_config" ]; then
	[ ! -e "$answers_file" ] || exit 0
	answers=$(derive "$user_config") || exit 0
	backup=$user_config.bak.$(date +%Y%m%d-%H%M%S)
	write_answers "$answers"
	mv -fT "$user_config" "$backup"
	printf '  %s held only dwm build answers: they are now in %s, and the file is kept as %s.\n' \
		"$user_config" "$answers_file" "$backup"
	exit 0
fi

[ -f "$repo/config.h" ] || exit 0
! cmp -s "$repo/config.h" "$repo/config.def.h" || exit 0
if answers=$(derive "$repo/config.h"); then
	[ ! -e "$answers_file" ] || exit 0
	write_answers "$answers"
	printf '  Saved your dwm build answers to %s; lyona-update builds with them.\n' "$answers_file"
else
	install -Dm644 "$repo/config.h" "$user_config"
	printf '  Copied your customised config.h to %s; lyona-update builds with it.\n' "$user_config"
fi
