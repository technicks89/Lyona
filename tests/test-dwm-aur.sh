#!/usr/bin/env bash
set -euo pipefail

# #281: scripts/dwm-aur.sh, the one way lyona builds from the AUR, against stub
# git and makepkg. Checked: the pin table and lookups; a fetch takes the pinned
# commit, refuses a different head and a source without a checksum; a build
# copies only real packages (not -debug splits) and stops at its time limit;
# build-pinned leaves nothing behind.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

helper=$repo/scripts/dwm-aur.sh
mkdir -p "$work/bin"
# git: clone makes the directory and a PKGBUILD (STUB_GIT=fail fails it);
# checkout records the commit; rev-parse reports it, or STUB_HEAD.
cat >"$work/bin/git" <<'EOF'
#!/bin/bash
printf 'git %s\n' "$*" >>"$STUB_LOG"
if [[ $1 == clone ]]; then
	[[ ${STUB_GIT:-} != fail ]] || exit 128
	mkdir -p "${*: -1}"
	: >"${*: -1}/PKGBUILD"
	exit 0
fi
dir=$2
shift 2
while [[ $1 == -c ]]; do shift 2; done
case $1 in
checkout) printf '%s\n' "${*: -1}" >"$dir/.head" ;;
rev-parse) printf '%s\n' "${STUB_HEAD:-$(cat "$dir/.head")}" ;;
esac
EOF
# makepkg: --printsrcinfo per STUB_SRCINFO (ok, nosum, skip); a build writes a
# package, its -debug split and a signature, or fails (STUB_BUILD=fail), or
# hangs (STUB_BUILD=hang).
cat >"$work/bin/makepkg" <<'EOF'
#!/bin/bash
if [[ $1 == --printsrcinfo ]]; then
	printf 'pkgbase = demo\n\tsource = demo.tar.gz::https://example.org/demo.tar.gz\n'
	case ${STUB_SRCINFO:-ok} in
	ok) printf '\tsha256sums = abc\n' ;;
	skip) printf '\tsha256sums = SKIP\n' ;;
	esac
	printf '\npkgname = demo\n'
	exit 0
fi
printf 'makepkg %s (uid %s)\n' "$*" "$(id -u)" >>"$STUB_LOG"
case ${STUB_BUILD:-ok} in
fail) exit 4 ;;
hang) exec sleep 30 ;;
esac
: >demo-1.0-1-x86_64.pkg.tar.zst
: >demo-1.0-1-x86_64.pkg.tar.zst.sig
: >demo-debug-1.0-1-x86_64.pkg.tar.zst
EOF
chmod +x "$work/bin/git" "$work/bin/makepkg"
export STUB_LOG=$work/log PATH="$work/bin:$PATH"
aur() { bash "$helper" "$@"; }

# ── the pin table ─────────────────────────────────────────────────────────
[[ $(aur bases | paste -sd ' ') == 'yay-bin topgrade-bin nvidia-580xx-utils nvidia-470xx-utils' ]] ||
	fail "the pinned bases: $(aur bases | paste -sd ' ')"
[[ $(aur pin yay-bin) == 13e0a4754d106a9252b7479bf1b370fbe454fc48 ]] || fail 'yay-bin pin'
if aur pin something-else 2>/dev/null; then fail 'an unpinned base got a commit'; fi

# ── fetch ─────────────────────────────────────────────────────────────────
: >"$work/log"
srcinfo=$(aur fetch yay-bin "$work/f1") || fail 'a clean fetch failed'
[[ $srcinfo == *'sha256sums = abc'* ]] || fail "fetch did not print the .SRCINFO: $srcinfo"
grep -Fqx "git clone --quiet -- https://aur.archlinux.org/yay-bin.git $work/f1" "$work/log" ||
	fail "the clone: $(grep clone "$work/log")"
grep -Fq 'checkout --quiet --detach 13e0a4754d106a9252b7479bf1b370fbe454fc48' "$work/log" || fail 'not checked out at the pin'
if aur fetch yay-bin "$work/f1" 2>/dev/null; then fail 'a fetch into an existing directory was accepted'; fi
if aur fetch not-pinned "$work/f2" 2>/dev/null; then fail 'an unpinned base was fetched'; fi
if STUB_GIT=fail aur fetch yay-bin "$work/f3" 2>/dev/null; then fail 'a failed clone was accepted'; fi
if STUB_HEAD=0000000000000000000000000000000000000000 aur fetch yay-bin "$work/f4" 2>/dev/null; then
	fail 'a head other than the pin was accepted'
fi
for bad in nosum skip; do
	if STUB_SRCINFO=$bad aur fetch yay-bin "$work/f-$bad" 2>"$work/err"; then
		fail "a source without a checksum ($bad) was accepted"
	fi
	grep -Fq 'has a source without a checksum' "$work/err" || fail "$bad: $(cat "$work/err")"
done

# ── build ─────────────────────────────────────────────────────────────────
mkdir -p "$work/out"
out=$(aur build "$work/f1" "$work/out") || fail 'a clean build failed'
[[ $out == "$work/out/demo-1.0-1-x86_64.pkg.tar.zst" ]] || fail "the build printed: $out"
[[ ! -e $work/out/demo-debug-1.0-1-x86_64.pkg.tar.zst && ! -e $work/out/demo-1.0-1-x86_64.pkg.tar.zst.sig ]] ||
	fail 'a -debug split or a signature was copied'
grep -Fqx "makepkg --noconfirm --nocheck (uid $(id -u))" "$work/log" || fail "makepkg ran as: $(grep makepkg "$work/log")"
if aur build "$work/nowhere" "$work/out" 2>/dev/null; then fail 'a build without a PKGBUILD was accepted'; fi
if STUB_BUILD=fail aur build "$work/f1" "$work/out" 2>/dev/null; then fail 'a failed makepkg was accepted'; fi
start=$SECONDS
if STUB_BUILD=hang DWM_AUR_BUILD_SECONDS=1 aur build "$work/f1" "$work/out" 2>/dev/null; then
	fail 'a build past its time limit was accepted'
fi
((SECONDS - start < 15)) || fail 'the build time limit did not stop makepkg'

# ── build-pinned ──────────────────────────────────────────────────────────
mkdir -p "$work/pinned"
out=$(aur build-pinned topgrade-bin "$work/pinned") || fail 'build-pinned failed'
[[ $out == "$work/pinned/demo-1.0-1-x86_64.pkg.tar.zst" ]] || fail "build-pinned printed: $out"
[[ $(find "$work/pinned" -mindepth 1 | wc -l) == 1 ]] || fail "build-pinned left more than its package: $(ls -A "$work/pinned")"
mkdir -p "$work/failed"
if STUB_BUILD=fail aur build-pinned topgrade-bin "$work/failed" 2>/dev/null; then fail 'a failed build-pinned succeeded'; fi
[[ -z $(ls -A "$work/failed") ]] || fail "a failed build-pinned left: $(ls -A "$work/failed")"

# ── install.sh's yay-bin bootstrap goes through it ───────────────────────
awk '/^ensure_yay_installed\(\) \{$/ { f = 1 } f { print } f && /^}$/ { exit }' "$repo/install.sh" >"$work/yay.sh"
grep -q '^ensure_yay_installed() {$' "$work/yay.sh" || fail 'ensure_yay_installed is missing from install.sh'
mkdir -p "$work/repo/scripts" "$work/ybin"
# The helper as install.sh runs it: builds a yay-bin package (STUB_YAY=fail
# fails), and logs how it was called.
cat >"$work/repo/scripts/dwm-aur.sh" <<'EOF'
printf 'dwm-aur %s\n' "$*" >>"$STUB_LOG"
[[ ${STUB_YAY:-} != fail ]] || exit 1
: >"$3/yay-bin-13.0.1-1-x86_64.pkg.tar.zst"
printf '%s\n' "$3/yay-bin-debug-13.0.1-1-x86_64.pkg.tar.zst" "$3/yay-bin-13.0.1-1-x86_64.pkg.tar.zst"
EOF
cat >"$work/ybin/sudo" <<'EOF'
#!/bin/sh
printf 'sudo %s\n' "$*" >>"$STUB_LOG"
EOF
chmod +x "$work/ybin/sudo"
# Only the tools it needs: this machine's own yay would make it skip itself.
for tool in bash env mktemp rm mkdir cat; do
	ln -sf "$(command -v "$tool")" "$work/ybin/$tool"
done
yay_bootstrap() { # NON_INTERACTIVE, with STUB_ settings in the environment
	# shellcheck disable=SC2016 # expanded by the inner bash
	env PATH="$work/ybin:$work/bin" REPO_DIR="$work/repo" NON_INTERACTIVE="$1" bash -c '
		info() { printf "info %s\n" "$*"; }
		ok() { printf "ok %s\n" "$*"; }
		warn() { printf "warn %s\n" "$*"; }
		. "$1"
		ensure_yay_installed' sh "$work/yay.sh"
}
: >"$work/log"
yay_bootstrap true >"$work/yay.out" || fail "the yay bootstrap failed: $(cat "$work/yay.out")"
grep -Eq '^dwm-aur build-pinned yay-bin /' "$work/log" || fail "the helper was not used: $(cat "$work/log")"
grep -Eqx 'sudo pacman -U --needed --noconfirm -- /.*/yay-bin-13\.0\.1-1-x86_64\.pkg\.tar\.zst' "$work/log" ||
	fail "yay-bin was installed as: $(grep sudo "$work/log")"
if grep -q 'makepkg' "$work/log"; then fail 'install.sh ran makepkg itself'; fi
: >"$work/log"
yay_bootstrap false >/dev/null
grep -Eqx 'sudo pacman -U --needed -- /.*/yay-bin-13\.0\.1-1-x86_64\.pkg\.tar\.zst' "$work/log" ||
	fail "an interactive install answered for the user: $(grep sudo "$work/log")"
: >"$work/log"
if STUB_YAY=fail yay_bootstrap true >"$work/yay.out"; then fail 'a failed yay-bin build reported success'; fi
grep -q '^sudo' "$work/log" && fail 'a failed build still ran pacman'
grep -Fq 'continuing without an AUR helper' "$work/yay.out" || fail "a failed build said: $(cat "$work/yay.out")"

printf 'dwm-aur.sh pins, fetch checks, build and time limit; install.sh yay-bin through it: PASS\n'
