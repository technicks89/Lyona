#!/bin/sh
# Covers scripts/lyona-gtk-theme, which generates one GTK theme per palette.
#
# The two mapping traps guarded here were both found by checking the generator
# against all 15 real palettes rather than against one: a light theme whose
# background comes from the wrong key renders grey windows, and three dark
# themes whose border key equals their background render no borders at all.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace

generator=$repo/scripts/lyona-gtk-theme
themes=$repo/config/themes.toml
assert_executable "$generator"
assert_file "$themes"

out=$work/themes
"$generator" generate-all "$themes" "$out" || fail 'generate-all failed'

# One directory per [theme.*] section, no more and no fewer.
expected=$(grep -c '^\[theme\.' "$themes")
actual=$(find "$out" -mindepth 1 -maxdepth 1 -type d | wc -l)
assert_equals "$expected" "$actual" 'one generated theme per palette'
[ "$expected" -ge 10 ] || fail "expected at least 10 palettes, found $expected"

token_of() {
	sed -n "s/^@define-color $2  *//p" "$1" | tr -d ';'
}

for dir in "$out"/Lyona-*; do
	name=${dir##*/}
	id=${name#Lyona-}

	assert_file "$dir/index.theme"
	assert_file "$dir/gtk-3.0/gtk.css"
	assert_file "$dir/gtk-4.0/gtk.css"
	assert_contains "$dir/index.theme" "GtkTheme=$name"

	for css in "$dir/gtk-3.0/gtk.css" "$dir/gtk-4.0/gtk.css"; do
		for token in bg surface overlay border fg fg_dim muted accent error; do
			value=$(token_of "$css" "lyona_$token")
			[ -n "$value" ] ||
				fail "$css does not define lyona_$token"
			case $value in
			'#'[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;;
			*) fail "$css has a malformed lyona_$token: $value" ;;
			esac
		done

		# A border the same colour as the background is invisible. This is
		# the solarized / gruvbox / everforest regression guard: all three
		# have normbordercolor == term_bg in themes.toml.
		bg=$(token_of "$css" lyona_bg)
		border=$(token_of "$css" lyona_border)
		[ "$bg" != "$border" ] ||
			fail "$name renders an invisible border: bg and border are both $bg"

		# The import must stay in the exact shape the greeter test greps for.
		grep -Eq '^@import url\("resource:[^"]*"\);$' "$css" ||
			fail "$css has no well-formed base theme import"
	done

	# Dark and light palettes must import different base themes, and GTK 4
	# has no Adwaita resource at all -- its base theme is Default.
	dark=$(awk -v s="[theme.$id]" '
		$0 == s { in_s = 1; next }
		/^\[/ { in_s = 0 }
		in_s && $1 == "dark_mode" { print $3; exit }
	' "$themes")
	[ -n "$dark" ] || dark=true
	if [ "$dark" = true ]; then
		assert_contains "$dir/gtk-3.0/gtk.css" 'Adwaita/gtk-contained-dark.css'
		assert_contains "$dir/gtk-4.0/gtk.css" 'Default/Default-dark.css'
	else
		assert_contains "$dir/gtk-3.0/gtk.css" 'Adwaita/gtk-contained.css'
		assert_contains "$dir/gtk-4.0/gtk.css" 'Default/Default-light.css'
	fi
done

# The background comes from term_bg, not normbgcolor. On light palettes
# normbgcolor is the dwm bar's grey, so this pins the difference.
latte_css=$out/Lyona-catppuccin-latte/gtk-3.0/gtk.css
if [ -f "$latte_css" ]; then
	latte_term_bg=$(awk '
		$0 == "[theme.catppuccin-latte]" { in_s = 1; next }
		/^\[/ { in_s = 0 }
		in_s && $1 == "term_bg" { gsub(/"/, "", $3); print $3; exit }
	' "$themes")
	assert_equals "$latte_term_bg" "$(token_of "$latte_css" lyona_bg)" \
		'a light palette takes its background from term_bg'
fi

# Same palette, same bytes -- so an install does not churn the theme files.
second=$work/themes-again
"$generator" generate-all "$themes" "$second" || fail 'second generate-all failed'
diff -r "$out" "$second" >/dev/null || fail 'generation is not deterministic'

# Unsafe theme ids must be refused rather than written somewhere unexpected.
for bad in '../escape' 'with space' 'a/b' ''; do
	if "$generator" generate "$bad" "$themes" "$work/rejected" >/dev/null 2>&1; then
		fail "generator accepted an unsafe theme id: '$bad'"
	fi
done
assert_no_file "$work/rejected" 'a rejected id wrote nothing'

# A palette that is not in the file is an error, not an empty theme.
if "$generator" generate nosuchtheme "$themes" "$work/missing" >/dev/null 2>&1; then
	fail 'generator accepted a palette that does not exist'
fi

printf '%s\n' 'Lyona GTK theme generation: PASS'
