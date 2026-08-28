#!/bin/sh
# Covers scripts/install-mybash.
#
# That script installs packages with sudo pacman, clones over the network and
# replaces ~/.bashrc, so it cannot be run here. What is checkable without
# running it is the contract around it: that it is syntactically sound, that
# every helper it calls exists, that install.sh installs the packages it would
# otherwise fetch from the network, and that the linked .bashrc's startup
# dependencies are actually installed by something.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace

installer=$repo/scripts/install-mybash
assert_executable "$installer"
sh -n "$installer" || fail 'install-mybash is not valid shell'

# ── Every function it calls is defined ───────────────────────────────────
#
# command_exists was called four times and never defined, which made every
# check falsy: the "already installed" branches were unreachable and the
# network fallbacks below became reachable on machines that needed nothing.

sed -n 's/^\([a-zA-Z_][a-zA-Z_0-9]*\)() {$/\1/p' "$installer" | sort -u >"$work/defined"
for helper in command_exists _install_pkg installDepend cloneMyBash installFont \
	installStarshipAndFzf installZoxide linkConfig; do
	grep -Fxq "$helper" "$work/defined" ||
		fail "install-mybash calls $helper but never defines it"
done

# The multi-argument call in installDepend only works if every argument is
# tested, not just the first.
awk '/^command_exists\(\) \{/, /^\}/' "$installer" >"$work/command_exists"
grep -Fq 'for command_name in "$@"' "$work/command_exists" ||
	fail 'command_exists does not test every argument it is given'

# ── The network fallbacks must stay unreachable in practice ──────────────
#
# The script pipes an installer from the network when pacman fails. That is
# only acceptable because install.sh installs these from the repositories
# first, so pacman has nothing left to do by the time the script runs.

grep -Eq '^[[:space:]]*dwm_install_package_profile[[:space:]]+shell[[:space:]]*$' \
	"$repo/install.sh" ||
	fail 'install.sh does not install the shell profile'

shell_profile=$(. "$repo/scripts/dwm-packages.sh" && dwm_packages arch shell)
for fallback in starship fzf zoxide; do
	printf '%s\n' "$shell_profile" | grep -Fxq "$fallback" ||
		fail "the shell profile omits $fallback, so install-mybash may fetch it from the network"
done

# fastfetch is not installed by install-mybash at all, so only the profile can
# supply it. The .bashrc guards it behind command -v, so its absence is silent
# rather than an error, which makes it easier to miss, not less important.
printf '%s\n' "$shell_profile" | grep -Fxq fastfetch ||
	fail 'the shell profile omits fastfetch, so the linked .bashrc would skip it'

# Ordering matters: installing the packages after the script would leave the
# fallbacks reachable.
profile_line=$(grep -n 'dwm_install_package_profile shell' "$repo/install.sh" | cut -d: -f1)
script_line=$(grep -n 'scripts/install-mybash' "$repo/install.sh" | cut -d: -f1)
[ "$profile_line" -lt "$script_line" ] ||
	fail 'install.sh runs install-mybash before installing the shell packages'

# ── All four configuration files are linked ─────────────────────────────
#
# .bashrc and starship.toml alone leave fastfetch and the palette switcher on
# stock defaults, which looks like the configuration half-applied.

awk '/^linkConfig\(\) \{/, /^\}/' "$installer" >"$work/link_config"
# shellcheck disable=SC2016 # the literal shell source text is what we look for
for target in '"$HOME/.bashrc"' '"$HOME/.config/starship.toml"' \
	'"$HOME/.config/fastfetch/config.jsonc"' '"$HOME/.local/bin/starship-theme"'; do
	grep -Fq "ln -svf" "$work/link_config" || fail 'linkConfig no longer links anything'
	grep -Fq "$target" "$work/link_config" ||
		fail "linkConfig does not link $target"
done

# Both new targets are in directories that may not exist yet.
# shellcheck disable=SC2016 # the literal shell source text is what we look for
for parent in '"$HOME/.config/fastfetch"' '"$HOME/.local/bin"'; do
	grep -Fq "mkdir -p $parent" "$work/link_config" ||
		fail "linkConfig links into $parent without creating it"
done

# ── The previous shell configuration is kept ─────────────────────────────

# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq 'mv "$OLD_BASHRC" "$HOME/.bashrc.bak"' "$installer" ||
	fail 'install-mybash no longer preserves an existing .bashrc'

# ── It is reached, and only for the recommended profile ──────────────────

assert_contains "$repo/install.sh" 'scripts/install-mybash'
grep -Fq 'install-mybash' "$repo/Makefile" ||
	fail 'install-mybash is not installed onto PATH'

printf '%s\n' 'mybash shell configuration: PASS'
