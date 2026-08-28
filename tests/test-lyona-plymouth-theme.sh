#!/bin/sh
# Covers scripts/lyona-plymouth-theme, which generates the boot splash.
#
# The splash cannot be proven correct here -- that needs a real boot, and the
# ISO test only checks that the files reach the profile. What is checkable is
# the part that is easy to get wrong silently: the palette to Plymouth colour
# conversion, and the pairing of wordmark to background.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace

generator=$repo/scripts/lyona-plymouth-theme
themes=$repo/config/themes.toml
assets=$repo/assets/logo
assert_executable "$generator"
assert_file "$themes"

toml_value() {
	awk -v s="[theme.$1]" -v k="$2" '
		$0 == s { in_s = 1; next }
		/^\[/ { in_s = 0 }
		in_s && $1 == k { gsub(/"/, "", $3); print $3; exit }
	' "$themes"
}

# ── Every palette generates, and generates the same bytes twice ──────────

grep '^\[theme\.' "$themes" | sed 's/^\[theme\.//; s/\].*$//' >"$work/palettes"
while IFS= read -r id; do
	out=$work/themes/$id
	"$generator" generate "$id" "$themes" "$assets" "$out" ||
		fail "generating the $id splash failed"

	assert_file "$out/lyona.plymouth"
	assert_file "$out/lyona.script"
	assert_file "$out/logo.png"

	# Plymouth reads the theme by name, so these paths are what makes the
	# generated theme findable at boot at all.
	assert_contains "$out/lyona.plymouth" 'ModuleName=script'
	assert_contains "$out/lyona.plymouth" 'ImageDir=/usr/share/plymouth/themes/lyona'
	assert_contains "$out/lyona.plymouth" 'ScriptFile=/usr/share/plymouth/themes/lyona/lyona.script'

	# The console colour is the palette's background in plymouth's 0xRRGGBB
	# form, not the #RRGGBB the palette is written in.
	term_bg=$(toml_value "$id" term_bg)
	expected_console=$(printf '0x%s' "$(printf '%s' "${term_bg#\#}" | tr '[:upper:]' '[:lower:]')")
	assert_contains "$out/lyona.plymouth" "ConsoleLogBackgroundColor=$expected_console"

	# Plymouth's script module takes 0..1 floats rather than hex, so a
	# background left in hex would be silently wrong rather than an error.
	grep -Eq '^Window\.SetBackgroundTopColor\(0\.[0-9]{3}, 0\.[0-9]{3}, 0\.[0-9]{3}\);$' \
		"$out/lyona.script" ||
		fail "$id has no well-formed background colour in its splash script"
	if grep -Eq '#[0-9A-Fa-f]{6}' "$out/lyona.script"; then
		fail "$id leaked a hex colour into the splash script"
	fi

	# The dark wordmark is the one with white text, so it belongs on a dark
	# background. Getting this backwards renders the logo invisible.
	dark=$(toml_value "$id" dark_mode)
	[ -n "$dark" ] || dark=true
	if [ "$dark" = true ]; then
		expected_logo=$assets/lyona-logo-horizontal-dark.png
	else
		expected_logo=$assets/lyona-logo-horizontal-light.png
	fi
	cmp -s "$out/logo.png" "$expected_logo" ||
		fail "the $id splash uses the wrong wordmark for its background"
done <"$work/palettes"

# The background is term_bg rather than normbgcolor, for the same reason the
# GTK themes use it: normbgcolor is the dwm bar's grey on light palettes.
latte_bg=$(toml_value catppuccin-latte term_bg)
assert_contains "$work/themes/catppuccin-latte/lyona.plymouth" \
	"ConsoleLogBackgroundColor=0x$(printf '%s' "${latte_bg#\#}" | tr '[:upper:]' '[:lower:]')"

# Same palette, same bytes, so a rebuild does not churn the ISO.
"$generator" generate tokyonight "$themes" "$assets" "$work/again" ||
	fail 'the second generation failed'
for name in lyona.plymouth lyona.script; do
	cmp -s "$work/themes/tokyonight/$name" "$work/again/$name" ||
		fail "generation is not deterministic: $name"
done

# ── Refusals ─────────────────────────────────────────────────────────────

for bad in '../escape' 'with space' 'a/b' ''; do
	if "$generator" generate "$bad" "$themes" "$assets" "$work/rejected" >/dev/null 2>&1; then
		fail "the generator accepted an unsafe theme id: '$bad'"
	fi
done
assert_no_file "$work/rejected" 'a rejected id wrote nothing'

if "$generator" generate nosuchtheme "$themes" "$assets" "$work/missing" >/dev/null 2>&1; then
	fail 'the generator accepted a palette that does not exist'
fi
if "$generator" generate tokyonight "$themes" "$work/no-assets" "$work/missing" >/dev/null 2>&1; then
	fail 'the generator accepted a missing asset directory'
fi

# ── The ISO carries what the splash needs ────────────────────────────────
#
# Three separate things, and the splash is invisible if any one is absent.
assert_line "$repo/archiso/packages.x86_64" 'plymouth'
assert_contains "$repo/archiso/airootfs/etc/plymouth/plymouthd.conf" 'Theme=lyona'
assert_contains "$repo/scripts/build-lyona-arch-iso.sh" 'HOOKS=(base udev plymouth '
assert_contains "$repo/scripts/build-lyona-arch-iso.sh" 'quiet splash loglevel=3'

printf '%s\n' 'Lyona boot splash generation: PASS'
