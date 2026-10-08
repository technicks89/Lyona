#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 16 R16-28: the installer's summary lists every change it makes
# before asking: the yay build, the mybash links, the wallpaper download,
# LightDM, the gamemode group. And [multilib] is Arch's own repository, not a
# third-party one. Run as dry runs, with a scratch home.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
if ! grep -Eqs '^ID=arch$' /etc/os-release; then
	printf 'SKIP: the installer dry run needs Arch Linux\n'
	exit 77
fi

mkdir -p "$work/home"
plan() { # PROFILE [ARGS...]
	local profile=$1
	shift
	env HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" XDG_DATA_HOME="$work/home/.local/share" \
		"$repo/install.sh" --dry-run --non-interactive --profile "$profile" "$@" 2>&1
}
has() { # PLAN TEXT
	[[ $1 == *"$2"* ]] || fail "the summary does not say: $2"$'\n'"$1"
}
lacks() { # PLAN TEXT
	[[ $1 != *"$2"* ]] || fail "the summary says, but should not: $2"
}

core=$(plan core)
has "$core" '  AUR helper: '
# Every profile, whatever this machine's state (#258).
has "$core" '  Time synchronization: '
lacks "$core" 'Shell configuration: mybash'
lacks "$core" 'Wallpapers: '

recommended=$(plan recommended)
has "$recommended" 'Shell configuration: mybash replaces ~/.bashrc'
has "$recommended" '(previous files kept as .bak.<time>)'
lacks "$recommended" 'Wallpapers: '

full=$(plan full --enable-arch-gaming-repos)
has "$full" "  Wallpapers: downloaded into $work/home/Pictures/backgrounds (pinned commit)"
has "$full" '  Display manager: '
lacks "$full" 'Third-party repositories'
if [[ $full == *'Arch gaming packages:'* ]]; then
	has "$full" '  Arch [multilib] repository: '
	has "$full" "  gamemode group: $(id -un) is added to it"
fi
mkdir -p "$work/home/Pictures/backgrounds"
has "$(plan full)" "  Wallpapers: already present in $work/home/Pictures/backgrounds"

# A non-interactive run answers makepkg's pacman prompt: behind the image
# install's spinner nothing else can, and it waited there forever (Sync Sprint
# 16, found in a VM).
yay_fn=$(sed -n '/^ensure_yay_installed() {$/,/^}$/p' "$repo/install.sh")
# shellcheck disable=SC2016 # the literal text in install.sh
grep -Fq '[[ $NON_INTERACTIVE != true ]] || makepkg_args+=(--noconfirm)' <<<"$yay_fn" ||
	fail 'a non-interactive install does not answer makepkg'

printf 'Installer summary completeness: PASS\n'
