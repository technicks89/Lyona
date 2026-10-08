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
	printf '144hz\n144\n\n\n\n\n\n\n\n' |
		script -qec "$(printf '%s --template %s --output %s' "$repo/scripts/configure-build.sh" \
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
