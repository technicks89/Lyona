#!/bin/bash

set -euo pipefail

THEME_DISCOVERY_HOME=${DWM_APPEARANCE_DISCOVERY_HOME:-$HOME}
[[ $THEME_DISCOVERY_HOME == /* ]] || {
	echo "theme-apply: theme discovery home must be an absolute path" >&2
	exit 1
}
RUNTIME_ONLY_EXPLICIT=false
[[ -z ${DWM_APPEARANCE_RUNTIME_ONLY+x} ]] || RUNTIME_ONLY_EXPLICIT=true
RUNTIME_ONLY=${DWM_APPEARANCE_RUNTIME_ONLY:-0}
[[ $RUNTIME_ONLY == 0 || $RUNTIME_ONLY == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_RUNTIME_ONLY must be 0 or 1" >&2
	exit 1
}
AUTOMATIC_APPLY=${DWM_THEME_APPLY_AUTOMATIC:-}
if [[ -z $AUTOMATIC_APPLY ]]; then
	AUTOMATIC_APPLY=0
	if [[ -r /proc/$PPID/comm ]]; then
		IFS= read -r AUTOMATIC_PARENT </proc/"$PPID"/comm || AUTOMATIC_PARENT=
		[[ $AUTOMATIC_PARENT != dwm ]] || AUTOMATIC_APPLY=1
	fi
fi
[[ $AUTOMATIC_APPLY == 0 || $AUTOMATIC_APPLY == 1 ]] || {
	echo "theme-apply: DWM_THEME_APPLY_AUTOMATIC must be 0 or 1" >&2
	exit 1
}
TRANSACTIONAL_APPLY=${DWM_APPEARANCE_TRANSACTIONAL:-0}
[[ $TRANSACTIONAL_APPLY == 0 || $TRANSACTIONAL_APPLY == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_TRANSACTIONAL must be 0 or 1" >&2
	exit 1
}
LIVE_ONLY=${DWM_APPEARANCE_LIVE_ONLY:-0}
[[ $LIVE_ONLY == 0 || $LIVE_ONLY == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_LIVE_ONLY must be 0 or 1" >&2
	exit 1
}
STAGED_OUTPUT=${DWM_APPEARANCE_STAGED_OUTPUT:-0}
[[ $STAGED_OUTPUT == 0 || $STAGED_OUTPUT == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_STAGED_OUTPUT must be 0 or 1" >&2
	exit 1
}
[[ ! ($RUNTIME_ONLY == 1 && $LIVE_ONLY == 1) ]] || {
	echo "theme-apply: runtime-only and live-only modes are mutually exclusive" >&2
	exit 1
}

THEME_RUNTIME_BASE="${XDG_RUNTIME_DIR:-}"
if [[ -z "$THEME_RUNTIME_BASE" ]]; then
	THEME_RUNTIME_BASE=/tmp/lyona-$UID
elif [[ "$THEME_RUNTIME_BASE" != /* ]]; then
	echo "theme-apply: XDG_RUNTIME_DIR must be an absolute path" >&2
	exit 1
fi
if [[ ! -e "$THEME_RUNTIME_BASE" ]]; then
	(umask 077 && mkdir -p -- "$THEME_RUNTIME_BASE")
fi
if [[ ! -d "$THEME_RUNTIME_BASE" || -L "$THEME_RUNTIME_BASE" ||
	$(stat -c %u -- "$THEME_RUNTIME_BASE") != "$UID" ]]; then
	echo "theme-apply: unsafe runtime directory: $THEME_RUNTIME_BASE" >&2
	exit 1
fi
chmod 700 -- "$THEME_RUNTIME_BASE"
THEME_APPLY_LOCK="$THEME_RUNTIME_BASE/dwm-theme-apply.lock"
if [[ -e "$THEME_APPLY_LOCK" &&
	(! -f "$THEME_APPLY_LOCK" || -L "$THEME_APPLY_LOCK" ||
	$(stat -c %u -- "$THEME_APPLY_LOCK") != "$UID") ]]; then
	echo "theme-apply: unsafe integration lock: $THEME_APPLY_LOCK" >&2
	exit 1
fi
command -v flock >/dev/null 2>&1 || {
	echo "theme-apply: flock is unavailable" >&2
	exit 1
}
if [[ ${DWM_APPEARANCE_INTEGRATION_LOCK_HELD:-0} == 1 && -e /proc/$$/fd/8 &&
	$(readlink -f -- /proc/$$/fd/8) == "$(readlink -f -- "$THEME_APPLY_LOCK")" ]]; then
	flock 8
elif [[ ${DWM_APPEARANCE_INTEGRATION_LOCK_HELD:-0} == 1 ]]; then
	echo "theme-apply: caller-reported integration lock does not match descriptor 8" >&2
	exit 1
else
	: >>"$THEME_APPLY_LOCK"
	chmod 600 -- "$THEME_APPLY_LOCK"
	exec 8>"$THEME_APPLY_LOCK"
	flock 8
fi

THEMES_FILE="${DWM_APPEARANCE_THEMES_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/lyona/themes.toml}"
MANAGED_THEMES_FILE="${DWM_APPEARANCE_MANAGED_THEMES_FILE:-${XDG_DATA_HOME:-$HOME/.local/share}/lyona/config/themes.toml}"
if [[ -e "$THEMES_FILE" || -L "$THEMES_FILE" ]]; then
	if [[ ! -f "$THEMES_FILE" || ! -r "$THEMES_FILE" ]]; then
		echo "theme-apply: user theme source is not a regular file: $THEMES_FILE" >&2
		exit 1
	fi
else
	THEMES_FILE=$MANAGED_THEMES_FILE
	if [[ ! -f "$THEMES_FILE" || -L "$THEMES_FILE" || ! -r "$THEMES_FILE" ]]; then
		echo "theme-apply: no user or managed themes.toml file is available" >&2
		exit 1
	fi
fi
THEME_SOURCE_HASH=$(sha256sum -- "$THEMES_FILE" | awk '{print $1}')

if [[ $RUNTIME_ONLY_EXPLICIT == false ]]; then
	THEME_STATE_HOME=${XDG_STATE_HOME:-}
	[[ $THEME_STATE_HOME == /* ]] || THEME_STATE_HOME=$HOME/.local/state
	if [[ $AUTOMATIC_APPLY == 1 ]]; then
		THEME_SUPPRESS_FILE=$THEME_STATE_HOME/lyona/appearance/integration-suppress
		if [[ -f $THEME_SUPPRESS_FILE && ! -L $THEME_SUPPRESS_FILE &&
			$(stat -c %u -- "$THEME_SUPPRESS_FILE") == "$UID" ]]; then
			read -r THEME_SUPPRESS_HASH _ <"$THEME_SUPPRESS_FILE" || {
				THEME_SUPPRESS_HASH=
			}
			if [[ $THEME_SUPPRESS_HASH == "$THEME_SOURCE_HASH" ]]; then
				RUNTIME_ONLY=1
			elif [[ ! $THEME_SUPPRESS_HASH =~ ^[0-9a-f]{64}$ ||
				$THEME_SUPPRESS_HASH != "$THEME_SOURCE_HASH" ]]; then
				rm -f -- "$THEME_SUPPRESS_FILE"
			fi
		fi
	fi
	THEME_TRANSACTION_FILE=$THEME_STATE_HOME/lyona/appearance/integration-transaction
	if [[ -f $THEME_TRANSACTION_FILE && ! -L $THEME_TRANSACTION_FILE &&
		$(stat -c %u -- "$THEME_TRANSACTION_FILE") == "$UID" ]]; then
		read -r THEME_TRANSACTION_HASH THEME_TRANSACTION_STATE <"$THEME_TRANSACTION_FILE" || {
			THEME_TRANSACTION_HASH=
			THEME_TRANSACTION_STATE=
		}
		if [[ $THEME_TRANSACTION_HASH == "$THEME_SOURCE_HASH" ]]; then
			if [[ $THEME_TRANSACTION_STATE == ready ||
				$THEME_TRANSACTION_STATE == pending ]]; then
				RUNTIME_ONLY=1
			fi
		fi
	fi
fi

toml_get() {
	local section="$1" key="$2" file="$3"
	awk -v sec="[$section]" -v key="$key" '
	        /^[[:space:]]*\[/ {
	            header = $0
	            sub(/^[[:space:]]*/, "", header)
	            sub(/[[:space:]]*#.*/, "", header)
	            sub(/[[:space:]]+$/, "", header)
	            in_sec = (header == sec)
	        }
        in_sec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/"/, "")
            gsub(/[[:space:]]+#.*$/, "")
            sub(/[[:space:]]+$/, "")
            print; exit
        }
    ' "$file"
}

THEME_NAME="$(toml_get "active" "theme" "$THEMES_FILE")"
if [[ -z "$THEME_NAME" ]]; then
	echo "theme-apply: no [active] theme set in $THEMES_FILE" >&2
	exit 1
fi

SECTION="theme.$THEME_NAME"

theme_get() {
	toml_get "$SECTION" "$1" "$THEMES_FILE"
}

TERM_BG="$(theme_get term_bg)"
TERM_FG="$(theme_get term_fg)"
TERM_CURSOR="$(theme_get term_cursor)"
TERM_C0="$(theme_get term_color0)"
TERM_C1="$(theme_get term_color1)"
TERM_C2="$(theme_get term_color2)"
TERM_C3="$(theme_get term_color3)"
TERM_C4="$(theme_get term_color4)"
TERM_C5="$(theme_get term_color5)"
TERM_C6="$(theme_get term_color6)"
TERM_C7="$(theme_get term_color7)"
TERM_C8="$(theme_get term_color8)"
TERM_C9="$(theme_get term_color9)"
TERM_C10="$(theme_get term_color10)"
TERM_C11="$(theme_get term_color11)"
TERM_C12="$(theme_get term_color12)"
TERM_C13="$(theme_get term_color13)"
TERM_C14="$(theme_get term_color14)"
TERM_C15="$(theme_get term_color15)"

DARK_MODE="$(theme_get dark_mode)"
[[ "$DARK_MODE" != "false" ]] && DARK_MODE="true"
CURSOR_SIZE=32
if [[ "$DARK_MODE" == "true" ]]; then
	CURSOR_THEME="Capitaine-Cursors-White"
else
	CURSOR_THEME="Capitaine-Cursors"
fi

# ── Toolkit overrides ─────────────────────────────────────────────────────
#
# dwm-settings-toolkit records the user's cursor, icon, GTK and Qt choices
# here. They are an *input* to this script alongside themes.toml, which is why
# rolling one back is a re-run rather than a restore of the files below.
#
# The path is pinned by the caller during a staged dry run, so the rehearsal
# and the real apply see the same overrides. Without that pin the dry run
# would compute theme defaults and a later revert would refuse, believing the
# files had changed outside Settings.
PERSONALIZATION_FILE="${DWM_APPEARANCE_PERSONALIZATION_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/lyona/personalization.conf}"
declare -A PERSONALIZATION=()

read_personalization() {
	local record value extra records=0 header=''
	[[ -f $PERSONALIZATION_FILE && ! -L $PERSONALIZATION_FILE ]] || return 0
	[[ $(stat -c %s -- "$PERSONALIZATION_FILE" 2>/dev/null || echo 0) -le 4096 ]] || return 0
	local -A parsed=()
	while IFS=$'\t' read -r record value extra || [[ -n $record$value$extra ]]; do
		((records += 1))
		if ((records == 1)); then
			header=$record
			continue
		fi
		[[ -z $extra ]] || return 0
		case $record in
		cursor | icon | gtk | qt) parsed[$record]=$value ;;
		*) return 0 ;;
		esac
	done <"$PERSONALIZATION_FILE"
	[[ $header == toolkit-protocol ]] || return 0
	local key
	for key in "${!parsed[@]}"; do
		value=${parsed[$key]}
		# Refuse anything that could escape into another path or record.
		[[ -n $value && ${#value} -le 128 && $value != */* && $value != *$'\t'* &&
			$value != .. && $value != . ]] || continue
		case $value in
		follow-theme | follow-system) continue ;;
		esac
		PERSONALIZATION[$key]=$value
	done
}

read_personalization
[[ -z ${PERSONALIZATION[cursor]:-} ]] || CURSOR_THEME="${PERSONALIZATION[cursor]}"
ICON_THEME="${PERSONALIZATION[icon]:-}"

# The icon theme has no palette default, so releasing an override means putting
# back whatever was there before Settings first took it over -- which may well
# be a choice the user made by hand years earlier. dwm-settings-toolkit records
# that value the first time it overrides the icon theme; without it, releasing
# an override deletes a setting Settings never owned.
TOOLKIT_BASELINE_ICON=""
TOOLKIT_BASELINE_ICON_PRESENT=0
read_baseline_icon() {
	local file value
	file="${DWM_APPEARANCE_TOOLKIT_BASELINE_ICON:-${XDG_STATE_HOME:-$HOME/.local/state}/lyona/appearance/toolkit/baseline-icon}"
	[[ -f $file && ! -L $file ]] || return 0
	[[ $(stat -c %s -- "$file" 2>/dev/null || echo 0) -le 256 ]] || return 0
	# Present but empty is meaningful: it records that there was no icon theme
	# before the override, so releasing it removes the key again.
	TOOLKIT_BASELINE_ICON_PRESENT=1
	IFS= read -r value <"$file" 2>/dev/null || return 0
	[[ $value =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$ ]] || return 0
	TOOLKIT_BASELINE_ICON="$value"
}
read_baseline_icon

gtk_theme_available() {
	local name="$1"
	local base
	for base in \
		"${XDG_DATA_HOME:-$HOME/.local/share}/themes" \
		"$THEME_DISCOVERY_HOME/.themes" \
		/usr/local/share/themes \
		/usr/share/themes; do
		[[ -d "$base/$name" ]] || continue
		[[ -d "$base/$name/gtk-3.0" || -d "$base/$name/gtk-4.0" ]] && return 0
	done
	return 1
}

# Every palette has a generated Lyona-<name> theme; the Adwaita answers are a
# safety net for a themes.toml that names a palette we have not generated.
default_gtk_theme() {
	if gtk_theme_available "Lyona-$THEME_NAME"; then
		printf '%s\n' "Lyona-$THEME_NAME"
	elif [[ "$DARK_MODE" == "true" ]]; then
		printf '%s\n' "Adwaita-dark"
	else
		printf '%s\n' "Adwaita"
	fi
}

ALACRITTY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty"
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 && -d "$ALACRITTY_DIR" ]]; then
	cat >"$ALACRITTY_DIR/active-theme.toml" <<EOF
# Auto-generated by theme-apply.sh — do not edit manually.
# Change the theme in ~/.config/lyona/themes.toml instead.

[colors.primary]
background = '$TERM_BG'
foreground = '$TERM_FG'

[colors.cursor]
text   = '$TERM_BG'
cursor = '$TERM_CURSOR'

[colors.normal]
black   = '$TERM_C0'
red     = '$TERM_C1'
green   = '$TERM_C2'
yellow  = '$TERM_C3'
blue    = '$TERM_C4'
magenta = '$TERM_C5'
cyan    = '$TERM_C6'
white   = '$TERM_C7'

[colors.bright]
black   = '$TERM_C8'
red     = '$TERM_C9'
green   = '$TERM_C10'
yellow  = '$TERM_C11'
blue    = '$TERM_C12'
magenta = '$TERM_C13'
cyan    = '$TERM_C14'
white   = '$TERM_C15'
EOF

	if [[ -f "$ALACRITTY_DIR/alacritty.toml" ]]; then
		if ! grep -q "active-theme.toml" "$ALACRITTY_DIR/alacritty.toml"; then
			sed -i 's|^\(import = \[\s*\)|\1\n  "~/.config/alacritty/active-theme.toml",|' \
				"$ALACRITTY_DIR/alacritty.toml"
		fi
		sed -i 's|"~/.config/alacritty/[^k][^"]*\.toml"|"~/.config/alacritty/active-theme.toml"|g' \
			"$ALACRITTY_DIR/alacritty.toml"
	fi
fi

KITTY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 && -d "$KITTY_DIR" ]]; then
	cat >"$KITTY_DIR/active-theme.conf" <<EOF
# Auto-generated by theme-apply.sh — do not edit manually.
# Change the theme in ~/.config/lyona/themes.toml instead.

background  $TERM_BG
foreground  $TERM_FG
cursor      $TERM_CURSOR

color0  $TERM_C0
color1  $TERM_C1
color2  $TERM_C2
color3  $TERM_C3
color4  $TERM_C4
color5  $TERM_C5
color6  $TERM_C6
color7  $TERM_C7
color8  $TERM_C8
color9  $TERM_C9
color10 $TERM_C10
color11 $TERM_C11
color12 $TERM_C12
color13 $TERM_C13
color14 $TERM_C14
color15 $TERM_C15
EOF

	if [[ -f "$KITTY_DIR/kitty.conf" ]]; then
		if ! grep -q "include active-theme.conf" "$KITTY_DIR/kitty.conf"; then
			sed -i '1s|^|include active-theme.conf\n|' "$KITTY_DIR/kitty.conf"
		fi
	fi

fi
if [[ $STAGED_OUTPUT == 0 ]] && command -v kitty &>/dev/null; then
	while IFS= read -r kitty_pid; do
		[[ $kitty_pid =~ ^[1-9][0-9]*$ ]] || continue
		kill -SIGUSR1 "$kitty_pid" 2>/dev/null || true
	done < <(pgrep -x kitty 2>/dev/null || true)
fi

if [[ "$DARK_MODE" == "true" ]]; then
	GTK_COLOR_SCHEME="prefer-dark"
	GTK_DARK_PREF=1
else
	GTK_COLOR_SCHEME="default"
	GTK_DARK_PREF=0
fi
GTK_THEME_NAME="$(theme_get gtk_theme)"
[[ -n "$GTK_THEME_NAME" ]] || GTK_THEME_NAME="$(default_gtk_theme)"
# A user override wins over the palette's own choice.
[[ -z ${PERSONALIZATION[gtk]:-} ]] || GTK_THEME_NAME="${PERSONALIZATION[gtk]}"
# A themes.toml carried over from an older install may still name a theme we
# no longer ship, such as the Nordic clone; prefer this palette's generated
# theme over dropping all the way back to stock Adwaita.
if ! gtk_theme_available "$GTK_THEME_NAME" && gtk_theme_available "Lyona-$THEME_NAME"; then
	GTK_THEME_NAME="Lyona-$THEME_NAME"
fi
if ! gtk_theme_available "$GTK_THEME_NAME"; then
	GTK_THEME_FALLBACK="Adwaita"
	[[ "$DARK_MODE" == "true" ]] && GTK_THEME_FALLBACK="Adwaita-dark"
	echo "theme-apply: GTK theme '$GTK_THEME_NAME' not found; falling back to '$GTK_THEME_FALLBACK'" >&2
	GTK_THEME_NAME="$GTK_THEME_FALLBACK"
fi

# Set one key in an ini file, preserving everything else.
#
# The previous version tested for the key with `grep "^key"` but rewrote with
# `sed "s|^key=|"`, so a file written as `key = value` matched the test, missed
# the substitution, and silently kept its old value. It also matched any key
# with this one as a prefix. Doing the whole edit in awk removes both.
gtk_ini_set() {
	local file="$1" key="$2" value="$3" temp mode=644
	mkdir -p "$(dirname "$file")"
	if [[ ! -f "$file" ]]; then
		printf '[Settings]\n%s=%s\n' "$key" "$value" >"$file"
		return
	fi
	mode=$(stat -c %a -- "$file" 2>/dev/null || printf '644')
	temp=$(mktemp "${file}.XXXXXX") || return 1
	awk -v key="$key" -v value="$value" '
		BEGIN { done = 0; in_settings = 0 }
		/^[[:space:]]*\[/ {
			if (in_settings && !done) { print key "=" value; done = 1 }
			in_settings = ($0 ~ /^[[:space:]]*\[Settings\][[:space:]]*$/)
			print
			next
		}
		{
			split($0, parts, "=")
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[1])
			if (in_settings && parts[1] == key) {
				if (!done) { print key "=" value; done = 1 }
				next
			}
			print
		}
		END {
			if (!done) {
				if (!in_settings) print "[Settings]"
				print key "=" value
			}
		}
	' "$file" >"$temp" || {
		rm -f -- "$temp"
		return 1
	}
	chmod "$mode" -- "$temp"
	mv -fT -- "$temp" "$file"
}

# Remove a key, so an override that is withdrawn leaves nothing behind.
gtk_ini_unset() {
	local file="$1" key="$2" temp mode
	[[ -f "$file" ]] || return 0
	mode=$(stat -c %a -- "$file" 2>/dev/null || printf '644')
	temp=$(mktemp "${file}.XXXXXX") || return 1
	awk -v key="$key" '
		{
			split($0, parts, "=")
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[1])
			if (parts[1] == key) next
			print
		}
	' "$file" >"$temp" || {
		rm -f -- "$temp"
		return 1
	}
	chmod "$mode" -- "$temp"
	mv -fT -- "$temp" "$file"
}

# ~/.gtkrc-2.0 was rewritten wholesale on every apply, discarding any other
# setting the user had put there. These edit in place instead.
gtk2_set() {
	local key="$1" value="$2" raw="${3:-}" file="$HOME/.gtkrc-2.0" temp
	local rendered
	if [[ $raw == raw ]]; then
		rendered="$key=$value"
	else
		rendered="$key=\"$value\""
	fi
	if [[ ! -f $file ]]; then
		printf '%s\n' "$rendered" >"$file"
		return
	fi
	temp=$(mktemp "${file}.XXXXXX") || return 1
	awk -v key="$key" -v rendered="$rendered" '
		BEGIN { done = 0 }
		{
			split($0, parts, "=")
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[1])
			if (parts[1] == key) {
				if (!done) { print rendered; done = 1 }
				next
			}
			print
		}
		END { if (!done) print rendered }
	' "$file" >"$temp" || {
		rm -f -- "$temp"
		return 1
	}
	mv -fT -- "$temp" "$file"
}

gtk2_unset() {
	local key="$1" file="$HOME/.gtkrc-2.0" temp
	[[ -f $file ]] || return 0
	temp=$(mktemp "${file}.XXXXXX") || return 1
	awk -v key="$key" '
		{
			split($0, parts, "=")
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[1])
			if (parts[1] == key) next
			print
		}
	' "$file" >"$temp" || {
		rm -f -- "$temp"
		return 1
	}
	mv -fT -- "$temp" "$file"
}

if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 ]]; then
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
		"gtk-application-prefer-dark-theme" "$GTK_DARK_PREF"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
		"gtk-theme-name" "$GTK_THEME_NAME"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
		"gtk-cursor-theme-name" "$CURSOR_THEME"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
		"gtk-cursor-theme-size" "$CURSOR_SIZE"

	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
		"gtk-application-prefer-dark-theme" "$GTK_DARK_PREF"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
		"gtk-theme-name" "$GTK_THEME_NAME"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
		"gtk-cursor-theme-name" "$CURSOR_THEME"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
		"gtk-cursor-theme-size" "$CURSOR_SIZE"

	# The icon theme has no palette default, so unlike every other key here it
	# is not ours to write unprompted. Three cases:
	#
	#   an override is in force            -> write it
	#   an override is being released      -> put the recorded baseline back,
	#                                         or remove the key if the recording
	#                                         says there was nothing before
	#   no override was ever taken         -> leave it alone entirely
	#
	# The last case is why this is not simply an unset: a gtk-icon-theme-name
	# the user set by hand is not Settings' to delete, and deleting it on every
	# theme change is what the baseline recording exists to prevent.
	ICON_THEME_EFFECTIVE="$ICON_THEME"
	[[ -n $ICON_THEME_EFFECTIVE ]] || ICON_THEME_EFFECTIVE="$TOOLKIT_BASELINE_ICON"
	if [[ -n $ICON_THEME_EFFECTIVE ]]; then
		gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
			"gtk-icon-theme-name" "$ICON_THEME_EFFECTIVE"
		gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
			"gtk-icon-theme-name" "$ICON_THEME_EFFECTIVE"
	elif [[ $TOOLKIT_BASELINE_ICON_PRESENT == 1 ]]; then
		gtk_ini_unset "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
			"gtk-icon-theme-name"
		gtk_ini_unset "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
			"gtk-icon-theme-name"
	fi

	gtk2_set "gtk-theme-name" "$GTK_THEME_NAME"
	gtk2_set "gtk-cursor-theme-name" "$CURSOR_THEME"
	gtk2_set "gtk-cursor-theme-size" "$CURSOR_SIZE" raw
	if [[ -n $ICON_THEME_EFFECTIVE ]]; then
		gtk2_set "gtk-icon-theme-name" "$ICON_THEME_EFFECTIVE"
	elif [[ $TOOLKIT_BASELINE_ICON_PRESENT == 1 ]]; then
		gtk2_unset "gtk-icon-theme-name"
	fi
fi

CURSOR_XRESOURCES="${XDG_CONFIG_HOME:-$HOME/.config}/lyona/cursor.Xresources"
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 ]]; then
	mkdir -p "${CURSOR_XRESOURCES%/*}"
	printf 'Xcursor.theme: %s\nXcursor.size: %s\n' \
		"$CURSOR_THEME" "$CURSOR_SIZE" >"$CURSOR_XRESOURCES"
fi
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]] &&
	command -v xrdb &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
	printf 'Xcursor.theme: %s\nXcursor.size: %s\n' "$CURSOR_THEME" "$CURSOR_SIZE" |
		xrdb -merge
fi

if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]] && command -v gsettings &>/dev/null; then
	gsettings set org.gnome.desktop.interface color-scheme "$GTK_COLOR_SCHEME" 2>/dev/null || true
	gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
	gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" 2>/dev/null || true
	gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" 2>/dev/null || true
fi
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]] && command -v xfconf-query &>/dev/null; then
	xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "$GTK_THEME_NAME" 2>/dev/null || true
	xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s "$CURSOR_THEME" 2>/dev/null || true
	xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s "$CURSOR_SIZE" 2>/dev/null || true
fi

if [[ -n ${PERSONALIZATION[qt]:-} ]]; then
	QT_PLATFORM_THEME="${PERSONALIZATION[qt]}"
elif command -v qt6ct &>/dev/null; then
	QT_PLATFORM_THEME="qt6ct"
elif command -v qt5ct &>/dev/null; then
	QT_PLATFORM_THEME="qt5ct"
else
	QT_PLATFORM_THEME="gtk3"
fi

THEME_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/lyona/theme-env.sh"
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 ]]; then
	cat >"$THEME_ENV_FILE" <<EOF
# Auto-generated by theme-apply.sh — do not edit manually.
export QT_QPA_PLATFORMTHEME=$QT_PLATFORM_THEME
export XCURSOR_THEME=$CURSOR_THEME
export XCURSOR_SIZE=$CURSOR_SIZE
EOF

fi

if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 &&
	("$QT_PLATFORM_THEME" == "qt5ct" || "$QT_PLATFORM_THEME" == "qt6ct") ]]; then
	QT_CT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/${QT_PLATFORM_THEME}/${QT_PLATFORM_THEME}.conf"
	if [[ -f "$QT_CT_CONF" ]]; then
		if [[ "$DARK_MODE" == "true" ]]; then
			QT_CT_SCHEME="/usr/share/${QT_PLATFORM_THEME}/colors/darker.conf"
		else
			QT_CT_SCHEME=""
		fi
		if grep -q '^color_scheme_path' "$QT_CT_CONF"; then
			sed -i "s|^color_scheme_path=.*|color_scheme_path=$QT_CT_SCHEME|" "$QT_CT_CONF"
		else
			sed -i "/^\[Appearance\]/a color_scheme_path=${QT_CT_SCHEME}" "$QT_CT_CONF"
		fi
	fi
fi

if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]] && command -v systemctl &>/dev/null; then
	systemctl --user import-environment \
		QT_QPA_PLATFORMTHEME \
		XCURSOR_THEME \
		XCURSOR_SIZE 2>/dev/null || true
fi
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]] &&
	command -v dbus-update-activation-environment &>/dev/null; then
	dbus-update-activation-environment --systemd \
		QT_QPA_PLATFORMTHEME="$QT_PLATFORM_THEME" \
		XCURSOR_THEME="$CURSOR_THEME" \
		XCURSOR_SIZE="$CURSOR_SIZE" 2>/dev/null || true
fi

# A machine-readable statement of what actually took effect, written only when
# a caller asks for it. dwm-settings-toolkit compares this against what the
# user requested: the GTK fallback above can decline an override silently, and
# an exit status of 0 would otherwise report that decline as success.
if [[ -n ${DWM_APPEARANCE_TOOLKIT_REPORT:-} ]]; then
	printf 'toolkit-selection\t%s\t%s\t%s\t%s\n' \
		"$CURSOR_THEME" "$ICON_THEME" "$GTK_THEME_NAME" "$QT_PLATFORM_THEME" \
		>"$DWM_APPEARANCE_TOOLKIT_REPORT" || true
fi

echo "theme-apply: applied theme '$THEME_NAME'"
