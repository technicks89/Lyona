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
# The shell profile comes with every other package, in one transaction (#247).
grep -Eq '^		theme theme-gtk fonts shell theme-optional\)$' "$repo/install.sh" ||
	fail 'install.sh does not install the shell profile with the other packages'
# shellcheck disable=SC2016 # matching install.sh's literal text, not expanding it
profile_line=$(grep -nF 'if ! dwm_install_batch "${batch_flags[@]}" batch_required batch_optional; then' "$repo/install.sh" | cut -d: -f1)
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
	grep -Fq "link_with_backup " "$work/link_config" || fail 'linkConfig no longer links anything'
	grep -Fq "$target" "$work/link_config" ||
		fail "linkConfig does not link $target"
done

# ── The previous shell configuration is kept ─────────────────────────────
#
# Sync Sprint 16 R16-23: every file it replaces is kept with a timestamp, even
# when an older backup is already there, and a link already in place is left
# alone, so re-running install.sh adds no backups. Run against a scratch home.

awk '/^link_with_backup\(\) \{/, /^\}/' "$installer" >"$work/link_with_backup"
[ -s "$work/link_with_backup" ] || fail 'link_with_backup is missing'
home=$work/home
mkdir -p "$home/.config" "$work/mybash"
for file in .bashrc starship.toml; do printf 'mybash %s\n' "$file" >"$work/mybash/$file"; done
printf 'my own bashrc\n' >"$home/.bashrc"
printf 'an older backup\n' >"$home/.bashrc.bak"
ln -s "$work/elsewhere.toml" "$home/.config/starship.toml"
# shellcheck disable=SC1091 # extracted above
link() { (. "$work/link_with_backup" && link_with_backup "$@") >/dev/null; }
link "$work/mybash/.bashrc" "$home/.bashrc"
link "$work/mybash/starship.toml" "$home/.config/starship.toml"
# Into a directory that did not exist yet.
link "$work/mybash/starship.toml" "$home/.local/bin/starship-theme"
[ "$(readlink "$home/.bashrc")" = "$work/mybash/.bashrc" ] || fail '.bashrc was not linked'
[ "$(cat "$home/.bashrc.bak")" = 'an older backup' ] || fail 'an older backup was overwritten'
set -- "$home"/.bashrc.bak.*
[ $# -eq 1 ] && [ "$(cat "$1")" = 'my own bashrc' ] || fail 'the replaced .bashrc was not kept'
set -- "$home"/.config/starship.toml.bak.*
[ $# -eq 1 ] && [ "$(readlink "$1")" = "$work/elsewhere.toml" ] || fail 'the replaced starship.toml link was not kept'
[ -L "$home/.local/bin/starship-theme" ] || fail 'a link into a new directory was not made'
# Again: nothing new is backed up.
link "$work/mybash/.bashrc" "$home/.bashrc"
set -- "$home"/.bashrc.bak.*
[ $# -eq 1 ] || fail "a second run backed .bashrc up again: $*"

# ── Re-running keeps the checkout and the user's edits (#267) ────────────
#
# ~/.bashrc links into the checkout, so an edit to it is an edit there. A
# local repository stands in for mybash: no network.

awk '/^cloneMyBash\(\) \{/, /^\}/' "$installer" >"$work/clone_mybash"
[ -s "$work/clone_mybash" ] || fail 'cloneMyBash is missing'
upstream=$work/upstream
git init --quiet "$upstream"
git -C "$upstream" config user.email test@example.invalid
git -C "$upstream" config user.name test
printf 'first\n' >"$upstream/.bashrc"
git -C "$upstream" add .bashrc
git -C "$upstream" commit --quiet -m first
first=$(git -C "$upstream" rev-parse HEAD)
printf 'second\n' >"$upstream/.bashrc"
git -C "$upstream" commit --quiet -am second
second=$(git -C "$upstream" rev-parse HEAD)
chome=$work/clone-home
mkdir -p "$chome"
# clone URL REF: cloneMyBash for a scratch HOME, its output in clone.out.
# shellcheck disable=SC2034,SC2329 # the variables are read by the extracted function
clone() {
	(
		HOME=$chome
		gitpath=$chome/.local/share/mybash
		MYBASH_URL=$1
		MYBASH_REF=$2
		# shellcheck disable=SC1091 # extracted above
		. "$work/clone_mybash"
		cloneMyBash
	) >"$work/clone.out" 2>&1
}
checkout=$chome/.local/share/mybash

# Fresh, offline: fails, and leaves nothing half made.
if clone "$work/no-such-repo" "$first"; then fail 'a failed first clone succeeded'; fi
[ ! -e "$checkout" ] || fail 'a failed first clone left a checkout'
set -- "$chome"/.local/share/mybash.new.*
[ ! -e "$1" ] || fail 'a failed first clone left its temporary directory'

# Fresh: cloned at the pinned commit.
clone "$upstream" "$first" || fail "the first clone failed: $(cat "$work/clone.out")"
[ "$(git -C "$checkout" rev-parse HEAD)" = "$first" ] || fail 'the first clone is not at the pinned commit'

# A new pin, no local changes: moved in place, the same directory.
inode=$(stat -c %i "$checkout")
clone "$upstream" "$second" || fail "updating failed: $(cat "$work/clone.out")"
[ "$(git -C "$checkout" rev-parse HEAD)" = "$second" ] || fail 'a clean checkout was not moved to the new pin'
[ "$(stat -c %i "$checkout")" = "$inode" ] || fail 'the checkout was replaced instead of updated in place'
clone "$upstream" "$second" || fail 'a second run at the same pin failed'
grep -Fq 'up to date' "$work/clone.out" || fail 'an up-to-date checkout was not said'

# The user edited ~/.bashrc (the file in the checkout): kept, not updated.
git -C "$checkout" checkout --quiet --detach "$first"
printf 'my alias\n' >>"$checkout/.bashrc"
clone "$upstream" "$second" || fail 'a checkout with local changes stopped the install'
grep -Fq 'my alias' "$checkout/.bashrc" || fail 'the user'"'"'s edit to .bashrc was lost'
grep -Fq 'local changes' "$work/clone.out" || fail 'keeping local changes was not said'
git -C "$checkout" checkout --quiet -- .bashrc

# Offline with a checkout: kept as it is, the install goes on.
git -C "$checkout" remote set-url origin "$work/no-such-repo"
clone "$work/no-such-repo" "$second" || fail 'an offline update stopped the install'
[ "$(git -C "$checkout" rev-parse HEAD)" = "$first" ] || fail 'an offline update changed the checkout'
grep -Fq 'keeping the version already there' "$work/clone.out" || fail 'a failed update was not said'

# Something that is not a checkout in its place: kept aside, never deleted.
rm -rf "$checkout"
mkdir -p "$checkout"
printf 'mine\n' >"$checkout/notes"
clone "$upstream" "$first" || fail "cloning over a non-checkout failed: $(cat "$work/clone.out")"
set -- "$chome"/.local/share/mybash.bak.*
[ -f "$1/notes" ] || fail 'a directory that was not a checkout was not kept aside'
[ -d "$checkout/.git" ] || fail 'no checkout after moving the old directory aside'

# The fzf fallback is pinned to a commit, not only a tag.
grep -Eq '^FZF_COMMIT="[0-9a-f]{40}"$' "$installer" || fail 'the fzf fallback is not pinned to a commit'

# ── It is reached, and only for the recommended profile ──────────────────

# Sync Sprint 12 S12-18: the clone that becomes ~/.bashrc is pinned to a
# reviewed commit, not taken at HEAD.
grep -Eq '^MYBASH_REF="[0-9a-f]{40}"$' "$installer" ||
	fail 'install-mybash does not pin mybash to a full commit hash'
# shellcheck disable=SC2016 # the $ is literal source text, not an expansion
grep -Fq 'checkout --quiet --detach "$MYBASH_REF"' "$installer" ||
	fail 'install-mybash does not check out the pinned mybash commit'

assert_contains "$repo/install.sh" 'scripts/install-mybash'
grep -Fq 'install-mybash' "$repo/Makefile" ||
	fail 'install-mybash is not installed onto PATH'

printf '%s\n' 'mybash shell configuration: PASS'
