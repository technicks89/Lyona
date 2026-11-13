#!/usr/bin/env bash
# Build one aarch64 release image inside the Arch Linux ARM container the
# release workflow runs (ARM5-01): the generic installer ISO or the Raspberry Pi
# image. Run it as root in the image scripts/ci-archlinuxarm-image.sh builds,
# on an aarch64 Docker host, privileged, with the checkout at /src:
#
#   docker run --rm --privileged -v "$PWD:/src" -v "$OUT:/out" -w /src \
#       lyona-archlinuxarm:base-devel scripts/ci-release-aarch64.sh iso|rpi /out
#
# It leaves exactly one file in OUT: lyona-VERSION-aarch64.iso for `iso`,
# lyona-VERSION-rpi-aarch64.img.xz for `rpi`. The builders' own working files
# (the ISO's profile, the Pi image's checksum file) stay out of it, so the
# workflow uploads the directory as it is and the release's SHA256SUMS lists
# the image once.
#
# Arch Linux ARM does not package archiso 91, which the aarch64 ISO needs
# (docs/RELEASING.md): its mkarchiso and releng profile come from a clone of
# the archiso repository, pinned to the commit v91 points at.
set -euo pipefail

kind=${1:-}
out=${2:-}
# git rev-parse 'v91^{}', checked by the clone below.
archiso_commit=723da192226e1c9d5def9168f13332793c82a85e

die() {
	printf 'ci-release-aarch64: %s\n' "$*" >&2
	exit 1
}

[[ $kind == iso || $kind == rpi ]] || die "usage: $0 iso|rpi OUT_DIR"
[[ -n $out && -d $out ]] || die "the output directory must exist: ${out:-<none>}"
[[ $(uname -m) == aarch64 ]] || die "this builds natively and needs an aarch64 host, not $(uname -m)"
((EUID == 0)) || die "run as root"

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo"
# The mounted checkout belongs to another user.
git config --global --add safe.directory "$repo"
work=$(mktemp -d /var/tmp/lyona-release.XXXXXX)
trap 'rm -rf -- "$work"' EXIT

# Exactly one file matching GLOB (a directory and a pattern) into OUT.
publish() {
	local -a found
	mapfile -t found < <(find "$1" -maxdepth 1 -type f -name "$2")
	((${#found[@]} == 1)) || die "expected one $2 under $1, found ${#found[@]}"
	install -m 0644 -- "${found[0]}" "$out/"
}

case $kind in
iso)
	pacman -Syu --noconfirm --needed git rsync arch-install-scripts squashfs-tools \
		libisoburn mtools dosfstools erofs-utils mkinitcpio-archiso grub systemd-ukify
	git clone --quiet https://gitlab.archlinux.org/archlinux/archiso.git "$work/archiso"
	git -C "$work/archiso" checkout --quiet --detach "$archiso_commit"
	[[ $(git -C "$work/archiso" rev-parse HEAD) == "$archiso_commit" ]] || die "archiso is not at $archiso_commit"
	LYONA_MKARCHISO=$work/archiso/archiso/mkarchiso \
		LYONA_RELENG_DIR=$work/archiso/configs/releng \
		scripts/build-lyona-arch-iso.sh --arch aarch64 --output "$work/iso"
	publish "$work/iso" 'lyona-*-aarch64.iso'
	;;
rpi)
	pacman -Syu --noconfirm --needed git rsync arch-install-scripts util-linux \
		e2fsprogs dosfstools mtools xz
	scripts/build-lyona-rpi-image.sh --output "$work/rpi"
	publish "$work/rpi" 'lyona-*-rpi-aarch64.img.xz'
	;;
esac
