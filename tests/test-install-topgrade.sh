#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 15 S15-06 (decision D-28): scripts/install-topgrade against a stub
# cargo and rustup, and its place in install.sh.
#
# - The pinned version is built with --locked, into ~/.cargo/bin.
# - With no toolchain set, rustup's stable toolchain is installed (minimal
#   profile) and made the default; one already set is left alone.
# - An installed matching version is not rebuilt (unless --force).
# - A dry run changes nothing; root, a missing cargo, a failed build and a
#   wrong version all fail.
# - install.sh installs rustup through the map, never over Arch's rust, and
#   runs this after the shell configuration that puts ~/.cargo/bin on PATH.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

installer=$repo/scripts/install-topgrade
version=$(sed -n 's/^readonly TOPGRADE_VERSION=//p' "$installer")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "the pinned version is '$version'"
export HOME=$work/home STUB_DIR=$work
unset CARGO_HOME
mkdir -p "$HOME"

# cargo: logs its arguments; `install` writes a topgrade that reports
# STUB_BUILT_VERSION (default: the version asked for), or fails with STUB_CARGO=fail.
cat >"$work/bin/cargo" <<'EOF'
#!/bin/bash
printf 'cargo %s\n' "$*" >>"$STUB_DIR/log"
[[ ${STUB_CARGO:-} != fail ]] || exit 101
[[ $1 == install ]] || exit 0
while (($# > 0)) && [[ $1 != --version ]]; do shift; done
built=${STUB_BUILT_VERSION:-$2}
mkdir -p "$HOME/.cargo/bin"
printf '#!/bin/sh\necho "topgrade %s"\n' "$built" >"$HOME/.cargo/bin/topgrade"
chmod +x "$HOME/.cargo/bin/topgrade"
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
chmod +x "$work/bin/cargo" "$work/bin/rustup"

run() { PATH="$work/bin:$PATH" "$installer" "$@"; }
reset() { rm -rf "$HOME/.cargo" "$work/log" "$work/toolchain"; }

# No toolchain yet: stable, minimal, made the default, then the pinned build.
reset
run >/dev/null || fail 'the install failed'
expected="rustup show active-toolchain
rustup toolchain install stable --profile minimal
rustup default stable
cargo install --locked --version $version topgrade"
[[ $(cat "$work/log") == "$expected" ]] || fail "the install ran: $(cat "$work/log")"
[[ $("$HOME/.cargo/bin/topgrade" --version) == "topgrade $version" ]] || fail 'no topgrade was installed'

# Installed already: nothing runs.
rm -f "$work/log"
out=$(run)
[[ $out == *"Topgrade $version is already installed"* ]] || fail "a second run: $out"
[[ ! -e $work/log ]] || fail "a second run ran: $(cat "$work/log")"

# --force rebuilds, and a toolchain the user set is left alone.
run --force >/dev/null || fail '--force failed'
[[ $(cat "$work/log") == "rustup show active-toolchain
cargo install --locked --version $version topgrade" ]] || fail "--force ran: $(cat "$work/log")"

# An older Topgrade is upgraded to the pin.
reset
: >"$work/toolchain"
mkdir -p "$HOME/.cargo/bin"
printf '#!/bin/sh\necho "topgrade 1.0.0"\n' >"$HOME/.cargo/bin/topgrade"
chmod +x "$HOME/.cargo/bin/topgrade"
run >/dev/null || fail 'upgrading an older Topgrade failed'
grep -Fqx "cargo install --locked --version $version topgrade" "$work/log" || fail 'an older Topgrade was not upgraded'

# A dry run changes nothing.
reset
out=$(run --dry-run)
[[ $out == *"would build Topgrade $version"* ]] || fail "a dry run: $out"
[[ ! -e $work/log && ! -e $HOME/.cargo ]] || fail 'a dry run changed something'

# Failures.
reset
if STUB_CARGO=fail run >/dev/null 2>&1; then fail 'a failed build was reported as installed'; fi
reset
if STUB_BUILT_VERSION=0.0.1 run >/dev/null 2>&1; then fail 'a wrong version was reported as installed'; fi
mkdir -p "$work/nocargo"
for cmd in bash id sed; do ln -sf "$(command -v "$cmd")" "$work/nocargo/$cmd"; done
out=$(PATH="$work/nocargo" "$installer" 2>&1) && fail 'it succeeded without cargo'
[[ $out == *'install rustup first'* ]] || fail "without cargo: $out"
if run --frobnicate >/dev/null 2>&1; then fail 'an unknown option was accepted'; fi

# install.sh: rustup from the map, not over Arch's rust (compared by exact
# name, since pacman -Qq resolves provides), and Topgrade after the shell
# configuration that puts ~/.cargo/bin on PATH.
# shellcheck source=scripts/dwm-packages.sh
. "$repo/scripts/dwm-packages.sh"
[[ $(dwm_packages arch rust-toolchain) == rustup ]] || fail 'the rust-toolchain profile is not rustup'
dwm_packages arch recommended | grep -Fxq rustup || fail 'rustup is not in the recommended packages'
# shellcheck disable=SC2016 # the literal text in install.sh
grep -Fq '$(pacman -Qq rust 2>/dev/null) == rust' "$repo/install.sh" || fail 'install.sh does not keep an installed rust'
# shellcheck disable=SC2016 # the literal text in install.sh
mybash_line=$(grep -n '"$REPO_DIR/scripts/install-mybash"' "$repo/install.sh" | cut -d: -f1)
# shellcheck disable=SC2016 # the literal text in install.sh
topgrade_line=$(grep -n 'if "$REPO_DIR/scripts/install-topgrade"; then' "$repo/install.sh" | cut -d: -f1)
[[ -n $mybash_line && -n $topgrade_line && $topgrade_line -gt $mybash_line ]] ||
	fail 'install.sh does not run install-topgrade after install-mybash'
"$repo/install.sh" --dry-run --non-interactive --profile recommended >"$work/plan"
grep -Fq "Topgrade: built with cargo from crates.io ($version, rustup toolchain)" "$work/plan" ||
	fail 'the install plan does not list Topgrade'
"$repo/install.sh" --dry-run --non-interactive --profile core >"$work/core-plan"
if grep -Fq 'Topgrade' "$work/core-plan"; then fail 'a core install plans Topgrade'; fi

printf 'install-topgrade: PASS\n'
