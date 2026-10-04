#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

stage="$work/lightdm-target"

make -C "$repo/lightdm" --no-print-directory \
	DESTDIR="$stage" \
	LIGHTDM_SEAT_SECTION='Seat:*' \
	LIGHTDM_GREETER_SESSION=lightdm-slick-greeter \
	LIGHTDM_SESSION_WRAPPER=/etc/lightdm/Xsession \
	LIGHTDM_LOGIND_CHECK=true \
	install >/dev/null
cat >"$work/lightdm.expected" <<'CONF'
[LightDM]
logind-check-graphical=true

[Seat:*]
greeter-session=lightdm-slick-greeter
user-session=dwm
session-wrapper=/etc/lightdm/Xsession
CONF
cmp -s "$work/lightdm.expected" "$stage/etc/lightdm/lightdm.conf"

grep -Fqx 'xft-dpi=96' "$stage/etc/lightdm/slick-greeter.conf"
grep -Fqx 'activate-numlock=false' "$stage/etc/lightdm/slick-greeter.conf"

# The greeter takes its whole palette from the GTK theme named here, so the
# theme has to be installed alongside the config that names it.
greeter_theme=$(
	sed -n 's/^theme-name=//p' "$stage/etc/lightdm/slick-greeter.conf"
)
[[ -n $greeter_theme ]] || {
	printf 'slick-greeter.conf names no GTK theme.\n' >&2
	exit 1
}
theme_css="$stage/usr/share/themes/$greeter_theme/gtk-3.0/gtk.css"
for file in \
	"$stage/usr/share/themes/$greeter_theme/index.theme" \
	"$theme_css"; do
	[[ -f $file ]] || {
		printf 'greeter theme %s is not installed: missing %s\n' \
			"$greeter_theme" "$file" >&2
		exit 1
	}
done

# Everything the theme does not restate comes from Adwaita dark, which GTK
# ships as a gresource rather than a file on disk.
adwaita_resource=$(
	sed -n 's/^@import url("\(resource:[^"]*\)");$/\1/p' "$theme_css"
)
[[ -n $adwaita_resource ]] || {
	printf '%s imports no base GTK theme.\n' "$theme_css" >&2
	exit 1
}
adwaita_path=${adwaita_resource#resource://}
gtk_lib=$(
	for candidate in /usr/lib/libgtk-3.so.0 /usr/lib64/libgtk-3.so.0; do
		[[ -f $candidate ]] && printf '%s' "$candidate" && break
	done
)
if [[ -n $gtk_lib ]] && command -v strings >/dev/null 2>&1; then
	grep -Fq "$adwaita_path" <(strings "$gtk_lib") || {
		printf 'GTK 3 no longer ships %s; %s would fall back to an unstyled theme.\n' \
			"$adwaita_path" "$greeter_theme" >&2
		exit 1
	}
else
	printf 'LightDM config rendering: skipping the Adwaita gresource check (no libgtk-3)\n'
fi

# The panel and the login box are painted from the Tokyo Night palette in
# config/themes.toml, not from Adwaita's own greys.
tokyonight() {
	local key=$1 value
	value=$(
		awk -v key="$key" '
			/^\[theme\./ { in_theme = ($0 == "[theme.tokyonight]") }
			in_theme && $1 == key {
				if (match($0, /#[0-9A-Fa-f]{6}/)) {
					print substr($0, RSTART, RLENGTH)
					exit
				}
			}
		' "$repo/config/themes.toml"
	)
	[[ -n $value ]] || {
		printf 'config/themes.toml has no tokyonight %s.\n' "$key" >&2
		exit 1
	}
	printf '%s' "$value"
}

for key in term_bg term_fg; do
	value=$(tokyonight "$key")
	grep -Fqi "$value" "$theme_css" || {
		printf '%s does not use the tokyonight %s (%s).\n' \
			"$theme_css" "$key" "$value" >&2
		exit 1
	}
done

# Shown until the wallpaper loads, and in the letterboxing around it.
grep -Fqix "background-color=$(tokyonight term_bg)" \
	"$stage/etc/lightdm/slick-greeter.conf" || {
	printf 'slick-greeter.conf does not fall back to the tokyonight background.\n' >&2
	exit 1
}

for key in logo other-monitors-logo; do
	logo=$(sed -n "s/^$key=//p" "$stage/etc/lightdm/slick-greeter.conf")
	[[ -n $logo && -f "$stage$logo" ]] || {
		printf 'slick-greeter.conf %s points at an uninstalled file: %s\n' \
			"$key" "${logo:-<unset>}" >&2
		exit 1
	}
done

# The greeter theme needs the built lyona-toml, so install.sh deploys the
# LightDM config only after `make` (Sync Sprint 16: a fresh image install
# failed here). And the Makefile says so, rather than failing deep inside.
build_line=$(grep -nx 'make' "$repo/install.sh" | head -n 1 | cut -d: -f1)
deploy_line=$(grep -nx '	install_lightdm_config' "$repo/install.sh" | head -n 1 | cut -d: -f1)
[[ -n $build_line && -n $deploy_line ]] || {
	printf 'could not find the build or the LightDM deploy in install.sh\n' >&2
	exit 1
}
((deploy_line > build_line)) || {
	printf 'install.sh deploys the LightDM config (line %s) before building lyona-toml (line %s)\n' \
		"$deploy_line" "$build_line" >&2
	exit 1
}
grep -Fq '[ -x ../lyona-toml ] ||' "$repo/lightdm/Makefile" || {
	printf 'lightdm/Makefile does not check for the built lyona-toml\n' >&2
	exit 1
}

printf 'LightDM config rendering: PASS\n'
