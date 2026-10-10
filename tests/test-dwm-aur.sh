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
# hangs (STUB_BUILD=hang). It writes them where makepkg would: PKGDEST from the
# environment, else the makepkg.conf one (STUB_CONF_PKGDEST), else here.
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
dest=${PKGDEST:-${STUB_CONF_PKGDEST:-.}}
: >"$dest/demo-1.0-1-x86_64.pkg.tar.zst"
: >"$dest/demo-1.0-1-x86_64.pkg.tar.zst.sig"
: >"$dest/demo-debug-1.0-1-x86_64.pkg.tar.zst"
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
# A PKGDEST in the user's makepkg.conf does not move the packages away.
mkdir -p "$work/conf-pkgdest" "$work/out2"
aur fetch yay-bin "$work/f5" >/dev/null 2>&1 || fail 'a clean fetch failed'
out=$(STUB_CONF_PKGDEST=$work/conf-pkgdest aur build "$work/f5" "$work/out2") ||
	fail 'a build with PKGDEST set in makepkg.conf found no package'
[[ $out == "$work/out2/demo-1.0-1-x86_64.pkg.tar.zst" && -z $(ls -A "$work/conf-pkgdest") ]] ||
	fail "PKGDEST from makepkg.conf was used: $out"
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

# ── yay-bin is built through it, by the one script that installs yay ─────
# (#339: scripts/install-yay, for install.sh and the live medium alike;
# tests/test-install-yay.sh runs it.)
grep -Fq 'bash "$aur" build-pinned "$base" "$dest"' "$repo/scripts/install-yay" ||
	fail 'install-yay does not build through dwm-aur.sh'
grep -Fq 'build_pin yay-bin' "$repo/scripts/install-yay" || fail 'install-yay does not build yay-bin'
if grep -n 'build-pinned yay-bin' "$repo/install.sh" "$repo/archiso/airootfs/root/lyona-postinstall.sh" | grep -q .; then
	fail 'install.sh or the postinstall builds yay-bin apart from install-yay'
fi

printf 'dwm-aur.sh pins, fetch checks, build and time limit; yay-bin through install-yay: PASS\n'
