#!/usr/bin/env bash
set -euo pipefail

# What the installers download while sudo is cached is pinned:
# - R16-15: install-mybash installs the Meslo font install.sh pins, at the same
#   release and checksum, never a moving "latest" download; and a download
#   whose checksum does not match is skipped, not installed;
# - R16-16: install.sh fetches the wallpapers at a pinned commit, not a branch.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

mybash=$repo/scripts/install-mybash
for name in MESLO_VERSION MESLO_SHA256; do
	pinned=$(grep -E "^$name=" "$repo/install.sh")
	grep -Fxq "$pinned" "$mybash" || fail "install-mybash does not pin $pinned like install.sh"
done
# shellcheck disable=SC2016 # the literal text in both scripts
url='MESLO_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${MESLO_VERSION}/Meslo.zip"'
for script in "$repo/install.sh" "$mybash"; do
	grep -Fxq "$url" "$script" || fail "${script##*/} does not download the pinned release"
done
if grep -n 'releases/latest' "$mybash" | grep -q .; then
	fail "install-mybash still downloads a moving release: $(grep -n 'releases/latest' "$mybash")"
fi

# A download that does not match: skipped, nothing installed.
cat >"$work/bin/curl" <<'STUB'
#!/bin/sh
while [ $# -gt 0 ]; do
	[ "$1" = --output ] && { printf 'not the font\n' >"$2"; exit 0; }
	shift
done
STUB
printf '#!/bin/sh\nexit 1\n' >"$work/bin/fc-list"
# shellcheck disable=SC2016 # expanded by the stub
printf '#!/bin/sh\n: >"$HOME/fc-cache.ran"\n' >"$work/bin/fc-cache"
chmod +x "$work/bin/curl" "$work/bin/fc-list" "$work/bin/fc-cache"
mkdir -p "$work/home"
fn=$(awk '/^MESLO_VERSION=/ { f = 1 } f { print } f && /^}$/ { exit }' "$mybash")
out=$(env PATH="$work/bin:$PATH" HOME="$work/home" sh -c "$fn
installFont" 2>&1) || fail "a mismatched font download failed the install: $out"
[[ $out == *'does not match its pinned checksum; skipping it.'* ]] || fail "a mismatched font download: $out"
[[ ! -e $work/home/.local/share/fonts && ! -e $work/home/fc-cache.ran ]] ||
	fail 'a mismatched font download was installed'

# The wallpapers: a full commit, and fetched by it rather than cloned.
grep -Eq '^WALLPAPERS_REF="[0-9a-f]{40}"$' "$repo/install.sh" || fail 'the wallpapers are not pinned to a commit'
# shellcheck disable=SC2016 # the literal text in install.sh
grep -Fq 'fetch --quiet --depth 1 "$WALLPAPERS_URL" "$WALLPAPERS_REF"' "$repo/install.sh" ||
	fail 'install.sh does not fetch the pinned wallpaper commit'
if grep -n 'git clone.*nord-background' "$repo/install.sh" | grep -q .; then
	fail 'install.sh still clones the wallpapers unpinned'
fi

printf 'Installer download pins: PASS\n'
