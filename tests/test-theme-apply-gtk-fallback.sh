#!/usr/bin/env bash
# theme-apply.sh resolves gtk-theme-name to the palette's own generated
# `Lyona-<theme>` GTK theme. `lyona-gtk-theme generate-all` is normally an
# install-time step (the Makefile's `install-gtk-themes`), so a live system
# that has never run it -- or a `themes.toml` that grew a palette since --
# must not silently end up light: theme-apply.sh generates the one palette
# actually in use on demand instead of only falling back (#348).
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

home=$work/home
runtime=$work/run
bin=$work/bin
mkdir -p "$home/.config/lyona" "$home/.local/share" "$home/.local/state" \
	"$runtime" "$bin"
chmod 700 "$runtime"
cp "$repo/config/themes.toml" "$home/.config/lyona/themes.toml"
sed -i 's/^theme = ".*"/theme = "tokyonight"/' "$home/.config/lyona/themes.toml"

# Everything that could touch the developer's real session is a stub; only
# gtk_theme_available()'s search paths and lyona-gtk-theme itself are real.
for name in gsettings xfconf-query systemctl dbus-update-activation-environment \
	xsetroot dwm-cursor-reload; do
	printf '#!/bin/sh\nexit 0\n' >"$bin/$name"
done
chmod +x "$bin"/*

run_apply() {
	local data_home=${1:-$home/.local/share}
	HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$data_home \
		XDG_STATE_HOME=$home/.local/state XDG_RUNTIME_DIR=$runtime \
		PATH=$bin:/usr/bin:/bin \
		"$repo/scripts/theme-apply.sh" >"$work/apply.out" 2>&1
}

# 1. Nothing has ever generated the GTK themes (the real-world gap this
# fixes): theme-apply.sh generates the one actually needed on demand.
[[ ! -d $home/.local/share/themes/Lyona-tokyonight ]] ||
	fail 'the theme already exists before the run; the test setup is wrong'
run_apply || {
	cat "$work/apply.out" >&2
	fail 'theme-apply.sh failed with no GTK themes generated yet'
}
assert_file "$home/.config/gtk-3.0/settings.ini"
grep -Fq 'gtk-theme-name=Lyona-tokyonight' "$home/.config/gtk-3.0/settings.ini" ||
	fail "did not generate and use Lyona-tokyonight on demand: $(cat "$home/.config/gtk-3.0/settings.ini")"
grep -Fq 'gtk-application-prefer-dark-theme=1' "$home/.config/gtk-3.0/settings.ini" ||
	fail 'a dark preset must set the dark-theme preference'
assert_file "$home/.local/share/themes/Lyona-tokyonight/gtk-3.0/gtk.css"
assert_file "$home/.local/share/themes/Lyona-tokyonight/gtk-4.0/gtk.css"
printf 'a missing GTK theme is generated on demand: PASS\n'

# 2. A second run, now that it exists, does not regenerate it (no needless
# work every time a theme is applied).
generated_at=$(stat -c %Y "$home/.local/share/themes/Lyona-tokyonight/gtk-3.0/gtk.css")
sleep 1.1
run_apply || {
	cat "$work/apply.out" >&2
	fail 'theme-apply.sh failed on a second run with the theme already present'
}
regenerated_at=$(stat -c %Y "$home/.local/share/themes/Lyona-tokyonight/gtk-3.0/gtk.css")
[[ $generated_at == "$regenerated_at" ]] ||
	fail 'an already-generated theme was regenerated on an unrelated apply'
printf 'an existing GTK theme is not regenerated: PASS\n'

# 2b. A user override wins over the palette's own choice, including over the
# generate-on-demand fallback: it must never be silently replaced by
# "Lyona-tokyonight", even once that theme genuinely exists on disk (which it
# now does, from case 1 above -- the point of generating on demand, so this
# is the scenario that would actually catch a regression here).
assert_file "$home/.local/share/themes/Lyona-tokyonight/gtk-3.0/gtk.css"
printf 'toolkit-protocol\t1\t0\ngtk\tAdwaita-dark\n' >"$home/.config/lyona/personalization.conf"
run_apply || {
	cat "$work/apply.out" >&2
	fail 'theme-apply.sh failed with a gtk personalization override set'
}
grep -Fq 'gtk-theme-name=Adwaita-dark' "$home/.config/gtk-3.0/settings.ini" ||
	fail "a user's explicit gtk override was replaced: $(cat "$home/.config/gtk-3.0/settings.ini")"
rm -f "$home/.config/lyona/personalization.conf"
printf 'a personalized GTK theme already on disk is never swapped back out: PASS\n'

# 2c. Same, but from a clean slate: a personalization override must not
# trigger the on-demand *generation* either, only the substitution above.
rm -rf "$home/.local/share/themes"
printf 'toolkit-protocol\t1\t0\ngtk\tAdwaita-dark\n' >"$home/.config/lyona/personalization.conf"
run_apply || {
	cat "$work/apply.out" >&2
	fail 'theme-apply.sh failed with a gtk personalization override set and no themes generated yet'
}
grep -Fq 'gtk-theme-name=Adwaita-dark' "$home/.config/gtk-3.0/settings.ini" ||
	fail "a user's explicit gtk override was replaced: $(cat "$home/.config/gtk-3.0/settings.ini")"
[[ ! -d $home/.local/share/themes/Lyona-tokyonight ]] ||
	fail 'a personalization override still triggered generating the palette theme'
rm -f "$home/.config/lyona/personalization.conf"
printf 'a personalized GTK theme never triggers on-demand generation: PASS\n'

# 3. Generation genuinely failing (an invalid data home, standing in for "the
# generator itself broke") must still fall back to something that is actually
# dark, not a theme name nothing provides. /dev/null is a non-directory, so
# this blocks output creation even when the test runs as root.
rm -rf "$home/.local/share/themes"
run_apply /dev/null || true
if grep -Fq 'gtk-theme-name=Adwaita-dark' "$home/.config/gtk-3.0/settings.ini"; then
	fail 'fell back to the literal name "Adwaita-dark", which recent GTK does not ship as a separate theme'
fi
grep -Fq 'gtk-theme-name=Adwaita' "$home/.config/gtk-3.0/settings.ini" ||
	fail "did not fall back to plain Adwaita when generation failed: $(cat "$home/.config/gtk-3.0/settings.ini")"
grep -Fq 'gtk-application-prefer-dark-theme=1' "$home/.config/gtk-3.0/settings.ini" ||
	fail 'the dark-theme preference must still be set even on the Adwaita fallback'
printf 'a fallback that cannot generate still asks for the dark variant correctly: PASS\n'

# 4. --runtime-only must not have the side effect of writing a new theme
# directory (it is documented to avoid persistent changes).
rm -rf "$home/.local/share/themes"
DWM_APPEARANCE_RUNTIME_ONLY=1 HOME=$home XDG_CONFIG_HOME=$home/.config \
	XDG_DATA_HOME=$home/.local/share XDG_STATE_HOME=$home/.local/state \
	XDG_RUNTIME_DIR=$runtime PATH=$bin:/usr/bin:/bin \
	"$repo/scripts/theme-apply.sh" >"$work/apply.out" 2>&1 || {
	cat "$work/apply.out" >&2
	fail 'theme-apply.sh --runtime-only failed'
}
[[ ! -d $home/.local/share/themes/Lyona-tokyonight ]] ||
	fail 'a runtime-only apply generated a persistent GTK theme directory'
printf 'a runtime-only apply does not generate a GTK theme on disk: PASS\n'

printf 'theme-apply.sh GTK theme fallback: PASS\n'
