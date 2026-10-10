#!/usr/bin/env bash
set -euo pipefail

# #339: scripts/install-yay is the one place yay is installed, for install.sh
# and the live medium's postinstall, against stub git, makepkg and sudo.
#
# - yay-bin is built at its pinned commit with makepkg as the user, after the
#   sudo timestamp is closed (#328), and only the built package (never a -debug
#   split) is installed, with sudo pacman -U. The build directory is removed.
# - A non-interactive run answers pacman (--noconfirm) and never waits for a
#   sudo password: where sudo needs one it installs nothing, says so and exits
#   3 before building. Where sudo needs none, sudo -n installs the package.
# - yay (or paru) already on PATH: nothing is built.
# - A failed build installs nothing and exits 1.
# - --build-only builds into a directory, prints only the package's path, and
#   never uses sudo. --print-plan prints the summary line.
# - install.sh and the postinstall go through it; neither builds yay itself.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

installer=$repo/scripts/install-yay
export STUB_DIR=$work
stage_helpers checkout "$work/scripts" install-yay
helper=$work/scripts/install-yay

pin=$(bash "$repo/scripts/dwm-aur.sh" pin yay-bin)
[[ $pin == 13e0a4754d106a9252b7479bf1b370fbe454fc48 ]] || fail "yay-bin is not at its reviewed commit: $pin"
# shellcheck disable=SC2016 # the literal text in the installer
[[ $(grep -oE 'build-pinned "?\$?[a-z_-]+' "$installer" | sort -u) == 'build-pinned "$base' ]] &&
	[[ $(grep -oE 'build_pin [a-z-]+' "$installer" | sort -u) == 'build_pin yay-bin' ]] ||
	fail 'install-yay builds another AUR base than yay-bin, or not through dwm-aur.sh'
if grep -nE 'aur\.archlinux\.org|git clone|makepkg --' "$installer" | grep -v '^[0-9]*:#' | grep -q .; then
	fail 'install-yay reaches the AUR itself, not through dwm-aur.sh'
fi

# git: clone writes nothing but the directory; checkout records the commit, and
# rev-parse reports it.
cat >"$work/bin/git" <<'EOF2'
#!/bin/bash
printf 'git %s\n' "$*" >>"$STUB_DIR/log"
if [[ $1 == clone ]]; then
	dir=${*: -1}
	mkdir -p "$dir"
	printf '%s\n' "${*: -2:1}" >"$dir/.url"
	: >"$dir/PKGBUILD"
	exit 0
fi
[[ $1 == -C ]] || exit 0
dir=$2
shift 2
while [[ $1 == -c ]]; do shift 2; done
case $1 in
checkout) printf '%s\n' "${*: -1}" >"$dir/.head" ;;
rev-parse) cat "$dir/.head" ;;
esac
EOF2
# makepkg: --printsrcinfo prints a checksummed .SRCINFO; a build writes
# BASE-1.0-1 and its -debug split, or fails for a base listed in STUB_FAIL.
cat >"$work/bin/makepkg" <<'EOF2'
#!/bin/bash
base=$(basename "$(sed 's/\.git$//' .url)")
if [[ $1 == --printsrcinfo ]]; then
	printf 'pkgbase = %s\n\tpkgver = 1.0\n\tsource_x86_64 = %s.tar.gz::https://github.com/x/%s.tar.gz\n' "$base" "$base" "$base"
	printf '\tb2sums_x86_64 = abc123\n\npkgname = %s\n' "$base"
	exit 0
fi
printf 'makepkg %s %s (uid %s)\n' "$base" "$*" "$(id -u)" >>"$STUB_DIR/log"
[[ " ${STUB_FAIL:-} " != *" $base "* ]] || exit 4
: >"$base-1.0-1-x86_64.pkg.tar.zst"
: >"$base-debug-1.0-1-x86_64.pkg.tar.zst"
EOF2
# sudo: logs; "sudo -n true" fails when STUB_SUDO_N=fail (a password needed).
cat >"$work/bin/sudo" <<'EOF2'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$STUB_DIR/log"
if [[ $1 == -n && $2 == true ]]; then [[ ${STUB_SUDO_N:-} != fail ]]; exit; fi
[[ ${STUB_SUDO:-} != fail ]]
EOF2
chmod +x "$work/bin/git" "$work/bin/makepkg" "$work/bin/sudo"

# Tools from the system, without any yay, paru, git or makepkg of its own.
mkdir -p "$work/sys" "$work/with-yay"
for cmd in bash sh env sed grep awk sort head mkdir mktemp rm cp chmod install timeout id cat dirname \
	basename printf cut find uname; do
	ln -sf "$(command -v "$cmd")" "$work/sys/$cmd"
done
printf '#!/bin/sh\n' >"$work/with-yay/yay"
chmod +x "$work/with-yay/yay"
base_path=$work/bin:$work/sys
run() { # RUN_PATH in the environment puts a directory before the base PATH
	env HOME="$work/home" PATH="${RUN_PATH:-$base_path}" XDG_CACHE_HOME="$work/home/.cache" "$helper" "$@" </dev/null
}
reset() {
	rm -rf "${work:?}/home" "$work/log" "$work/out" "$work/err"
	mkdir -p "$work/home"
}
log_has() { grep -Fqx -- "$1" "$work/log" 2>/dev/null; }
no_build_dir() {
	! find "$work/home/.cache/lyona" -mindepth 1 -maxdepth 1 -name 'yay-build.*' 2>/dev/null | grep -q .
}

[[ $(run --print-plan) == "yay-bin from the AUR (PKGBUILD pinned at ${pin:0:12}), built with makepkg and installed with pacman" ]] ||
	fail "the plan line: $(run --print-plan)"

# A fresh machine, at a terminal: the timestamp closed, yay-bin at its pin built
# as the user, and only its package installed, with a sudo that may ask.
reset
run >"$work/out" 2>"$work/err" || fail "the install failed: $(cat "$work/err")"
[[ $(grep -m1 -n '^sudo -k$' "$work/log" | cut -d: -f1) -lt $(grep -m1 -n '^makepkg' "$work/log" | cut -d: -f1) ]] ||
	fail "the sudo timestamp was not closed before the build: $(cat "$work/log")"
grep -Eq "^git -C [^ ]+/src -c advice.detachedHead=false checkout --quiet --detach $pin\$" "$work/log" ||
	fail "the checkout ran as: $(grep checkout "$work/log")"
log_has "makepkg yay-bin --noconfirm --nocheck (uid $(id -u))" || fail "makepkg ran as: $(grep makepkg "$work/log")"
grep -Eq "^sudo pacman -U --needed -- $work/home/.cache/lyona/yay-build\.[^/]+/yay-bin-1\.0-1-x86_64\.pkg\.tar\.zst$" "$work/log" ||
	fail "the package was installed as: $(grep '^sudo pacman' "$work/log")"
[[ $(grep -c '^sudo pacman' "$work/log") == 1 ]] || fail 'pacman ran more than once'
if grep -q 'yay-bin-debug' "$work/log"; then fail 'the -debug package was installed'; fi
if grep -q '^sudo -n' "$work/log"; then fail 'an interactive run probed sudo -n'; fi
no_build_dir || fail 'the build directory was left behind'
[[ -z $(cat "$work/out") ]] || fail "the install printed to stdout: $(cat "$work/out")"
grep -Fq 'yay is installed.' "$work/err" || fail "the install said: $(cat "$work/err")"

# Non-interactive where sudo needs no password: pacman answered, sudo -n.
reset
INSTALL_YAY_NON_INTERACTIVE=1 run 2>"$work/err" || fail "a non-interactive install failed: $(cat "$work/err")"
log_has 'sudo -n true' || fail 'a non-interactive run did not check whether sudo needs a password'
grep -Eq '^sudo -n pacman -U --needed --noconfirm -- /.*/yay-bin-1\.0-1-x86_64\.pkg\.tar\.zst$' "$work/log" ||
	fail "a non-interactive run installed as: $(grep '^sudo' "$work/log")"

# Non-interactive where sudo needs a password: nothing built, exit 3, said so.
reset
status=0
INSTALL_YAY_NON_INTERACTIVE=1 STUB_SUDO_N=fail run 2>"$work/err" || status=$?
[[ $status == 3 ]] || fail "a non-interactive run that cannot ask exited $status, not 3"
if grep -q '^makepkg\|^git clone' "$work/log"; then fail 'a run that could not install still built'; fi
grep -Fq 'sudo needs a password, which a non-interactive run cannot give' "$work/err" || fail "it said: $(cat "$work/err")"

# yay already on PATH: nothing built, nothing run as root.
reset
RUN_PATH="$work/with-yay:$base_path" run 2>"$work/err" || fail 'an installed yay failed the run'
[[ ! -e $work/log ]] || fail "an installed yay was rebuilt: $(cat "$work/log")"
grep -Fq 'an AUR helper is already installed' "$work/err" || fail "an installed yay: $(cat "$work/err")"

# A failed build: no package installed, exit 1.
reset
status=0
STUB_FAIL=yay-bin run 2>"$work/err" || status=$?
[[ $status == 1 ]] || fail "a failed build exited $status"
if grep -q '^sudo pacman' "$work/log"; then fail 'a failed build still ran pacman'; fi
grep -Fq 'yay could not be built from the AUR' "$work/err" || fail "a failed build said: $(cat "$work/err")"
no_build_dir || fail 'a failed build left its directory behind'

# --build-only: the package's path on stdout, nothing installed, no sudo.
reset
mkdir -p "$work/out-dir"
package=$(run --build-only "$work/out-dir" 2>"$work/err") || fail "--build-only failed: $(cat "$work/err")"
[[ $package == "$work/out-dir/yay-bin-1.0-1-x86_64.pkg.tar.zst" ]] || fail "--build-only printed: $package"
[[ -f $package ]] || fail '--build-only printed a package that does not exist'
if grep -q '^sudo' "$work/log"; then fail '--build-only used sudo'; fi
status=0
run --build-only "$work/missing" 2>/dev/null || status=$?
[[ $status == 1 ]] || fail '--build-only accepted a missing directory'

# install.sh and the live medium go through it, and neither builds yay itself.
grep -Fq 'INSTALL_YAY_NON_INTERACTIVE=1 "$REPO_DIR/scripts/install-yay" </dev/null' "$repo/install.sh" ||
	fail 'install.sh does not run install-yay non-interactively'
# shellcheck disable=SC2016 # the literal text in install.sh
grep -Fq '"$REPO_DIR/scripts/install-yay" || status=$?' "$repo/install.sh" || fail 'install.sh does not run install-yay'
grep -Fq 'only where sudo needs no password' "$repo/install.sh" || fail 'install.sh does not say when a non-interactive run skips yay'
postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
grep -Fq 'scripts/install-yay" --build-only "$build"' "$postinstall" || fail 'the postinstall does not build yay through install-yay'
grep -Fq 'dwm_packages arch aur-build' "$postinstall" || fail 'the postinstall does not take the AUR build prerequisites from the map'
if grep -n 'build-pinned yay-bin' "$repo/install.sh" "$postinstall" | grep -q .; then
	fail 'install.sh or the postinstall still builds yay-bin itself'
fi
grep -Eq '^[[:space:]]+scripts/install-yay[[:space:]]' "$repo/Makefile" || fail 'install-yay is not installed'

printf 'install-yay: PASS\n'
