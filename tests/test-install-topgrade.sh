#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 15 S15-06 (decision D-28): scripts/install-topgrade against stub
# curl, cargo, rustup, pacman and id; the shared rule that leaves rustup out
# beside another Rust toolchain; and where install.sh and the live medium's
# postinstall build it.
#
# - The version is the newest on crates.io, looked up each run (with a user
#   agent, over HTTPS only), and built --locked into $CARGO_HOME/bin, in a
#   private directory removed afterwards.
# - A rerun upgrades an older Topgrade, and leaves the newest alone; one
#   installed some other way is kept (unless --force).
# - With rustup and no toolchain set, stable (minimal) is set up; without
#   rustup (Arch's rust), no toolchain step runs.
# - Root, no cargo, a failed or odd lookup, a failed build and a wrong version
#   all fail, and build nothing.
# - rustup is skipped beside Arch's rust, another provider, or a rustup.rs
#   cargo; never beside rustup itself.
# - install.sh: --skip-topgrade, a guarded toolchain install, and the build
#   last, after sudo -k. The live medium builds it after its sudoers file is
#   gone.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
command -v jq >/dev/null 2>&1 || {
	printf 'SKIP: jq is unavailable\n'
	exit 77
}

installer=$repo/scripts/install-topgrade
grep -Fq 'readonly crates_api=https://crates.io/api/v1/crates/topgrade' "$installer" ||
	fail 'the newest version is not looked up on crates.io'
# shellcheck disable=SC2016 # the literal text in the installer
grep -Fq 'timeout --kill-after=30 "$build_seconds"' "$installer" || fail 'the build is not bounded in time'

export STUB_DIR=$work
stage_helpers checkout "$work/scripts" install-topgrade
helper=$work/scripts/install-topgrade

# curl: the crates.io answer for topgrade, with STUB_LATEST as the newest version,
# or a failure with STUB_CURL=fail.
cat >"$work/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >>"$STUB_DIR/log"
[[ ${STUB_CURL:-} != fail ]] || exit 22
printf '{"crate":{"name":"topgrade","max_stable_version":"%s"}}\n' "${STUB_LATEST-17.12.3}"
EOF
# cargo install ... --version V --root ROOT ...: logs, then writes ROOT/bin/topgrade
# reporting STUB_BUILT_VERSION (default: V).
cat >"$work/bin/cargo" <<'EOF'
#!/bin/bash
printf 'cargo %s\n' "$*" >>"$STUB_DIR/log"
[[ $1 == install ]] || exit 0
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
	case ${args[i]} in
	--version) version=${args[i + 1]} ;;
	--root) root=${args[i + 1]} ;;
	--target-dir) target=${args[i + 1]} ;;
	esac
done
# A real cargo has fetched crates into the registry before a build fails.
mkdir -p "$target" "$root/registry/cache"
printf '%s\n' "$target" >"$STUB_DIR/target-dir"
[[ ${STUB_CARGO:-} != fail ]] || exit 101
mkdir -p "$root/bin"
printf '#!/bin/sh\necho "topgrade %s"\n' "${STUB_BUILT_VERSION:-$version}" >"$root/bin/topgrade"
chmod +x "$root/bin/topgrade"
EOF
# rustup: `show active-toolchain` succeeds once a default is set.
cat >"$work/bin/rustup" <<'EOF'
#!/bin/bash
printf 'rustup %s\n' "$*" >>"$STUB_DIR/log"
case "$1 $2" in
'show active-toolchain') [[ -e $STUB_DIR/toolchain ]] ;;
'default stable') : >"$STUB_DIR/toolchain" ;;
*) exit 0 ;;
esac
EOF
# pacman -Qq NAME: prints STUB_RUST_PROVIDER for rust and cargo, as pacman
# resolves provides; nothing installed when it is unset.
cat >"$work/bin/pacman" <<'EOF'
#!/bin/sh
[ "$1" = -Qq ] || exit 1
case $2 in
rust | cargo)
	[ -n "${STUB_RUST_PROVIDER:-}" ] || exit 1
	printf '%s\n' "$STUB_RUST_PROVIDER"
	;;
*) exit 1 ;;
esac
EOF
chmod +x "$work/bin/curl" "$work/bin/cargo" "$work/bin/rustup" "$work/bin/pacman"

# Tools from the system, without any topgrade, cargo or rustup of its own.
mkdir -p "$work/sys"
for cmd in bash sh env sed grep awk sort head mkdir mktemp rm cp chmod timeout id cat dirname printf cut find jq nproc; do
	ln -sf "$(command -v "$cmd")" "$work/sys/$cmd"
done
base_path=$work/bin:$work/sys

# A machine with 5 GiB available, unless a test says otherwise: two jobs.
printf 'MemTotal:       16000000 kB\nMemAvailable:    5242880 kB\n' >"$work/meminfo"
run() {
	env HOME="$work/home" PATH="$base_path" XDG_CACHE_HOME="$work/home/.cache" \
		INSTALL_TOPGRADE_MEMINFO="${STUB_MEMINFO:-$work/meminfo}" "$helper" "$@"
}
reset() {
	rm -rf "${work:?}/home" "$work/log" "$work/toolchain" "$work/target-dir"
	mkdir -p "$work/home"
}
built_by_cargo() { grep -q '^cargo install' "$work/log" 2>/dev/null; }
installed_version() { "${1:-$work/home/.cargo}/bin/topgrade" --version; }

# A fresh machine: the newest version looked up, stable (minimal) set up, and a
# locked build of exactly that version.
reset
run >"$work/out" || fail "the install failed: $(cat "$work/out")"
grep -Eq '^curl .*--proto =https --tlsv1\.2 .*-A lyona-install-topgrade .*https://crates\.io/api/v1/crates/topgrade$' "$work/log" ||
	fail "the lookup ran as: $(grep '^curl' "$work/log")"
[[ $(grep -c '^rustup' "$work/log") == 3 ]] || fail "the toolchain steps: $(cat "$work/log")"
grep -Fqx 'rustup toolchain install stable --profile minimal' "$work/log" || fail 'stable (minimal) was not installed'
jobs=2
(($(nproc) >= 2)) || jobs=1
grep -Eq "^cargo install --locked --force --jobs $jobs --version 17\.12\.3 --root $work/home/.cargo --target-dir $work/home/.cache/lyona/topgrade-build\.[^ ]+/target topgrade$" "$work/log" ||
	fail "the build ran as: $(grep '^cargo' "$work/log")"
# Sync Sprint 16 R16-33: the jobs follow the memory there is. Under 2 GiB: one.
reset
printf 'MemAvailable:    1048576 kB\n' >"$work/low-meminfo"
STUB_MEMINFO=$work/low-meminfo run >/dev/null 2>&1 || fail 'the low-memory install failed'
grep -q '^cargo install --locked --force --jobs 1 ' "$work/log" || fail "a low-memory build: $(grep '^cargo' "$work/log")"
# A CARGO_BUILD_JOBS the user set is kept.
reset
CARGO_BUILD_JOBS=3 run >/dev/null 2>&1 || fail 'the install with CARGO_BUILD_JOBS failed'
grep -q '^cargo install --locked --force --jobs 3 ' "$work/log" || fail "CARGO_BUILD_JOBS=3: $(grep '^cargo' "$work/log")"
reset
run >"$work/out" || fail "the install failed: $(cat "$work/out")"
[[ $(installed_version) == 'topgrade 17.12.3' ]] || fail 'the newest Topgrade was not installed'
[[ ! -e $(cat "$work/target-dir") ]] || fail 'the build directory was left behind'
[[ -z $(find "$work/home/.cache/lyona" -mindepth 1 2>/dev/null) ]] || fail 'the cache directory was not cleaned'
[[ ! -e $work/home/.cargo/registry ]] || fail 'the crate downloads this build made were left behind'
grep -Fq "$work/home/.cargo/bin is not on PATH" "$work/out" || fail 'no PATH hint when ~/.cargo/bin is not on PATH'

# The newest is already there: nothing is built.
rm -f "$work/log"
out=$(run)
[[ $out == *'Topgrade 17.12.3, the newest release, is already installed'* ]] || fail "a second run: $out"
! built_by_cargo || fail 'a second run built again'

# A newer release appears: a rerun upgrades to it, and a toolchain already set is used.
rm -f "$work/log"
out=$(STUB_LATEST=17.13.0 run)
[[ $out == *'upgrading Topgrade 17.12.3 to 17.13.0'* ]] || fail "an upgrade: $out"
[[ $(installed_version) == 'topgrade 17.13.0' ]] || fail 'Topgrade was not upgraded to the newest release'
[[ $(grep -c '^rustup' "$work/log") == 1 ]] || fail "the upgrade changed the toolchain: $(cat "$work/log")"

# --force rebuilds the newest; a registry the user already had is kept.
mkdir -p "$work/home/.cargo/registry/index"
rm -f "$work/log"
STUB_LATEST=17.13.0 run --force >/dev/null || fail '--force failed'
built_by_cargo || fail '--force did not build'
[[ -d $work/home/.cargo/registry/index ]] || fail "the user's own cargo registry was removed"

# Topgrade installed some other way (an AUR package, say): kept unless --force.
reset
mkdir -p "$work/other"
printf '#!/bin/sh\necho "topgrade 17.0.0"\n' >"$work/other/topgrade"
chmod +x "$work/other/topgrade"
out=$(base_path=$work/bin:$work/sys:$work/other run)
[[ $out == *"already installed at $work/other/topgrade (17.0.0); leaving it"* ]] || fail "another Topgrade: $out"
! built_by_cargo || fail 'a Topgrade installed another way was built over'
base_path=$work/bin:$work/sys:$work/other run --force >/dev/null || fail '--force beside another Topgrade failed'
built_by_cargo || fail '--force did not build beside another Topgrade'

# A custom CARGO_HOME: the binary and the check both follow it.
reset
CARGO_HOME=$work/cargo-home run >/dev/null || fail 'the install with CARGO_HOME failed'
grep -Fq -- "--root $work/cargo-home " "$work/log" || fail 'the build ignored CARGO_HOME'
[[ $(installed_version "$work/cargo-home") == 'topgrade 17.12.3' ]] || fail 'Topgrade is not in CARGO_HOME/bin'
rm -f "$work/log"
CARGO_HOME=$work/cargo-home run >/dev/null
! built_by_cargo || fail 'the newest Topgrade in CARGO_HOME/bin was built again'

# Arch's rust instead of rustup: no toolchain step, and the plan says so.
reset
mv "$work/bin/rustup" "$work/rustup.off"
run >/dev/null || fail 'the build with Arch rust failed'
! grep -q '^rustup' "$work/log" 2>/dev/null || fail 'a toolchain step ran without rustup'
mv "$work/rustup.off" "$work/bin/rustup"
plan=$(STUB_RUST_PROVIDER=rust run --print-plan)
[[ $plan == 'the newest release from crates.io, built with cargo, using the installed Rust toolchain (rust)' ]] ||
	fail "the plan with Arch rust: $plan"
# Arch's rustup package answers for rust (pacman -Qq resolves provides).
plan=$(STUB_RUST_PROVIDER=rustup run --print-plan)
[[ $plan == *'using rustup' ]] || fail "the plan with rustup: $plan"

# Failures build nothing.
for case in 'STUB_CURL=fail' 'STUB_LATEST=' 'STUB_LATEST=17.13.0-beta.1' 'STUB_LATEST=1.2;rm' 'STUB_CARGO=fail' 'STUB_BUILT_VERSION=0.0.1'; do
	reset
	if env "$case" HOME="$work/home" PATH="$base_path" XDG_CACHE_HOME="$work/home/.cache" "$helper" >/dev/null 2>&1; then
		fail "it reported success with $case"
	fi
	case $case in
	STUB_CARGO=* | STUB_BUILT_VERSION=*) ;;
	*) ! built_by_cargo || fail "it built with $case" ;;
	esac
done
# A failed build still removes its build directory and the crate downloads it made.
reset
if STUB_CARGO=fail run >/dev/null 2>&1; then fail 'a failed build was reported as installed'; fi
[[ -s $work/target-dir && ! -e $(cat "$work/target-dir") ]] || fail 'a failed build left its build directory'
[[ ! -e $work/home/.cargo/registry ]] || fail 'a failed build left the crate downloads it made'
reset
out=$(env HOME="$work/home" PATH="$work/sys" "$helper" 2>&1) && fail 'it succeeded without curl and cargo'
[[ $out == *'curl is not installed'* ]] || fail "without curl: $out"
mkdir -p "$work/curl-only"
ln -sf "$work/bin/curl" "$work/curl-only/curl"
out=$(env HOME="$work/home" PATH="$work/curl-only:$work/sys" "$helper" 2>&1) && fail 'it succeeded without cargo'
[[ $out == *'install rustup first'* ]] || fail "without cargo: $out"
cat >"$work/bin/id" <<'EOF'
#!/bin/sh
[ "$1" = -u ] && echo 0
EOF
chmod +x "$work/bin/id"
out=$(run 2>&1) && fail 'it ran as root'
[[ $out == *'not as root'* ]] || fail "as root: $out"
rm "$work/bin/id"
if run --frobnicate >/dev/null 2>&1; then fail 'an unknown option was accepted'; fi
reset
out=$(run --dry-run)
[[ $out == *'would look up the newest Topgrade release on crates.io'* ]] || fail "a dry run: $out"
[[ ! -e $work/log && ! -e $work/home/.cargo ]] || fail 'a dry run changed something'

# The shared rule: rustup only where no other Rust toolchain is installed.
# shellcheck source=scripts/dwm-packages.sh
. "$repo/scripts/dwm-packages.sh"
[[ $(dwm_packages arch rust-toolchain | paste -sd ' ') == 'rustup cargo-update' ]] ||
	fail 'the rust-toolchain profile is not rustup and cargo-update'
dwm_packages arch recommended | grep -Fxq rustup || fail 'rustup is not in the recommended packages'
dwm_packages arch recommended | grep -Fxq cargo-update || fail 'cargo-update is not in the recommended packages (#238)'
other() { # PATH [PROVIDER]
	# shellcheck disable=SC2016 # expanded by the inner shell
	env PATH="$1" STUB_RUST_PROVIDER="${2:-}" bash -c '. "$0"; dwm_other_rust_toolchain' "$repo/scripts/dwm-packages.sh"
}
[[ $(other "$work/bin:$work/sys" rust) == rust ]] || fail "Arch's rust was not found"
[[ $(other "$work/bin:$work/sys" rust-nightly-bin) == rust-nightly-bin ]] || fail 'another rust provider was not found'
if other "$work/bin:$work/sys" rustup >/dev/null; then fail 'rustup itself counted as another toolchain'; fi
mkdir -p "$work/rustupsh"
ln -sf "$work/bin/cargo" "$work/rustupsh/cargo"
[[ $(other "$work/rustupsh:$work/sys") == "$work/rustupsh/cargo" ]] || fail 'a rustup.rs cargo on PATH was not found'
if other "$work/sys" >/dev/null; then fail 'a toolchain was found where there is none'; fi
# pacman alone, without the stub cargo: a machine whose only Rust is a package.
mkdir -p "$work/pacman-only"
ln -sf "$work/bin/pacman" "$work/pacman-only/pacman"
installs() { # PROVIDER
	# shellcheck disable=SC2016 # expanded by the inner shell
	env PATH="$work/pacman-only:$work/sys" STUB_RUST_PROVIDER="$1" bash -c '
		. "$0"
		DISTRO_FAMILY=arch
		install_packages() { printf "INSTALL %s\n" "$*"; }
		dwm_install_package_profile rust-toolchain' "$repo/scripts/dwm-packages.sh" 2>/dev/null
}
[[ $(installs '') == 'INSTALL rustup cargo-update' ]] || fail 'rustup was not installed on a machine without Rust'
[[ $(installs rust) == 'INSTALL cargo-update' ]] || fail "rustup was installed beside Arch's rust, or cargo-update was not"
[[ $(installs rust-nightly-bin) == 'INSTALL cargo-update' ]] || fail 'rustup was installed beside another provider'
[[ $(installs rustup) == 'INSTALL rustup cargo-update' ]] || fail 'an installed rustup was treated as another toolchain'
# Arch's rustup package with its cargo on PATH (/usr/bin/cargo, an absolute
# path): neither skipped, as that cargo is the package's, not rustup.rs's.
# shellcheck disable=SC2016 # expanded by the inner shell
out=$(env PATH="$work/pacman-only:$work/rustupsh:$work/sys" STUB_RUST_PROVIDER=rustup bash -c '
	. "$0"
	DISTRO_FAMILY=arch
	install_packages() { printf "INSTALL %s\n" "$*"; }
	dwm_install_package_profile rust-toolchain' "$repo/scripts/dwm-packages.sh" 2>&1)
[[ $out == 'INSTALL rustup cargo-update' ]] || fail "packaged rustup with cargo on PATH: $out"
# A rustup.rs cargo, which no package provides: neither, or pacman would pull in
# Arch's rust beside it for cargo-update's dependency on cargo.
# shellcheck disable=SC2016 # expanded by the inner shell
out=$(env PATH="$work/pacman-only:$work/rustupsh:$work/sys" STUB_RUST_PROVIDER='' bash -c '
	. "$0"
	DISTRO_FAMILY=arch
	install_packages() { printf "INSTALL %s\n" "$*"; }
	dwm_install_package_profile rust-toolchain' "$repo/scripts/dwm-packages.sh" 2>&1)
[[ $out != *INSTALL* && $out == *'skipping cargo-update (run cargo install cargo-update)'* ]] ||
	fail "beside a rustup.rs cargo: $out"

# install.sh: the skip flag, the plan line, a guarded toolchain install, and the
# build last, after the sudo timestamp is closed.
"$repo/install.sh" --dry-run --non-interactive --profile recommended >"$work/plan"
grep -Fq 'Topgrade: the newest release from crates.io, built with cargo' "$work/plan" ||
	fail "the install plan: $(grep Topgrade "$work/plan")"
"$repo/install.sh" --dry-run --non-interactive --profile full --skip-topgrade >"$work/skip-plan"
grep -Fqx '  Topgrade: skipped (--skip-topgrade)' "$work/skip-plan" || fail '--skip-topgrade is not in the plan'
DWM_INSTALL_TOPGRADE=false "$repo/install.sh" --dry-run --non-interactive --profile full >"$work/env-plan"
grep -Fqx '  Topgrade: skipped (--skip-topgrade)' "$work/env-plan" || fail 'DWM_INSTALL_TOPGRADE=false was ignored'
if DWM_INSTALL_TOPGRADE=maybe "$repo/install.sh" --dry-run --non-interactive >/dev/null 2>&1; then
	fail 'an unsupported DWM_INSTALL_TOPGRADE was accepted'
fi
"$repo/install.sh" --dry-run --non-interactive --profile core >"$work/core-plan"
if grep -Fq 'Topgrade: the newest' "$work/core-plan"; then fail 'a core install plans Topgrade'; fi
grep -Fq 'if dwm_install_package_profile rust-toolchain; then' "$repo/install.sh" ||
	fail 'the toolchain install is not guarded'
displays=$(grep -n '^configure_displays_after_install$' "$repo/install.sh" | cut -d: -f1)
sudo_k=$(grep -nF 'sudo -k 2>/dev/null' "$repo/install.sh" | cut -d: -f1)
# shellcheck disable=SC2016 # the literal text in install.sh
build=$(grep -nF 'if "$REPO_DIR/scripts/install-topgrade"; then' "$repo/install.sh" | cut -d: -f1)
last_sudo=$(grep -nE '^[[:space:]]*sudo [a-z]' "$repo/install.sh" | grep -v 'sudo -k' | tail -n 1 | cut -d: -f1)
[[ -n $displays && -n $sudo_k && -n $build && -n $last_sudo ]] || fail 'could not find the build steps in install.sh'
((sudo_k > displays && build > sudo_k && build > last_sudo)) ||
	fail "install.sh does not build Topgrade last, after sudo -k (displays $displays, sudo -k $sudo_k, build $build, last sudo $last_sudo)"

# The live medium: install.sh skips it, and it is built once the passwordless
# sudoers file is gone.
postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
grep -Fq './install.sh --non-interactive --profile full --skip-topgrade' "$postinstall" ||
	fail 'the live medium does not skip Topgrade in install.sh'
# shellcheck disable=SC2016 # the literal text in the postinstall
# The last removal: the one after install.sh (an earlier one clears a stale copy).
removed=$(grep -n '^rm -f -- "$install_sudoers"$' "$postinstall" | tail -n 1 | cut -d: -f1)
topgrade=$(grep -n 'run_logged "Building Topgrade' "$postinstall" | cut -d: -f1)
if [[ -z $removed || -z $topgrade ]] || ((topgrade <= removed)); then
	fail 'the live medium builds Topgrade before its sudoers file is removed'
fi
grep -Eq '^[[:space:]]+install_networkmanager setup_swap_if_needed install_qemu_guest_utils install_topgrade$' "$postinstall" ||
	fail 'install_topgrade is not exported for run_logged'
# The postinstall's own install_topgrade, against a stub arch-chroot: rustup only
# when the target has no other Rust toolchain, and the build as the user either way.
awk '/^install_topgrade\(\) \{$/ { f = 1 } f { print } f && /^}$/ { exit }' "$postinstall" >"$work/install_topgrade.sh"
grep -q '^}$' "$work/install_topgrade.sh" || fail 'could not find install_topgrade in the postinstall'
cat >"$work/bin/arch-chroot" <<'EOF'
#!/bin/bash
shift
printf 'chroot %s\n' "$*" >>"$STUB_DIR/chroot.log"
if [[ $1 == bash ]]; then
	[[ -n ${STUB_TARGET_RUST:-} ]] || exit 1
	printf '%s\n' "$STUB_TARGET_RUST"
fi
EOF
chmod +x "$work/bin/arch-chroot"
postinstall_topgrade() { # TARGET-RUST
	rm -f "$work/chroot.log"
	# shellcheck disable=SC2016 # expanded by the inner shell
	env PATH="$work/bin:$work/sys" STUB_TARGET_RUST="$1" TARGET=/mnt target_user=alice target_home=/home/alice \
		bash -c '. "$1"; . "$2"; install_topgrade' _ "$repo/scripts/dwm-packages.sh" "$work/install_topgrade.sh" >/dev/null
}
postinstall_topgrade '' || fail 'the postinstall Topgrade step failed'
grep -Fqx 'chroot pacman -S --noconfirm --needed rustup cargo-update' "$work/chroot.log" ||
	fail "the postinstall did not install rustup and cargo-update: $(cat "$work/chroot.log")"
postinstall_topgrade rust || fail 'the postinstall Topgrade step failed beside Arch rust'
! grep -Fq 'rustup' "$work/chroot.log" || fail "the postinstall installed rustup beside Arch's rust"
grep -Fqx 'chroot pacman -S --noconfirm --needed cargo-update' "$work/chroot.log" ||
	fail "the postinstall did not install cargo-update beside Arch's rust: $(cat "$work/chroot.log")"
postinstall_topgrade "$work/rustupsh/cargo" || fail 'the postinstall Topgrade step failed beside a rustup.rs cargo'
! grep -Fq 'pacman -S' "$work/chroot.log" || fail 'the postinstall installed packages beside a rustup.rs cargo'
grep -Fq 'su - alice -c' "$work/chroot.log" || fail 'the postinstall did not build Topgrade as the user beside Arch rust'

printf 'install-topgrade: PASS\n'
