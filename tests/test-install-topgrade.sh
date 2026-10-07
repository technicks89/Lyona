#!/usr/bin/env bash
set -euo pipefail

# #245: scripts/install-topgrade installs Topgrade from the AUR, against stub
# git, makepkg, sudo, pacman and cargo; the cargo-update rule; and where
# install.sh and the live medium's postinstall run it.
#
# - topgrade-bin is built at its pinned commit with makepkg as the user, and
#   only the built package (never a -debug split) is installed, with sudo
#   pacman -U. The build directory is removed afterwards.
# - No source fallback: only topgrade-bin is ever built, and nothing pulls in
#   Rust.
# - A PKGBUILD with a source and no checksum, or a SKIP checksum, or a checkout
#   that is not the pinned commit, is not built.
# - An installed Topgrade package is left alone (unless --force). An older
#   cargo-built copy in ~/.cargo/bin is described, never removed silently.
# - Root, and a build that fails both ways, install nothing.
# - --build-only builds topgrade-bin into a directory, prints only its path,
#   and never uses sudo.
# - No Rust toolchain or cargo-update anywhere in the map or install.sh.
# - install.sh: no Rust toolchain, --skip-topgrade, the install last after
#   sudo -k. The live medium builds it as the user once its sudoers file is
#   gone, and installs the package as root.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

installer=$repo/scripts/install-topgrade
export STUB_DIR=$work
stage_helpers checkout "$work/scripts" install-topgrade
helper=$work/scripts/install-topgrade

# The reviewed pin, and only that one.
pins=$(awk '/^readonly topgrade_pins=/ { f = 1 } f { print } f && /'"'"'$/ { exit }' "$installer")
[[ $pins == "readonly topgrade_pins='topgrade-bin	478487d31444ccbad24ab5d390d41466201b9dbc'" ]] ||
	fail "topgrade-bin is not the only base, at its reviewed commit: $pins"
if grep -nE -- '--syncdeps|--rmdeps|-s[a-z]*r' "$installer" | grep -v '^[0-9]*:#' | grep -q .; then
	fail 'install-topgrade pulls in build dependencies'
fi
# shellcheck disable=SC2016 # the literal text in the installer
grep -Fq 'readonly aur_url=${INSTALL_TOPGRADE_AUR_URL:-https://aur.archlinux.org}' "$installer" ||
	fail 'the AUR is not reached over HTTPS'
if grep -nE 'crates\.io|cargo install|rustup' "$installer" | grep -v '^[0-9]*:#' | grep -v 'cargo uninstall' | grep -q .; then
	fail "install-topgrade still builds with cargo: $(grep -nE 'crates\.io|cargo install|rustup' "$installer")"
fi

# git: clone writes nothing but the directory; checkout records the commit, and
# rev-parse reports it (or STUB_HEAD). STUB_GIT=fail fails the clone.
cat >"$work/bin/git" <<'EOF'
#!/bin/bash
printf 'git %s\n' "$*" >>"$STUB_DIR/log"
if [[ $1 == clone ]]; then
	[[ ${STUB_GIT:-} != fail ]] || exit 128
	dir=${*: -1}
	mkdir -p "$dir"
	printf '%s\n' "${*: -2:1}" >"$dir/.url"
	exit 0
fi
[[ $1 == -C ]] || exit 0
dir=$2
shift 2
while [[ $1 == -c ]]; do shift 2; done
case $1 in
checkout) printf '%s\n' "${*: -1}" >"$dir/.head" ;;
rev-parse) printf '%s\n' "${STUB_HEAD:-$(cat "$dir/.head")}" ;;
esac
EOF
# makepkg: --printsrcinfo prints a .SRCINFO (STUB_SRCINFO: ok, nosum or skip);
# a build writes BASE-1.0-1 and its -debug split, or fails for a base listed in
# STUB_FAIL.
cat >"$work/bin/makepkg" <<'EOF'
#!/bin/bash
base=$(basename "$(sed 's/\.git$//' .url)")
if [[ $1 == --printsrcinfo ]]; then
	printf 'pkgbase = %s\n\tpkgver = 1.0\n\tsource_x86_64 = %s.tar.gz::https://github.com/x/%s.tar.gz\n' "$base" "$base" "$base"
	printf '\tsource_aarch64 = other.tar.gz::https://github.com/x/other.tar.gz\n'
	case ${STUB_SRCINFO:-ok} in
	ok) printf '\tb2sums_x86_64 = abc123\n\tb2sums_aarch64 = def456\n' ;;
	skip) printf '\tb2sums_x86_64 = SKIP\n\tb2sums_aarch64 = def456\n' ;;
	nosum) printf '\tb2sums_aarch64 = def456\n' ;;
	esac
	printf '\npkgname = %s\n' "$base"
	exit 0
fi
printf 'makepkg %s %s (uid %s)\n' "$base" "$*" "$(id -u)" >>"$STUB_DIR/log"
[[ " ${STUB_FAIL:-} " != *" $base "* ]] || exit 4
: >"$base-1.0-1-x86_64.pkg.tar.zst"
: >"$base-debug-1.0-1-x86_64.pkg.tar.zst"
EOF
cat >"$work/bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$STUB_DIR/log"
[[ ${STUB_SUDO:-} != fail ]]
EOF
# pacman -Qq NAME, as pacman resolves provides: topgrade is STUB_INSTALLED, rust
# and cargo are STUB_RUST_PROVIDER; nothing installed when unset.
cat >"$work/bin/pacman" <<'EOF'
#!/bin/sh
[ "$1" = -Qq ] || exit 1
case $2 in
topgrade) value=${STUB_INSTALLED:-} ;;
rust | cargo) value=${STUB_RUST_PROVIDER:-} ;;
*) exit 1 ;;
esac
[ -n "$value" ] || exit 1
printf '%s\n' "$value"
EOF
cat >"$work/bin/cargo" <<'EOF'
#!/bin/sh
printf 'cargo %s\n' "$*" >>"$STUB_DIR/log"
EOF
# install: the system's, or a failure with STUB_INSTALL=fail.
cat >"$work/bin/install" <<EOF
#!/bin/sh
[ "\${STUB_INSTALL:-}" != fail ] || exit 1
exec $(command -v install) "\$@"
EOF
chmod +x "$work/bin/git" "$work/bin/makepkg" "$work/bin/sudo" "$work/bin/pacman" "$work/bin/cargo" "$work/bin/install"

# Tools from the system, without any topgrade, cargo, git or makepkg of its own.
mkdir -p "$work/sys"
for cmd in bash sh env sed grep awk sort head mkdir mktemp rm cp chmod install timeout id cat dirname \
	basename printf cut find uname; do
	ln -sf "$(command -v "$cmd")" "$work/sys/$cmd"
done
base_path=$work/bin:$work/sys
run() {
	env HOME="$work/home" PATH="$base_path" XDG_CACHE_HOME="$work/home/.cache" "$helper" "$@" </dev/null
}
reset() {
	rm -rf "${work:?}/home" "$work/log" "$work/out" "$work/err"
	mkdir -p "$work/home"
}
log_has() { grep -Fqx -- "$1" "$work/log" 2>/dev/null; }
no_build_dir() {
	! find "$work/home/.cache/lyona" -mindepth 1 -maxdepth 1 -name 'topgrade-build.*' 2>/dev/null | grep -q .
}

[[ $(run --print-plan) == 'topgrade-bin from the AUR (PKGBUILD pinned at 478487d31444), built with makepkg and installed with pacman' ]] ||
	fail "the plan line: $(run --print-plan)"

# A fresh machine: topgrade-bin at its pin, built as the user, and only its
# package installed.
reset
run >"$work/out" 2>"$work/err" || fail "the install failed: $(cat "$work/err")"
log_has 'git clone --quiet -- https://aur.archlinux.org/topgrade-bin.git '"$(grep -o "$work/home/.cache/lyona/topgrade-build\.[^ ]*/topgrade-bin\.[^ ]*/src" "$work/log" | head -n 1)" ||
	fail "the clone ran as: $(grep '^git clone' "$work/log")"
grep -Eq '^git -C [^ ]+/src -c advice.detachedHead=false checkout --quiet --detach 478487d31444ccbad24ab5d390d41466201b9dbc$' "$work/log" ||
	fail "the checkout ran as: $(grep checkout "$work/log")"
log_has "makepkg topgrade-bin --noconfirm (uid $(id -u))" || fail "makepkg ran as: $(grep makepkg "$work/log")"
grep -Eq "^sudo pacman -U --noconfirm --needed -- $work/home/.cache/lyona/topgrade-build\.[^/]+/topgrade-bin-1\.0-1-x86_64\.pkg\.tar\.zst$" "$work/log" ||
	fail "the package was installed as: $(grep '^sudo' "$work/log")"
[[ $(grep -c '^sudo' "$work/log") == 1 ]] || fail 'sudo ran for more than installing the package'
if grep -q 'topgrade-bin-debug' "$work/log"; then fail 'the -debug package was installed'; fi
no_build_dir || fail 'the build directory was left behind'
[[ -z $(cat "$work/out") ]] || fail "the install printed to stdout: $(cat "$work/out")"
grep -Fq 'Topgrade is installed; run topgrade. It updates itself through yay.' "$work/err" || fail "the install said: $(cat "$work/err")"

# Already installed as a package: left alone, unless --force.
reset
STUB_INSTALLED=topgrade-bin run 2>"$work/err" || fail 'an installed Topgrade failed the run'
[[ ! -e $work/log ]] || fail "an installed Topgrade was rebuilt: $(cat "$work/log")"
grep -Fq 'Topgrade is already installed (topgrade-bin)' "$work/err" || fail "an installed Topgrade: $(cat "$work/err")"
reset
STUB_INSTALLED=topgrade-bin run --force 2>/dev/null || fail '--force failed'
# Without --needed, which would skip the version already installed.
grep -Eq '^sudo pacman -U --noconfirm -- .*/topgrade-bin-1\.0-1-x86_64\.pkg\.tar\.zst$' "$work/log" ||
	fail "--force did not reinstall: $(grep '^sudo' "$work/log")"

# topgrade-bin cannot be built, or the AUR is unreachable: an error, nothing
# installed, and nothing else built.
for case in STUB_FAIL=topgrade-bin STUB_GIT=fail; do
	reset
	if env "$case" HOME="$work/home" PATH="$base_path" XDG_CACHE_HOME="$work/home/.cache" "$helper" \
		</dev/null 2>"$work/err"; then
		fail "$case: the install succeeded"
	fi
	if grep -q '^sudo' "$work/log" 2>/dev/null; then fail "$case: something was installed"; fi
	grep -Fq 'Topgrade could not be built from the AUR; check the network, then run install-topgrade again' "$work/err" ||
		fail "$case said: $(cat "$work/err")"
	no_build_dir || fail "$case: the build directory was left behind"
	if grep -q '^makepkg topgrade ' "$work/log" 2>/dev/null; then fail "$case: the source package was built"; fi
done

# A source without a checksum, a SKIP checksum, or a checkout that is not the
# pin: not built, either way.
for case in STUB_SRCINFO=nosum STUB_SRCINFO=skip STUB_HEAD=0000000000000000000000000000000000000000; do
	reset
	if env "$case" HOME="$work/home" PATH="$base_path" XDG_CACHE_HOME="$work/home/.cache" "$helper" \
		</dev/null 2>"$work/err"; then
		fail "$case: the install succeeded"
	fi
	if grep -q '^makepkg' "$work/log"; then fail "$case: makepkg built: $(grep makepkg "$work/log")"; fi
	if grep -q '^sudo' "$work/log"; then fail "$case: something was installed"; fi
done
grep -q 'has a source without a checksum; not building it' <<<"$(
	reset
	STUB_SRCINFO=skip run 2>&1 || :
)" || fail 'a SKIP checksum was not named'

# Root: refused, nothing built.
cat >"$work/root-id" <<'EOF'
#!/bin/sh
[ "$1" = -u ] && { echo 0; exit 0; }
exec /usr/bin/id "$@"
EOF
mkdir -p "$work/rootbin"
cp "$work/root-id" "$work/rootbin/id"
chmod +x "$work/rootbin/id"
reset
if env HOME="$work/home" PATH="$work/rootbin:$base_path" "$helper" </dev/null 2>"$work/err"; then fail 'root was not refused'; fi
grep -Fq 'run as the target user, not as root' "$work/err" || fail "root was refused with: $(cat "$work/err")"
[[ ! -e $work/log ]] || fail 'root built something'

# --build-only: the package's path alone on stdout, in the directory; no sudo.
reset
mkdir -p "$work/out-dir"
rm -f "$work/out-dir"/*
path=$(run --build-only "$work/out-dir" 2>"$work/err") || fail "--build-only failed: $(cat "$work/err")"
[[ $path == "$work/out-dir/topgrade-bin-1.0-1-x86_64.pkg.tar.zst" && -f $path ]] || fail "--build-only printed: $path"
[[ $(find "$work/out-dir" -mindepth 1 | wc -l) == 1 ]] || fail "--build-only left: $(ls -A "$work/out-dir")"
if grep -q '^sudo' "$work/log"; then fail '--build-only used sudo'; fi
reset
rm -f "$work/out-dir"/*
if STUB_FAIL=topgrade-bin run --build-only "$work/out-dir" >/dev/null 2>&1; then fail '--build-only succeeded without topgrade-bin'; fi
# The package cannot be copied out: a failure, and no path printed.
reset
rm -f "$work/out-dir"/*
if path=$(STUB_INSTALL=fail run --build-only "$work/out-dir" 2>/dev/null); then fail '--build-only succeeded although the copy failed'; fi
[[ -z $path ]] || fail "a failed copy printed a path: $path"
reset
if STUB_INSTALL=fail run >/dev/null 2>&1; then fail 'an install succeeded although the copy failed'; fi
if grep -q '^sudo' "$work/log"; then fail 'pacman ran although the copy failed'; fi
if run --build-only "$work/no-such-dir" >/dev/null 2>&1; then fail '--build-only accepted a missing directory'; fi
STUB_INSTALLED=topgrade-bin run --build-only "$work/out-dir" >/dev/null 2>&1 || fail '--build-only skipped the build for an installed Topgrade'

# An older cargo-built Topgrade: described, and left in place without a terminal.
reset
mkdir -p "$work/home/.cargo/bin"
printf '#!/bin/sh\n' >"$work/home/.cargo/bin/topgrade"
chmod +x "$work/home/.cargo/bin/topgrade"
run 2>"$work/err" || fail 'the install failed beside a cargo-built Topgrade'
[[ -x $work/home/.cargo/bin/topgrade ]] || fail 'the cargo-built Topgrade was removed without asking'
grep -Fq 'left in place; remove it with: cargo uninstall topgrade' "$work/err" || fail "the cargo copy: $(cat "$work/err")"
if grep -q '^cargo' "$work/log"; then fail 'cargo ran without asking'; fi

# Options.
if run --frobnicate >/dev/null 2>&1; then fail 'an unknown option was accepted'; fi
if run --build-only >/dev/null 2>&1; then fail '--build-only without a directory was accepted'; fi
reset
out=$(run --dry-run 2>&1)
[[ $out == *'would build topgrade-bin (AUR commit 478487d31444ccbad24ab5d390d41466201b9dbc) with makepkg and install it with sudo pacman -U'* ]] ||
	fail "a dry run: $out"
[[ ! -e $work/log ]] || fail 'a dry run changed something'
run --help | grep -Fq 'cargo uninstall topgrade' || fail 'the help does not say how to remove a cargo-built Topgrade'

# No Rust: no toolchain or cargo-update profile, nothing Rust in the
# recommended packages, and no Rust rules left in the map.
# shellcheck source=scripts/dwm-packages.sh
. "$repo/scripts/dwm-packages.sh"
for name in rustup rust cargo cargo-update; do
	if dwm_packages arch full | grep -Fxq "$name"; then fail "$name is in the full profile"; fi
done
for profile in rust-toolchain cargo-update; do
	if dwm_packages arch "$profile" | grep -q .; then fail "the $profile profile still exists"; fi
done
if declare -F dwm_other_rust_toolchain >/dev/null; then fail 'dwm_other_rust_toolchain is still defined'; fi

# install.sh: no Rust toolchain or cargo-update; the skip flag; the plan line;
# and the install last, after the sudo timestamp is closed.
if grep -nE 'rust-toolchain|rustup|cargo-update' "$repo/install.sh" | grep -q .; then
	fail "install.sh still installs Rust: $(grep -nE 'rust-toolchain|rustup|cargo-update' "$repo/install.sh")"
fi
"$repo/install.sh" --dry-run --non-interactive --profile recommended >"$work/plan"
grep -Fq 'Topgrade: topgrade-bin from the AUR (PKGBUILD pinned at 478487d31444)' "$work/plan" ||
	fail "the install plan: $(grep Topgrade "$work/plan")"
"$repo/install.sh" --dry-run --non-interactive --profile full --skip-topgrade >"$work/skip-plan"
grep -Fqx '  Topgrade: skipped (--skip-topgrade)' "$work/skip-plan" || fail '--skip-topgrade is not in the plan'
DWM_INSTALL_TOPGRADE=false "$repo/install.sh" --dry-run --non-interactive --profile full >"$work/env-plan"
grep -Fqx '  Topgrade: skipped (--skip-topgrade)' "$work/env-plan" || fail 'DWM_INSTALL_TOPGRADE=false was ignored'
if DWM_INSTALL_TOPGRADE=maybe "$repo/install.sh" --dry-run --non-interactive >/dev/null 2>&1; then
	fail 'an unsupported DWM_INSTALL_TOPGRADE was accepted'
fi
"$repo/install.sh" --dry-run --non-interactive --profile core >"$work/core-plan"
if grep -Fq 'Topgrade: topgrade-bin' "$work/core-plan"; then fail 'a core install plans Topgrade'; fi
displays=$(grep -n '^configure_displays_after_install$' "$repo/install.sh" | cut -d: -f1)
sudo_k=$(grep -nF 'sudo -k 2>/dev/null' "$repo/install.sh" | cut -d: -f1)
# shellcheck disable=SC2016 # the literal text in install.sh
build=$(grep -nF '"$REPO_DIR/scripts/install-topgrade" </dev/null || topgrade_status=$?' "$repo/install.sh" | cut -d: -f1)
last_sudo=$(grep -nE '^[[:space:]]*sudo [a-z]' "$repo/install.sh" | grep -v 'sudo -k' | tail -n 1 | cut -d: -f1)
[[ -n $displays && -n $sudo_k && -n $build && -n $last_sudo ]] || fail 'could not find the Topgrade steps in install.sh'
((sudo_k > displays && build > sudo_k && build > last_sudo)) ||
	fail "install.sh does not install Topgrade last, after sudo -k (displays $displays, sudo -k $sudo_k, build $build, last sudo $last_sudo)"

# The live medium: install.sh skips it; it is built as the user once the
# passwordless sudoers file is gone, and root installs only the built package.
postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
grep -Fq './install.sh --non-interactive --profile full --skip-topgrade' "$postinstall" ||
	fail 'the live medium does not skip Topgrade in install.sh'
# shellcheck disable=SC2016 # the literal text in the postinstall
removed=$(grep -n '^rm -f -- "$install_sudoers"$' "$postinstall" | tail -n 1 | cut -d: -f1)
topgrade=$(grep -n 'run_logged "Installing Topgrade from the AUR\.\.\." install_topgrade' "$postinstall" | cut -d: -f1)
if [[ -z $removed || -z $topgrade ]] || ((topgrade <= removed)); then
	fail 'the live medium installs Topgrade before its sudoers file is removed'
fi
grep -Eq '^[[:space:]]+install_networkmanager setup_swap_if_needed install_qemu_guest_utils install_topgrade$' "$postinstall" ||
	fail 'install_topgrade is not exported for run_logged'
awk '/^install_topgrade\(\) \{$/ { f = 1 } f { print } f && /^}$/ { exit }' "$postinstall" >"$work/install_topgrade.sh"
grep -q '^}$' "$work/install_topgrade.sh" || fail 'could not find install_topgrade in the postinstall'
# arch-chroot: runs runuser by printing a built package's path (or failing with
# STUB_BUILD=fail); everything else is only logged.
cat >"$work/bin/arch-chroot" <<'EOF'
#!/bin/bash
shift
printf 'chroot %s\n' "$*" >>"$STUB_DIR/chroot.log"
if [[ $1 == runuser ]]; then
	[[ ${STUB_BUILD:-} != fail ]] || exit 1
	printf '/var/tmp/lyona-topgrade/topgrade-bin-1.0-1-x86_64.pkg.tar.zst\n'
fi
EOF
chmod +x "$work/bin/arch-chroot"
postinstall_topgrade() {
	rm -f "$work/chroot.log"
	# shellcheck disable=SC2016 # expanded by the inner shell
	env PATH="$work/bin:$work/sys" TARGET=/mnt target_user=alice target_group=alice target_home=/home/alice \
		checkout_rel=.local/src/lyona bash -c '. "$1"; install_topgrade' _ "$work/install_topgrade.sh" >/dev/null
}
postinstall_topgrade || fail 'the postinstall Topgrade step failed'
grep -Fqx 'chroot runuser -u alice -- env HOME=/home/alice /home/alice/.local/src/lyona/scripts/install-topgrade --build-only /var/tmp/lyona-topgrade' "$work/chroot.log" ||
	fail "the postinstall did not build as the user: $(cat "$work/chroot.log")"
grep -Fqx 'chroot pacman -U --noconfirm --needed -- /var/tmp/lyona-topgrade/topgrade-bin-1.0-1-x86_64.pkg.tar.zst' "$work/chroot.log" ||
	fail "the postinstall did not install the built package: $(cat "$work/chroot.log")"
if grep -Eq 'rustup|cargo|pacman -S' "$work/chroot.log"; then fail "the postinstall installed a toolchain: $(cat "$work/chroot.log")"; fi
tail -n 1 "$work/chroot.log" | grep -Fqx 'chroot rm -rf -- /var/tmp/lyona-topgrade' || fail 'the postinstall left its build directory'
if STUB_BUILD=fail postinstall_topgrade; then fail 'a failed build passed the postinstall step'; fi
if grep -q 'pacman -U' "$work/chroot.log"; then fail 'the postinstall installed a package after a failed build'; fi
tail -n 1 "$work/chroot.log" | grep -Fqx 'chroot rm -rf -- /var/tmp/lyona-topgrade' || fail 'a failed build left its build directory'

printf 'install-topgrade: PASS\n'
