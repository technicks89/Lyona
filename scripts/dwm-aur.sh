#!/usr/bin/env bash
# The one way lyona builds from the AUR (#281, decision D-27,
# docs/AUR-PACKAGES.md): a base at the commit pinned below, whose PKGBUILD was
# reviewed, built with makepkg as the calling user (never root), within a time
# limit, after checking that every source it downloads has a checksum. It only
# builds: the caller installs the packages with pacman -U, as root.
#
#   dwm-aur.sh pin BASE                The pinned commit of BASE.
#   dwm-aur.sh bases                   Every pinned base, one per line.
#   dwm-aur.sh fetch BASE DIR          BASE at its pinned commit, cloned into DIR
#                                      (which must not exist) and checked; prints
#                                      its .SRCINFO, for a caller that installs
#                                      the build dependencies first.
#   dwm-aur.sh build DIR OUTDIR        makepkg in DIR, a fetched base; copies the
#                                      packages it built (not -debug splits) into
#                                      OUTDIR and prints their paths.
#   dwm-aur.sh build-pinned BASE OUTDIR
#                                      fetch and build, in a private directory
#                                      removed afterwards.
#
# Run it with bash (installed, it is shared code in PREFIX/lib/lyona, not a
# command). DWM_AUR_URL replaces https://aur.archlinux.org, for tests;
# DWM_AUR_BUILD_SECONDS the build's time limit (1800). Needs git and makepkg.
set -euo pipefail

# The reviewed pins, AUR base<TAB>commit<TAB>what it is. Re-pin only after
# reviewing the PKGBUILD's diff since the last pin, and update
# docs/AUR-PACKAGES.md; make check-aur-policy reads this table.
readonly aur_pins='yay-bin	13e0a4754d106a9252b7479bf1b370fbe454fc48	yay 13.0.1, the user'"'"'s AUR helper
topgrade-bin	478487d31444ccbad24ab5d390d41466201b9dbc	Topgrade 17.12.3-1 (#245)
nvidia-580xx-utils	3d31a20c08a1e6c11c1abe953954f44158c9a592	legacy NVIDIA 580xx 580.178.04-2
nvidia-470xx-utils	af0b7617132e32dd39174779aa8ced2a726afc51	legacy NVIDIA 470xx 470.256.02-8.03'

readonly aur_url=${DWM_AUR_URL:-https://aur.archlinux.org}
readonly build_seconds=${DWM_AUR_BUILD_SECONDS:-1800}

say() { printf 'dwm-aur: %s\n' "$*" >&2; }
die() {
	say "$*"
	exit 1
}

pin_of() {
	local ref
	ref=$(awk -F '\t' -v base="$1" '$1 == base { print $2; exit }' <<<"$aur_pins")
	[[ $ref =~ ^[0-9a-f]{40}$ ]] || return 1
	printf '%s\n' "$ref"
}

# Every source has a checksum, and none is SKIP: the pin covers the PKGBUILD,
# the checksums what it downloads.
sources_checksummed() {
	awk -v arch="$(uname -m)" '
		{ sub(/^[ \t]+/, "") }
		$1 == "source" || $1 == "source_" arch { sources++ }
		$1 ~ "^(sha256|sha512|b2)sums(_" arch ")?$" { sums[$1]++; if ($3 == "SKIP") skipped = 1 }
		END {
			if (!sources || skipped) exit 1
			for (kind in sums) {
				base = kind; sub("_" arch "$", "", base)
				total[base] += sums[kind]
			}
			for (base in total) if (total[base] == sources) exit 0
			exit 1
		}' <<<"$1"
}

not_root() {
	(($(id -u) != 0)) || die 'run as the building user, not as root: makepkg refuses root'
	local tool
	for tool in git makepkg; do
		command -v "$tool" >/dev/null 2>&1 ||
			die "$tool is not installed; install base-devel and git (sudo pacman -S --needed base-devel git)"
	done
}

fetch() {
	local base=$1 dir=$2 ref srcinfo
	ref=$(pin_of "$base") || die "no pinned commit for $base"
	[[ ! -e $dir ]] || die "$dir already exists"
	say "fetching $base from the AUR at ${ref:0:12}..."
	git clone --quiet -- "$aur_url/$base.git" "$dir" >&2 || die "could not clone $base"
	git -C "$dir" -c advice.detachedHead=false checkout --quiet --detach "$ref" >&2 ||
		die "$base has no commit ${ref:0:12}"
	[[ $(git -C "$dir" rev-parse HEAD) == "$ref" ]] || die "$base is not at its pinned commit"
	srcinfo=$(cd "$dir" && makepkg --printsrcinfo) || die "could not read $base's .SRCINFO"
	sources_checksummed "$srcinfo" ||
		die "$base at ${ref:0:12} has a source without a checksum; not building it"
	printf '%s\n' "$srcinfo"
}

build() {
	local dir=$1 out=$2 package built=0
	[[ -f $dir/PKGBUILD ]] || die "$dir holds no PKGBUILD"
	[[ -d $out && -w $out ]] || die "$out is not a writable directory"
	(cd "$dir" && timeout --kill-after=30 "$build_seconds" makepkg --noconfirm --nocheck >&2) ||
		die "makepkg failed in $dir"
	for package in "$dir"/*.pkg.tar.*; do
		[[ -f $package && $package != *.sig && $package != *-debug-[0-9]* ]] || continue
		install -m 0644 -- "$package" "$out/" || die "could not copy ${package##*/}"
		printf '%s\n' "$out/${package##*/}"
		built=1
	done
	((built)) || die "makepkg finished in $dir, but built no package"
}

build_pinned() {
	local base=$1 out=$2 work status=0
	[[ -d $out && -w $out ]] || die "$out is not a writable directory"
	work=$(mktemp -d "$out/.$base.XXXXXX") || die "cannot create a build directory in $out"
	# shellcheck disable=SC2064 # this run's directory, fixed now
	trap "rm -rf -- '$work'" EXIT
	(fetch "$base" "$work/src" >/dev/null && build "$work/src" "$out") || status=$?
	rm -rf -- "$work"
	trap - EXIT
	return "$status"
}

case ${1:-} in
pin)
	(($# == 2)) || die 'usage: dwm-aur.sh pin BASE'
	pin_of "$2" || die "no pinned commit for $2"
	;;
bases)
	(($# == 1)) || die 'usage: dwm-aur.sh bases'
	cut -f1 <<<"$aur_pins"
	;;
fetch)
	(($# == 3)) || die 'usage: dwm-aur.sh fetch BASE DIR'
	not_root
	fetch "$2" "$3"
	;;
build)
	(($# == 3)) || die 'usage: dwm-aur.sh build DIR OUTDIR'
	not_root
	build "$2" "$3"
	;;
build-pinned)
	(($# == 3)) || die 'usage: dwm-aur.sh build-pinned BASE OUTDIR'
	not_root
	build_pinned "$2" "$3"
	;;
*)
	die 'usage: dwm-aur.sh pin|bases|fetch|build|build-pinned ...'
	;;
esac
