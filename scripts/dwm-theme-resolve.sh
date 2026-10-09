# shellcheck shell=bash disable=SC2034 # LYONA_* globals are read by the scripts that source this
# The GTK and cursor theme theme-apply.sh writes, worked out in one place
# (#274). theme-apply.sh applies the answer and dwm-settings-appearance reports
# whether it is applied; when each kept its own copy of the rule they drifted,
# and Appearance showed a Toolkit override as a stale theme forever.
#
# Callers set data_home (lyona_xdg_dirs) and config_home first. The test and
# staging overrides, all optional:
#   DWM_APPEARANCE_PERSONALIZATION_FILE  the Toolkit overrides file
#   DWM_APPEARANCE_DATA_DIRS             data roots in place of the XDG ones
#   DWM_APPEARANCE_DISCOVERY_HOME        the home whose ~/.themes is searched

# Toolkit overrides from personalization.conf: cursor, icon, gtk and qt, each
# a theme name. "follow-theme" and "follow-system" are no override. A file
# that is not exactly the protocol is ignored whole.
declare -gA LYONA_PERSONALIZATION=()
lyona_read_personalization() {
	local file=${DWM_APPEARANCE_PERSONALIZATION_FILE:-$config_home/lyona/personalization.conf}
	local record value extra records=0 header='' key
	local -A overrides=()
	LYONA_PERSONALIZATION=()
	[[ -f $file && ! -L $file ]] || return 0
	[[ $(stat -c %s -- "$file" 2>/dev/null || echo 0) -le 4096 ]] || return 0
	while IFS=$'\t' read -r record value extra || [[ -n $record$value$extra ]]; do
		((records += 1))
		if ((records == 1)); then
			header=$record
			continue
		fi
		[[ -z $extra ]] || return 0
		case $record in
		cursor | icon | gtk | qt) overrides[$record]=$value ;;
		*) return 0 ;;
		esac
	done <"$file"
	[[ $header == toolkit-protocol ]] || return 0
	for key in "${!overrides[@]}"; do
		value=${overrides[$key]}
		# Refuse anything that could escape into another path or record.
		[[ -n $value && ${#value} -le 128 && $value != */* && $value != *$'\t'* &&
			$value != .. && $value != . ]] || continue
		case $value in
		follow-theme | follow-system) continue ;;
		esac
		LYONA_PERSONALIZATION[$key]=$value
	done
}

# Where themes are looked for: each data root's themes/, user first, then the
# discovery home's ~/.themes.
lyona_theme_dirs() {
	local roots root
	local -a split_roots=()
	roots=${DWM_APPEARANCE_DATA_DIRS:-$data_home:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}}
	IFS=: read -r -a split_roots <<<"$roots"
	for root in "${split_roots[@]}"; do
		[[ -z $root ]] || printf '%s\n' "$root/themes"
	done
	printf '%s\n' "${DWM_APPEARANCE_DISCOVERY_HOME:-${HOME:-}}/.themes"
}

# lyona_gtk_theme_has_version NAME VERSION: NAME has gtk-VERSION assets.
# Adwaita is built into GTK 3 and 4; Adwaita-dark is not a theme there, only
# Adwaita with the prefer-dark hint, so it counts only when installed.
lyona_gtk_theme_has_version() {
	local name=$1 version=$2 dir
	[[ $name != Adwaita ]] || return 0
	while IFS= read -r dir; do
		[[ -d $dir/$name/gtk-$version ]] && return 0
	done < <(lyona_theme_dirs)
	return 1
}

lyona_gtk_theme_available() {
	lyona_gtk_theme_has_version "$1" 3.0 || lyona_gtk_theme_has_version "$1" 4.0
}

# lyona_gtk_theme_requested PALETTE TOML_GTK: the palette's own choice, before
# overrides and fallbacks: its gtk_theme, else its generated Lyona-<palette>.
lyona_gtk_theme_requested() {
	local palette=$1 toml_gtk=$2
	if [[ -n $toml_gtk ]]; then
		printf '%s\n' "$toml_gtk"
	else
		printf 'Lyona-%s\n' "$palette"
	fi
}

# lyona_gtk_theme_resolve PALETTE TOML_GTK: sets LYONA_GTK_THEME, the GTK
# theme to apply.
# - A Toolkit override wins as it is, installed or not: it is the user's pick.
# - Else the palette's choice, or its generated Lyona-<palette> when that is
#   missing, or Adwaita (with the dark hint for a dark palette).
# LYONA_GTK_THEME_FELL_BACK is the name that was missing when the answer is
# that last fallback, so theme-apply.sh can say so. Globals, not output: a
# $(...) caller would lose the second one.
LYONA_GTK_THEME=
LYONA_GTK_THEME_FELL_BACK=
lyona_gtk_theme_resolve() {
	local palette=$1 toml_gtk=$2 name
	LYONA_GTK_THEME_FELL_BACK=
	if [[ -n ${LYONA_PERSONALIZATION[gtk]:-} ]]; then
		LYONA_GTK_THEME=${LYONA_PERSONALIZATION[gtk]}
		return 0
	fi
	name=$(lyona_gtk_theme_requested "$palette" "$toml_gtk")
	if ! lyona_gtk_theme_available "$name" && lyona_gtk_theme_available "Lyona-$palette"; then
		name=Lyona-$palette
	fi
	if ! lyona_gtk_theme_available "$name"; then
		LYONA_GTK_THEME_FELL_BACK=$name
		name=Adwaita
	fi
	LYONA_GTK_THEME=$name
}

# lyona_cursor_theme_resolve DARK: the cursor theme to apply, a Toolkit
# override first, else the managed Capitaine theme for the palette.
lyona_cursor_theme_resolve() {
	if [[ -n ${LYONA_PERSONALIZATION[cursor]:-} ]]; then
		printf '%s\n' "${LYONA_PERSONALIZATION[cursor]}"
	elif [[ $1 == true ]]; then
		printf '%s\n' Capitaine-Cursors-White
	else
		printf '%s\n' Capitaine-Cursors
	fi
}
