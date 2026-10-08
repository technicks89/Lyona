#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/configure-build.sh [--non-interactive] [--output FILE] [--template FILE]

Create a local config.h from config.def.h. Existing output files are preserved.
Unattended values can be provided with these environment variables:

  DWM_REFRESH_RATE, DWM_FONT_SIZE, DWM_MODKEY, DWM_MFACT, DWM_NMASTER,
  DWM_CURSORWARP, DWM_SWALLOWFLOATING, DWM_RESIZEHINTS
EOF
}

die() {
	printf 'configure-build: %s\n' "$*" >&2
	exit 1
}

# prompt_value VARIABLE PROMPT DEFAULT CHECK [CHECK-ARGS...]: an answer is
# checked as soon as it is typed and asked again with the reason, so one typo
# no longer stops the install after every question (#289).
prompt_value() {
	local variable_name=$1
	local prompt=$2
	local default=$3
	local check=$4
	local value reason
	shift 4

	if [[ $interactive == false ]]; then
		printf -v "$variable_name" '%s' "$default"
		return
	fi

	while true; do
		# End of input is not an answer: stop rather than ask forever.
		read -r -p "$prompt [$default]: " value || die "no answer for: $prompt (end of input)"
		value=${value:-$default}
		reason=$("$check" "$value" "$@")
		if [[ -z $reason ]]; then
			printf -v "$variable_name" '%s' "$value"
			return
		fi
		printf '%s\n' "$reason" >&2
	done
}

prompt_boolean() {
	local variable_name=$1
	local prompt=$2
	local default=$3
	local default_label answer

	if [[ $default == 1 ]]; then
		default_label="Y/n"
	else
		default_label="y/N"
	fi

	if [[ $interactive == false ]]; then
		printf -v "$variable_name" '%s' "$default"
		return
	fi

	while true; do
		read -r -p "$prompt [$default_label]: " answer || die "no answer for: $prompt (end of input)"
		case "${answer:-$default}" in
		1 | y | Y | yes | YES | Yes)
			printf -v "$variable_name" '%s' 1
			return
			;;
		0 | n | N | no | NO | No)
			printf -v "$variable_name" '%s' 0
			return
			;;
		*)
			printf 'Please answer yes or no.\n' >&2
			;;
		esac
	done
}

# check_* VALUE NAME [MIN MAX]: why VALUE is refused, or nothing when valid.
# A whole number without leading zeros (it goes into C, where 0144 is octal),
# no longer than the maximum, so bash arithmetic never sees one that overflows.
check_integer() {
	local value=$1 name=$2 minimum=$3 maximum=$4
	if [[ ! $value =~ ^(0|[1-9][0-9]*)$ ]]; then
		printf '%s must be a whole number, such as %s.\n' "$name" "$minimum"
	elif ((${#value} > ${#maximum})) || ((value < minimum || value > maximum)); then
		printf '%s must be between %s and %s.\n' "$name" "$minimum" "$maximum"
	fi
}

check_decimal() {
	local value=$1 name=$2 minimum=$3 maximum=$4
	if [[ ! $value =~ ^(0|1)(\.[0-9]+)?$ ]] ||
		! awk -v value="$value" -v minimum="$minimum" -v maximum="$maximum" \
			'BEGIN { exit !(value >= minimum && value <= maximum) }'; then
		printf '%s must be a decimal between %s and %s.\n' "$name" "$minimum" "$maximum"
	fi
}

check_modkey() {
	case "${1,,}" in
	super | mod4 | mod4mask | alt | mod1 | mod1mask) ;;
	*) printf 'The modifier key must be super or alt.\n' ;;
	esac
}

# validate CHECK VALUE ARGS...: an unattended value (DWM_*) that is refused
# stops here, before any file is written.
validate() {
	local reason
	reason=$("$@")
	[[ -z $reason ]] || die "$reason"
}

detect_refresh_rate() {
	local rate

	if command -v xrandr >/dev/null 2>&1 && [[ -n ${DISPLAY:-} ]]; then
		rate=$(
			xrandr --current 2>/dev/null |
				awk '$0 ~ /\*/ { gsub(/[^0-9.]/, "", $2); print int($2 + 0.5); exit }'
		)
		if [[ $rate =~ ^[0-9]+$ ]] && ((rate >= 30 && rate <= 1000)); then
			printf '%s\n' "$rate"
			return
		fi
	fi
	printf '%s\n' 60
}

interactive=true
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
template="$repo_dir/config.def.h"
output="$repo_dir/config.h"

while (($# > 0)); do
	case "$1" in
	--non-interactive)
		interactive=false
		shift
		;;
	--output)
		(($# >= 2)) || die "--output requires a path."
		output=$2
		shift 2
		;;
	--template)
		(($# >= 2)) || die "--template requires a path."
		template=$2
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "unknown option: $1"
		;;
	esac
done

[[ -r $template ]] || die "template is not readable: $template"

if [[ -e $output ]]; then
	printf 'Preserving existing %s\n' "$output"
	exit 0
fi

if [[ $interactive == true && ! -t 0 ]]; then
	interactive=false
fi

refresh_rate=${DWM_REFRESH_RATE:-$(detect_refresh_rate)}
font_size=${DWM_FONT_SIZE:-12}
modkey=${DWM_MODKEY:-super}
mfact=${DWM_MFACT:-0.55}
nmaster=${DWM_NMASTER:-1}
cursorwarp=${DWM_CURSORWARP:-1}
swallowfloating=${DWM_SWALLOWFLOATING:-0}
resizehints=${DWM_RESIZEHINTS:-1}

printf '\nConfigure the local dwm build. Press Enter to accept each default.\n\n'
prompt_value refresh_rate "Monitor refresh rate in Hz" "$refresh_rate" check_integer "The refresh rate" 30 1000
prompt_value font_size "Interface font size" "$font_size" check_integer "The font size" 6 48
prompt_value modkey "Primary modifier key (super or alt)" "$modkey" check_modkey
prompt_value mfact "Default master-area ratio" "$mfact" check_decimal "The master-area ratio" 0.05 0.95
prompt_value nmaster "Default number of master windows" "$nmaster" check_integer "The master window count" 1 10
prompt_boolean cursorwarp "Warp the pointer to the focused window" "$cursorwarp"
prompt_boolean swallowfloating "Swallow floating windows launched from terminals" "$swallowfloating"
prompt_boolean resizehints "Respect application size hints while tiling" "$resizehints"

validate check_integer "$refresh_rate" "The refresh rate" 30 1000
validate check_integer "$font_size" "The font size" 6 48
validate check_integer "$nmaster" "The master window count" 1 10
validate check_decimal "$mfact" "The master-area ratio" 0.05 0.95
validate check_modkey "$modkey"

case "${modkey,,}" in
super | mod4 | mod4mask)
	modkey=Mod4Mask
	;;
alt | mod1 | mod1mask)
	modkey=Mod1Mask
	;;
*)
	die "modifier key must be super or alt."
	;;
esac

for setting in cursorwarp swallowfloating resizehints; do
	value=${!setting}
	[[ $value == 0 || $value == 1 ]] || die "$setting must be 0 or 1."
done

mkdir -p "$(dirname "$output")"
temporary=$(mktemp "${output}.tmp.XXXXXX")
trap 'rm -f "$temporary"' EXIT
cp "$template" "$temporary"

sed -i -E \
	-e "s/^(static const unsigned int refresh_rate[[:space:]]*=[[:space:]]*)[0-9]+;/\\1${refresh_rate};/" \
	-e "s/^(static const int cursorwarp[[:space:]]*=[[:space:]]*)[01];/\\1${cursorwarp};/" \
	-e "s/^(static const int swallowfloating[[:space:]]*=[[:space:]]*)[01];/\\1${swallowfloating};/" \
	-e "s/^(static const float mfact[[:space:]]*=[[:space:]]*)[0-9.]+;/\\1${mfact};/" \
	-e "s/^(static const int nmaster[[:space:]]*=[[:space:]]*)[0-9]+;/\\1${nmaster};/" \
	-e "s/^(static const int resizehints[[:space:]]*=[[:space:]]*)[01];/\\1${resizehints};/" \
	-e "s/^(#define MODKEY[[:space:]]+).*/\\1${modkey}/" \
	-e "s/(size=)[0-9]+/\\1${font_size}/g" \
	"$temporary"

mv "$temporary" "$output"
trap - EXIT
printf 'Created %s\n' "$output"
