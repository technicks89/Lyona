#!/usr/bin/env bash

set -eu

# A checkout keeps the shared shell code beside the scripts; an install keeps it
# in PREFIX/lib/lyona (Sync Sprint 12 S12-13).
lyona_lib=${0%/*}
[ "$lyona_lib" != "$0" ] || lyona_lib=.
[ -f "$lyona_lib/dwm-xdg.sh" ] || lyona_lib=${lyona_lib%bin}lib/lyona
# shellcheck source=scripts/dwm-xdg.sh
. "$lyona_lib/dwm-xdg.sh"
# shellcheck source=scripts/dwm-desktop-entry.sh
. "$lyona_lib/dwm-desktop-entry.sh"
lyona_xdg_dirs
config_dirs=${XDG_CONFIG_DIRS:-/etc/xdg}
destination_dir=$config_home/autostart
target_owner=${DWM_INSTALL_OWNER:-}
target_group=
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM

if [ -n "$target_owner" ]; then
	target_group=$(id -gn "$target_owner")
fi

find_vendor_entry() {
	entry=$1
	old_ifs=$IFS
	IFS=:
	# shellcheck disable=SC2086
	set -- $config_dirs
	IFS=$old_ifs

	for config_dir; do
		[ -n "$config_dir" ] || continue
		candidate=$config_dir/autostart/$entry
		if [ -f "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

# add_dwm_exclusion SOURCE DEST: SOURCE, hidden from dwm sessions, written to
# DEST through the shared reader and writer (#308): dwm taken out of an
# OnlyShowIn, X-DWM added to a NotShowIn, or NotShowIn=X-DWM; when it has
# neither. An entry with both, or that the reader refuses, is left alone.
add_dwm_exclusion() {
	local only_show not_show only_status=0 not_status=0
	only_show=$(desktop_entry_get "$1" OnlyShowIn) || only_status=$?
	not_show=$(desktop_entry_get "$1" NotShowIn) || not_status=$?
	((only_status <= 1 && not_status <= 1)) || return 1
	((only_status == 1 || not_status == 1)) || return 1
	# A file without a [Desktop Entry] group has no Type.
	desktop_entry_get "$1" Type >/dev/null || return 1
	if ((only_status == 0)); then
		desktop_entry_set "$1" "$2" 'Desktop Entry' OnlyShowIn "$(desktop_list_without "$only_show" X-DWM dwm)"
	elif ((not_status == 0)); then
		desktop_entry_set "$1" "$2" 'Desktop Entry' NotShowIn "$(desktop_list_with "$not_show" X-DWM)"
	else
		desktop_entry_set "$1" "$2" 'Desktop Entry' NotShowIn 'X-DWM;'
	fi
}

if [ ! -e "$destination_dir" ] && [ ! -L "$destination_dir" ]; then
	if [ -n "$target_owner" ]; then
		install -d -o "$target_owner" -g "$target_group" -m 755 \
			"$destination_dir"
	else
		mkdir -p "$destination_dir"
	fi
else
	mkdir -p "$destination_dir"
fi

for entry in \
	light-locker.desktop \
	picom.desktop \
	polkit-mate-authentication-agent-1.desktop; do
	destination=$destination_dir/$entry
	if [ -e "$destination" ] || [ -L "$destination" ]; then
		printf '  Preserving existing %s\n' "$destination"
		continue
	fi

	if ! source_entry=$(find_vendor_entry "$entry"); then
		continue
	fi
	if ! add_dwm_exclusion "$source_entry" "$tmp"; then
		printf 'Warning: could not scope invalid autostart entry: %s\n' \
			"$source_entry" >&2
		continue
	fi

	if [ -n "$target_owner" ]; then
		install -o "$target_owner" -g "$target_group" -m 644 \
			"$tmp" "$destination"
	else
		install -m 644 "$tmp" "$destination"
	fi
	printf '  Seeded dwm-scoped autostart override: %s\n' "$entry"
done
