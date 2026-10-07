#!/usr/bin/env bash
set -euo pipefail

# What the installers download while sudo is cached is pinned:
# - R16-15, #250: neither installer downloads the Meslo font: both install the
#   repository package from the shared map, and a failed install is skipped;
# - R16-16: install.sh fetches the wallpapers at a pinned commit, not a branch.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

# #250: the Meslo font comes from the repositories, through the shared map, in
# both scripts; neither downloads the release zip any more.
mybash=$repo/scripts/install-mybash
for script in "$repo/install.sh" "$mybash"; do
	if grep -n 'Meslo.zip\|MESLO_URL\|nerd-fonts/releases' "$script" | grep -q .; then
		fail "${script##*/} still downloads the Meslo release zip"
	fi
done
# shellcheck source=scripts/dwm-packages.sh
. "$repo/scripts/dwm-packages.sh"
dwm_packages arch fonts | grep -Fxq "$(dwm_packages arch font-meslo)" ||
	fail "the fonts profile does not include the Meslo package"
[[ $(dwm_packages arch font-meslo) == ttf-meslo-nerd ]] || fail 'the Meslo package is not ttf-meslo-nerd'

# install-mybash: a pacman failure skips the font, and installs nothing else.
printf '#!/bin/sh\nexit 1\n' >"$work/bin/fc-list"
cat >"$work/bin/sudo" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$HOME/sudo.log"
exit 1
STUB
chmod +x "$work/bin/fc-list" "$work/bin/sudo"
mkdir -p "$work/home"
fn=$(awk '/^installFont\(\) \{$/ { f = 1 } f { print } f && /^}$/ { exit }' "$mybash")
[[ -n $fn ]] || fail 'installFont not found in install-mybash'
out=$(env PATH="$work/bin:$PATH" HOME="$work/home" lyona_lib="$repo/scripts" sh -c "$fn
installFont" 2>&1) || fail "a failed font install failed the install: $out"
[[ $out == *'Could not install the font; skipping it.'* ]] || fail "a failed font install: $out"
[[ $(cat "$work/home/sudo.log") == 'pacman -S --needed --noconfirm ttf-meslo-nerd' ]] ||
	fail "install-mybash ran: $(cat "$work/home/sudo.log")"

# The wallpapers: a full commit, and fetched by it rather than cloned.
grep -Eq '^WALLPAPERS_REF="[0-9a-f]{40}"$' "$repo/install.sh" || fail 'the wallpapers are not pinned to a commit'
# shellcheck disable=SC2016 # the literal text in install.sh
grep -Fq 'fetch --quiet --depth 1 "$WALLPAPERS_URL" "$WALLPAPERS_REF"' "$repo/install.sh" ||
	fail 'install.sh does not fetch the pinned wallpaper commit'
if grep -n 'git clone.*nord-background' "$repo/install.sh" | grep -q .; then
	fail 'install.sh still clones the wallpapers unpinned'
fi

printf 'Installer download pins: PASS\n'
