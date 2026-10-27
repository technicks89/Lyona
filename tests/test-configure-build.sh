#!/bin/sh

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

output="$work/config.h"

DWM_REFRESH_RATE=144 \
	DWM_FONT_SIZE=15 \
	DWM_MODKEY=alt \
	DWM_MFACT=0.60 \
	DWM_NMASTER=2 \
	DWM_CURSORWARP=0 \
	DWM_SWALLOWFLOATING=1 \
	DWM_RESIZEHINTS=0 \
	"$repo/scripts/configure-build.sh" \
	--non-interactive \
	--template "$repo/config.def.h" \
	--output "$output" >/dev/null

grep -Eq 'refresh_rate[[:space:]]*=[[:space:]]*144;' "$output"
grep -Eq 'cursorwarp[[:space:]]*=[[:space:]]*0;' "$output"
grep -Eq 'swallowfloating[[:space:]]*=[[:space:]]*1;' "$output"
grep -Eq 'mfact[[:space:]]*=[[:space:]]*0.60;' "$output"
grep -Eq 'nmaster[[:space:]]*=[[:space:]]*2;' "$output"
grep -Eq 'resizehints[[:space:]]*=[[:space:]]*0;' "$output"
grep -Eq '^#define MODKEY[[:space:]]+Mod1Mask$' "$output"
grep -Fq 'MesloLGS Nerd Font Mono:size=15' "$output"
# #464: the interface font size leaves the emoji font's pixelsize alone.
grep -Fq 'NotoColorEmoji:pixelsize=14' "$output" || {
	printf '%s\n' "The font size also changed the emoji font's pixelsize." >&2
	exit 1
}

# #464: every default gives config.def.h itself, so a fresh config.h does not
# count as customised. The refresh rate is the template's, not this host's.
defaults="$work/defaults.h"
template_rate=$(sed -n -E 's/^static const unsigned int refresh_rate[[:space:]]*=[[:space:]]*([0-9]+);/\1/p' \
	"$repo/config.def.h")
DWM_REFRESH_RATE=$template_rate \
	"$repo/scripts/configure-build.sh" \
	--non-interactive \
	--template "$repo/config.def.h" \
	--output "$defaults" >/dev/null
cmp -s "$repo/config.def.h" "$defaults" || {
	diff "$repo/config.def.h" "$defaults" >&2 || true
	printf '%s\n' "The defaults did not give config.def.h." >&2
	exit 1
}

# #464: --derive gives back the answers a config.h was made from: the refresh
# rate, and every other one that is not the template's.
derive() {
	"$repo/scripts/configure-build.sh" --derive "$1" --template "$repo/config.def.h"
}
expected_answers='DWM_REFRESH_RATE=144
DWM_FONT_SIZE=15
DWM_MODKEY=alt
DWM_MFACT=0.60
DWM_NMASTER=2
DWM_CURSORWARP=0
DWM_SWALLOWFLOATING=1
DWM_RESIZEHINTS=0'
test "$(derive "$output")" = "$expected_answers" || {
	derive "$output" >&2 || true
	printf '%s\n' "--derive did not give the answers back." >&2
	exit 1
}
test "$(derive "$defaults")" = "DWM_REFRESH_RATE=$template_rate"
# A config.h made before #464, with the emoji pixelsize the font size too.
sed -E 's/(size=)[0-9]+/\115/g' "$output" >"$work/before-464.h"
test "$(derive "$work/before-464.h")" = "$expected_answers" || {
	printf '%s\n' "--derive refused a config.h made before #464." >&2
	exit 1
}
cp "$output" "$work/edited.h"
printf '/* lyona-test: edited by hand */\n' >>"$work/edited.h"
if derive "$work/edited.h" >/dev/null; then
	printf '%s\n' "--derive accepted a config.h edited by hand." >&2
	exit 1
fi

# #464: install-user keeps a checkout config.h of answers as build.conf, copies
# an edited one, and turns an earlier copy of answers into build.conf.
checkout="$work/checkout"
mkdir -p "$checkout/scripts"
cp "$repo/scripts/configure-build.sh" "$repo/scripts/keep-build-answers.sh" "$checkout/scripts/"
cp "$repo/config.def.h" "$checkout/config.def.h"
keep() {
	rm -rf "${work:?}/home"
	mkdir -p "$work/home"
	[ -z "${2:-}" ] || cp "$2" "$work/home/config.h"
	cp "$1" "$checkout/config.h"
	"$checkout/scripts/keep-build-answers.sh" "$work/home" >"$work/keep.out"
}
answers_in() {
	grep -v '^#' "$1"
}

keep "$output"
test "$(answers_in "$work/home/build.conf")" = "$expected_answers"
test ! -e "$work/home/config.h"
grep -Fq 'Saved your dwm build answers' "$work/keep.out"

keep "$work/edited.h"
cmp -s "$work/edited.h" "$work/home/config.h"
test ! -e "$work/home/build.conf"

keep "$repo/config.def.h"
test -z "$(ls -A "$work/home")"

keep "$repo/config.def.h" "$work/before-464.h"
test "$(answers_in "$work/home/build.conf")" = "$expected_answers"
test ! -e "$work/home/config.h"
backups=$(find "$work/home" -name 'config.h.bak.*')
test -n "$backups"
cmp -s "$work/before-464.h" "$backups"

keep "$output" "$work/edited.h"
cmp -s "$work/edited.h" "$work/home/config.h"
test ! -e "$work/home/build.conf"

before=$(sha256sum "$output" | awk '{print $1}')
DWM_REFRESH_RATE=60 \
	"$repo/scripts/configure-build.sh" \
	--non-interactive \
	--template "$repo/config.def.h" \
	--output "$output" >/dev/null
after=$(sha256sum "$output" | awk '{print $1}')
test "$before" = "$after"

invalid="$work/invalid.h"
if DWM_REFRESH_RATE=invalid \
	"$repo/scripts/configure-build.sh" \
	--non-interactive \
	--template "$repo/config.def.h" \
	--output "$invalid" >/dev/null 2>&1; then
	printf '%s\n' "Invalid refresh rate unexpectedly succeeded." >&2
	exit 1
fi
test ! -e "$invalid"

# #289: in a terminal, a wrong answer is asked again with the reason, instead
# of stopping after every question with no config.h.
if command -v script >/dev/null 2>&1; then
	asked="$work/asked.h"
	# script runs the command in $SHELL, which is nologin for a system user
	# such as the CI's nobody.
	printf '144hz\n144\n\n\n\n\n\n\n\n' |
		SHELL=/bin/sh script -qec "$(printf '%s --template %s --output %s' "$repo/scripts/configure-build.sh" \
			"$repo/config.def.h" "$asked")" /dev/null >"$work/asked.out" 2>&1 || {
		cat "$work/asked.out" >&2
		printf '%s\n' "The interactive configuration failed." >&2
		exit 1
	}
	grep -Fq 'The refresh rate must be a whole number' "$work/asked.out" || {
		cat "$work/asked.out" >&2
		printf '%s\n' "A wrong answer was not explained." >&2
		exit 1
	}
	grep -Eq 'refresh_rate[[:space:]]*=[[:space:]]*144;' "$asked" || {
		printf '%s\n' "The corrected answer was not used." >&2
		exit 1
	}
fi

printf '%s\n' "Build configuration generation and preservation: PASS"
